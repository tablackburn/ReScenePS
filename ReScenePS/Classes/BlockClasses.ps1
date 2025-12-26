# ReScenePS Block Classes
# Classes for parsing SRR and RAR block structures

using namespace System.IO
using namespace System.Text

#region Block Type Enumeration

enum BlockType {
    # SRR block types (0x69-0x71)
    SrrHeader = 0x69        # i -> SRR file header
    SrrStoredFile = 0x6A    # j -> Stored files (NFO, SFV, etc.)
    SrrOsoHash = 0x6B       # k -> ISDb/OSO hash
    SrrRarPadding = 0x6C    # l -> Padding after RAR end
    SrrRarFile = 0x71       # q -> RAR volume metadata marker

    # RAR block types (0x72-0x7B)
    RarMarker = 0x72        # r -> RAR marker (always first)
    RarVolumeHeader = 0x73  # s -> Archive header
    RarPackedFile = 0x74    # t -> File header (most important!)
    RarOldComment = 0x75
    RarOldAuthenticity76 = 0x76
    RarOldSubblock = 0x77
    RarOldRecovery = 0x78   # x -> Old-style recovery record
    RarOldAuthenticity79 = 0x79
    RarNewSub = 0x7A        # z -> New-style subblock (RR, CMT, AV)
    RarArchiveEnd = 0x7B    # { -> Archive end (optional)
}

# Block type name mapping for display
$script:BlockTypeNames = @{
    0x69 = "SRR Volume Header"
    0x6A = "SRR Stored File"
    0x6B = "SRR ISDb Hash"
    0x6C = "SRR Padding"
    0x71 = "SRR RAR subblock"
    0x72 = "RAR Marker"
    0x73 = "RAR Archive Header"
    0x74 = "RAR File"
    0x75 = "RAR Old style - Comment"
    0x76 = "RAR Old style - Extra info"
    0x77 = "RAR Old style - Subblock"
    0x78 = "RAR Old style - Recovery record"
    0x79 = "RAR Old style - Archive authenticity"
    0x7A = "RAR New-format subblock"
    0x7B = "RAR Archive end"
}

#endregion

#region SRR Block Classes

class SrrBlock {
    # Common header (7 bytes minimum)
    [uint16]$HeadCrc
    [byte]$HeadType
    [uint16]$HeadFlags
    [uint16]$HeadSize

    # Optional field
    [uint32]$AddSize

    # Position in file
    [long]$BlockPosition

    # Raw header data (after common 7 bytes)
    [byte[]]$RawData

    # Constructor from binary data
    SrrBlock([BinaryReader]$reader, [long]$position) {
        $this.BlockPosition = $position

        # Read 7-byte common header
        $this.HeadCrc = $reader.ReadUInt16()
        $this.HeadType = $reader.ReadByte()
        $this.HeadFlags = $reader.ReadUInt16()
        $this.HeadSize = $reader.ReadUInt16()

        # Sanity check
        if ($this.HeadSize -lt 7) {
            throw "Invalid block header size: $($this.HeadSize)"
        }

        # Read remaining header bytes
        $remainingHeaderBytes = $this.HeadSize - 7
        if ($remainingHeaderBytes -gt 0) {
            $this.RawData = $reader.ReadBytes($remainingHeaderBytes)
        }
        else {
            $this.RawData = [byte[]]::new(0)
        }

        # Check for ADD_SIZE field
        $hasAddSize = ($this.HeadFlags -band 0x8000) -or
                      ($this.HeadType -eq 0x74) -or  # RarPackedFile
                      ($this.HeadType -eq 0x7A)      # RarNewSub

        if ($hasAddSize -and $this.RawData.Length -ge 4) {
            $this.AddSize = [BitConverter]::ToUInt32($this.RawData, 0)
        }
        else {
            $this.AddSize = 0
        }

        # Determine if we should skip ADD_SIZE data
        # For SRR files:
        # - SrrStoredFile (0x6A): Skip the file data
        # - RarPackedFile (0x74): Data is NOT in the file (just metadata)
        # - Other blocks: Data might be included
        $shouldSkip = $false

        if ($this.AddSize -gt 0) {
            if ($this.HeadType -eq 0x6A) {
                # SrrStoredFile: Skip the actual file data
                $shouldSkip = $true
            }
            elseif ($this.HeadType -ne 0x74) {
                # Not a RarPackedFile: might have data to skip
                # (RarPackedFile in SRR has no data following it)
                # For other block types, we generally don't skip unless specific handling
                # Let derived classes handle as needed
                $shouldSkip = $false
            }
            # else: RarPackedFile (0x74) - do nothing, data not present in SRR
        }

        if ($shouldSkip) {
            $reader.BaseStream.Seek($this.AddSize, [SeekOrigin]::Current) | Out-Null
        }
    }

    # Get full block bytes (for writing to output)
    [byte[]] GetBlockBytes() {
        $ms = [MemoryStream]::new()
        $writer = [BinaryWriter]::new($ms)

        try {
            $writer.Write($this.HeadCrc)
            $writer.Write($this.HeadType)
            $writer.Write($this.HeadFlags)
            $writer.Write($this.HeadSize)

            if ($this.RawData.Length -gt 0) {
                $writer.Write($this.RawData)
            }

            return $ms.ToArray()
        }
        finally {
            $writer.Dispose()
            $ms.Dispose()
        }
    }

    # Get friendly block type name
    [string] GetTypeName() {
        if ($script:BlockTypeNames.ContainsKey($this.HeadType)) {
            return $script:BlockTypeNames[$this.HeadType]
        }
        return "Unknown (0x{0:X2})" -f $this.HeadType
    }

    # Total size of block in file
    [int] GetTotalSize() {
        return $this.HeadSize + $this.AddSize
    }
}

class SrrHeaderBlock : SrrBlock {
    [string]$AppName

    SrrHeaderBlock([BinaryReader]$reader, [long]$position) : base($reader, $position) {
        $offset = 0

        # Check if app name is present (flag 0x0001)
        if ($this.HeadFlags -band 0x0001) {
            if ($this.RawData.Length -ge 2) {
                $nameLength = [BitConverter]::ToUInt16($this.RawData, $offset)
                $offset += 2

                if ($nameLength -gt 0 -and $offset + $nameLength -le $this.RawData.Length) {
                    $this.AppName = [Encoding]::UTF8.GetString($this.RawData, $offset, $nameLength)
                }
                else {
                    $this.AppName = ""
                }
            }
        }
        else {
            $this.AppName = ""
        }
    }
}

class SrrStoredFileBlock : SrrBlock {
    [string]$FileName
    [uint32]$FileSize

    SrrStoredFileBlock([BinaryReader]$reader, [long]$position) : base($reader, $position) {
        $offset = 0

        # ADD_SIZE is first 4 bytes
        if ($this.RawData.Length -ge 4) {
            $this.FileSize = [BitConverter]::ToUInt32($this.RawData, $offset)
            $offset += 4
        }

        # Name length is next 2 bytes
        if ($this.RawData.Length -ge $offset + 2) {
            $nameLength = [BitConverter]::ToUInt16($this.RawData, $offset)
            $offset += 2

            if ($nameLength -gt 0 -and $offset + $nameLength -le $this.RawData.Length) {
                $this.FileName = [Encoding]::UTF8.GetString($this.RawData, $offset, $nameLength)
            }
        }
    }
}

class SrrRarFileBlock : SrrBlock {
    [string]$FileName

    SrrRarFileBlock([BinaryReader]$reader, [long]$position) : base($reader, $position) {
        $offset = 0

        if ($this.RawData.Length -ge 2) {
            $nameLength = [BitConverter]::ToUInt16($this.RawData, $offset)
            $offset += 2

            if ($nameLength -gt 0 -and $offset + $nameLength -le $this.RawData.Length) {
                $this.FileName = [Encoding]::UTF8.GetString($this.RawData, $offset, $nameLength)
            }
        }
    }
}

#endregion

#region RAR Block Classes

class RarMarkerBlock : SrrBlock {
    # Special case: 0x72 is a fixed marker (52 61 72 21 1a 07 00)
    # Usually no parsing needed, just copy as-is

    RarMarkerBlock([BinaryReader]$reader, [long]$position) : base($reader, $position) {
        # Marker block is always fixed 7 bytes, no additional data
    }
}

class RarVolumeHeaderBlock : SrrBlock {
    # 0x73 - Archive header (MAIN_HEAD)
    [uint16]$Reserved1
    [uint32]$Reserved2

    RarVolumeHeaderBlock([BinaryReader]$reader, [long]$position) : base($reader, $position) {
        $offset = 0

        if ($this.RawData.Length -ge 6) {
            $this.Reserved1 = [BitConverter]::ToUInt16($this.RawData, $offset)
            $offset += 2
            $this.Reserved2 = [BitConverter]::ToUInt32($this.RawData, $offset)
            $offset += 4
        }
    }

    [byte[]] GetBlockBytes() {
        # Return complete block: CRC(2) + HEAD_TYPE(1) + HEAD_FLAGS(2) + HEAD_SIZE(2) + RawData
        $blockBytes = New-Object byte[] ($this.HeadSize)
        $offset = 0

        # CRC16
        [BitConverter]::GetBytes([uint16]$this.HeadCrc).CopyTo($blockBytes, $offset)
        $offset += 2

        # HEAD_TYPE
        $blockBytes[$offset++] = [byte]$this.HeadType

        # HEAD_FLAGS
        [BitConverter]::GetBytes([uint16]$this.HeadFlags).CopyTo($blockBytes, $offset)
        $offset += 2

        # HEAD_SIZE
        [BitConverter]::GetBytes([uint16]$this.HeadSize).CopyTo($blockBytes, $offset)
        $offset += 2

        # RawData (Reserved1 + Reserved2)
        if ($this.RawData.Length -gt 0) {
            [Array]::Copy($this.RawData, 0, $blockBytes, $offset, $this.RawData.Length)
        }

        return $blockBytes
    }
}

class RarPackedFileBlock : SrrBlock {
    # 0x74 - File header (most important for reconstruction)
    [uint32]$PackedSize
    [uint32]$UnpackedSize
    [byte]$HostOs
    [uint32]$FileCrc
    [uint32]$FileDateTime
    [byte]$RarVersion
    [byte]$CompressionMethod
    [uint16]$NameSize
    [uint32]$FileAttributes
    [uint64]$FullPackedSize      # May be 64-bit with LARGE_FILE flag
    [uint64]$FullUnpackedSize    # May be 64-bit with LARGE_FILE flag
    [string]$FileName
    [byte[]]$Salt
    [bool]$HasLargeFile
    [bool]$HasUtf8Name
    [bool]$HasSalt

    RarPackedFileBlock([BinaryReader]$reader, [long]$position) : base($reader, $position) {
        $offset = 0

        # Core 25-byte structure
        if ($this.RawData.Length -ge 25) {
            $this.PackedSize = [BitConverter]::ToUInt32($this.RawData, $offset)
            $offset += 4
            $this.UnpackedSize = [BitConverter]::ToUInt32($this.RawData, $offset)
            $offset += 4
            $this.HostOs = $this.RawData[$offset]
            $offset += 1
            $this.FileCrc = [BitConverter]::ToUInt32($this.RawData, $offset)
            $offset += 4
            $this.FileDateTime = [BitConverter]::ToUInt32($this.RawData, $offset)
            $offset += 4
            $this.RarVersion = $this.RawData[$offset]
            $offset += 1
            $this.CompressionMethod = $this.RawData[$offset]
            $offset += 1
            $this.NameSize = [BitConverter]::ToUInt16($this.RawData, $offset)
            $offset += 2
            $this.FileAttributes = [BitConverter]::ToUInt32($this.RawData, $offset)
            $offset += 4
        }

        # Initialize full sizes with low 32 bits
        $this.FullPackedSize = [uint64]$this.PackedSize
        $this.FullUnpackedSize = [uint64]$this.UnpackedSize

        # Check for LARGE_FILE flag (0x0100)
        $this.HasLargeFile = ($this.HeadFlags -band 0x0100) -eq 0x0100
        if ($this.HasLargeFile -and $this.RawData.Length -ge $offset + 8) {
            $highPackSize = [BitConverter]::ToUInt32($this.RawData, $offset)
            $offset += 4
            $highUnpackSize = [BitConverter]::ToUInt32($this.RawData, $offset)
            $offset += 4
            # Combine high and low 32-bit values into 64-bit
            $this.FullPackedSize = ([uint64]$highPackSize * 0x100000000) + [uint64]$this.PackedSize
            $this.FullUnpackedSize = ([uint64]$highUnpackSize * 0x100000000) + [uint64]$this.UnpackedSize
        }

        # File name (UTF-8 encoded)
        $this.HasUtf8Name = ($this.HeadFlags -band 0x0200) -eq 0x0200
        if ($this.NameSize -gt 0 -and $offset + $this.NameSize -le $this.RawData.Length) {
            $this.FileName = [Encoding]::UTF8.GetString($this.RawData, $offset, $this.NameSize)
            $offset += $this.NameSize
        }

        # Optional SALT field (8 bytes) if flag 0x0400
        $this.HasSalt = ($this.HeadFlags -band 0x0400) -eq 0x0400
        if ($this.HasSalt -and $this.RawData.Length -ge $offset + 8) {
            $this.Salt = $this.RawData[$offset..($offset + 7)]
            $offset += 8
        }

        # EXT_TIME field parsing would go here if needed (flag 0x1000)
        # For now, we skip it
    }

    [byte[]] GetBlockBytes() {
        # Return complete block header (without file data)
        $blockBytes = New-Object byte[] ($this.HeadSize)
        $offset = 0

        # CRC16
        [BitConverter]::GetBytes([uint16]$this.HeadCrc).CopyTo($blockBytes, $offset)
        $offset += 2

        # HEAD_TYPE
        $blockBytes[$offset++] = [byte]$this.HeadType

        # HEAD_FLAGS
        [BitConverter]::GetBytes([uint16]$this.HeadFlags).CopyTo($blockBytes, $offset)
        $offset += 2

        # HEAD_SIZE
        [BitConverter]::GetBytes([uint16]$this.HeadSize).CopyTo($blockBytes, $offset)
        $offset += 2

        # RawData (all the field data after HEAD_SIZE)
        if ($this.RawData.Length -gt 0) {
            [Array]::Copy($this.RawData, 0, $blockBytes, $offset, $this.RawData.Length)
        }

        return $blockBytes
    }
}

class RarEndArchiveBlock : SrrBlock {
    # 0x7B - Archive end block
    [uint32]$ArchiveCrc
    [uint16]$VolumeNumber
    [bool]$HasNextVolume
    [bool]$HasArchiveCrc
    [bool]$HasVolumeNumber

    RarEndArchiveBlock([BinaryReader]$reader, [long]$position) : base($reader, $position) {
        $offset = 0

        # Check flags
        $this.HasNextVolume = ($this.HeadFlags -band 0x0001) -eq 0x0001
        $this.HasArchiveCrc = ($this.HeadFlags -band 0x0002) -eq 0x0002
        $this.HasVolumeNumber = ($this.HeadFlags -band 0x0008) -eq 0x0008

        # Read optional fields based on flags
        if ($this.HasArchiveCrc -and $this.RawData.Length -ge $offset + 4) {
            $this.ArchiveCrc = [BitConverter]::ToUInt32($this.RawData, $offset)
            $offset += 4
        }

        if ($this.HasVolumeNumber -and $this.RawData.Length -ge $offset + 2) {
            $this.VolumeNumber = [BitConverter]::ToUInt16($this.RawData, $offset)
            $offset += 2
        }
    }

    [byte[]] GetBlockBytes() {
        # Return complete block
        $blockBytes = New-Object byte[] ($this.HeadSize)
        $offset = 0

        # CRC16
        [BitConverter]::GetBytes([uint16]$this.HeadCrc).CopyTo($blockBytes, $offset)
        $offset += 2

        # HEAD_TYPE
        $blockBytes[$offset++] = [byte]$this.HeadType

        # HEAD_FLAGS
        [BitConverter]::GetBytes([uint16]$this.HeadFlags).CopyTo($blockBytes, $offset)
        $offset += 2

        # HEAD_SIZE
        [BitConverter]::GetBytes([uint16]$this.HeadSize).CopyTo($blockBytes, $offset)
        $offset += 2

        # RawData (optional fields)
        if ($this.RawData.Length -gt 0) {
            [Array]::Copy($this.RawData, 0, $blockBytes, $offset, $this.RawData.Length)
        }

        return $blockBytes
    }
}

#endregion

#region Block Reader

class BlockReader {
    [FileStream]$Stream
    [BinaryReader]$Reader
    [long]$FileLength
    [string]$FilePath

    BlockReader([string]$srrFilePath) {
        # Resolve to absolute path
        $resolvedPath = (Resolve-Path -Path $srrFilePath -ErrorAction Stop).Path

        if (-not (Test-Path $resolvedPath)) {
            throw "SRR file not found: $resolvedPath"
        }

        $this.FilePath = $resolvedPath
        $this.Stream = [FileStream]::new($resolvedPath, [FileMode]::Open, [FileAccess]::Read)
        $this.Reader = [BinaryReader]::new($this.Stream)
        $this.FileLength = $this.Stream.Length

        # Verify minimum size (20 bytes)
        if ($this.FileLength -lt 20) {
            throw "File too small to be a valid SRR file (minimum 20 bytes)"
        }

        # Verify SRR magic number (69 69 69)
        $magic = $this.Reader.ReadBytes(3)
        if ($magic[0] -ne 0x69 -or $magic[1] -ne 0x69 -or $magic[2] -ne 0x69) {
            throw "Not a valid SRR file (magic number mismatch)"
        }

        # Seek back to start
        $this.Stream.Seek(0, [SeekOrigin]::Begin) | Out-Null
    }

    [SrrBlock] ReadNextBlock() {
        if ($this.Stream.Position -ge $this.FileLength) {
            return $null
        }

        $position = $this.Stream.Position

        # Peek at block type
        $startPos = $this.Stream.Position
        $this.Reader.ReadUInt16() | Out-Null  # HeadCrc
        $blockType = $this.Reader.ReadByte()

        # Seek back to start of block
        $this.Stream.Seek($startPos, [SeekOrigin]::Begin) | Out-Null

        # Instantiate appropriate block class
        $block = switch ($blockType) {
            0x69 { [SrrHeaderBlock]::new($this.Reader, $position) }
            0x6A { [SrrStoredFileBlock]::new($this.Reader, $position) }
            0x6B { [SrrBlock]::new($this.Reader, $position) }  # ISDb hash
            0x6C { [SrrBlock]::new($this.Reader, $position) }  # Padding
            0x71 { [SrrRarFileBlock]::new($this.Reader, $position) }
            0x72 { [RarMarkerBlock]::new($this.Reader, $position) }
            0x73 { [RarVolumeHeaderBlock]::new($this.Reader, $position) }
            0x74 { [RarPackedFileBlock]::new($this.Reader, $position) }
            0x7B { [RarEndArchiveBlock]::new($this.Reader, $position) }
            default { [SrrBlock]::new($this.Reader, $position) }
        }

        return $block
    }

    [Object[]] ReadAllBlocks() {
        $blocks = [System.Collections.Generic.List[Object]]::new()

        while ($this.Stream.Position -lt $this.FileLength) {
            $block = $this.ReadNextBlock()
            if ($null -eq $block) {
                break
            }
            $blocks.Add($block)
        }

        return $blocks.ToArray()
    }

    [void] Close() {
        if ($null -ne $this.Reader) {
            $this.Reader.Dispose()
        }
        if ($null -ne $this.Stream) {
            $this.Stream.Dispose()
        }
    }
}

#endregion
