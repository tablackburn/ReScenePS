#Requires -Modules CRC

# ============================================================================
# IMPORTANT: ALWAYS USE Import-Module FOR THIS FILE
# ============================================================================
# DO NOT dot-source this file with ". .\ReScene.psm1"
# ALWAYS USE: Import-Module .\ReScene.psm1 -Force
#
# Reason: Classes and module loading require proper module scope isolation
# Dot-sourcing causes class scoping issues and will break the module
# ============================================================================

# ReScene PowerShell Module
# Single-file implementation for Phase 1
# Target: PowerShell 7+ (cross-platform)

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

#region Block Classes

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

#region RAR Block Classes (Phase 2)

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

#region EBML Parser Functions

function Get-EbmlUIntLength {
    <#
    .SYNOPSIS
    Returns the number of bytes that will be consumed based on the first byte (Length Descriptor).
    This matches pyrescene's GetUIntLength() function.

    .DESCRIPTION
    EBML uses a variable-length encoding where the first byte indicates how many bytes total
    will be consumed. The first byte's leading 1-bit position determines the byte count:
    - 10xxxxxx = 1 byte (0x80 = 128)
    - 01xxxxxx = 2 bytes (0x40 = 64)
    - 001xxxxx = 3 bytes (0x20 = 32)
    - 0001xxxx = 4 bytes (0x10 = 16)
    - 00001xxx = 5 bytes (0x08 = 8)
    - 000001xx = 6 bytes (0x04 = 4)
    - 0000001x = 7 bytes (0x02 = 2)
    - 00000001 = 8 bytes (0x01 = 1)

    .PARAMETER LengthDescriptor
    First byte read from EBML stream (0-255)

    .OUTPUTS
    [int] Number of bytes (1-8)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte]$LengthDescriptor
    )

    # Test bits from high to low: 128, 64, 32, 16, 8, 4, 2, 1
    for ($i = 0; $i -lt 8; $i++) {
        $testBit = 0x80 -shr $i
        if (($LengthDescriptor -band $testBit) -ne 0) {
            return $i + 1
        }
    }

    # Should never reach here, but return 0 for safety
    return 0
}

function Get-EbmlUInt {
    <#
    .SYNOPSIS
    Reads an EBML variable-length unsigned integer from a buffer.
    This matches pyrescene's GetEbmlUInt() function.

    .DESCRIPTION
    Decodes an EBML variable-length unsigned integer. The first byte contains
    the length descriptor bits which must be masked out before interpreting the value.

    .PARAMETER Buffer
    Byte array to read from

    .PARAMETER Offset
    Starting position in buffer

    .PARAMETER ByteCount
    Number of bytes to consume (from length descriptor)

    .OUTPUTS
    [uint64] The decoded integer value
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$Buffer,

        [Parameter(Mandatory=$true)]
        [int]$Offset,

        [Parameter(Mandatory=$true)]
        [int]$ByteCount
    )

    # Mask out length descriptor bits from first byte: 0xFF >> count gives mask
    [uint64]$mask = 0xFF -shr $ByteCount
    [uint64]$size = [uint64]($Buffer[$Offset] -band $mask)

    # Add remaining bytes (shift left 8 bits each time, then add next byte)
    for ($i = 1; $i -lt $ByteCount; $i++) {
        $size = ($size -shl 8) + [uint64]$Buffer[$Offset + $i]
    }

    return $size
}

function Get-EbmlElementID {
    <#
    .SYNOPSIS
    Reads an EBML Element ID (1-4 bytes) from a byte stream.

    .PARAMETER Buffer
    Byte array to read from

    .PARAMETER Offset
    Starting position in buffer

    .OUTPUTS
    [hashtable] @{ ElementID = [byte[]], Length = [int] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$Buffer,

        [Parameter(Mandatory=$true)]
        [int]$Offset
    )

    $firstByte = $Buffer[$Offset]
    $elementLength = Get-EbmlUIntLength -LengthDescriptor $firstByte

    # Element ID is first byte + (length - 1) more bytes
    $elementID = New-Object byte[] $elementLength
    [System.Array]::Copy($Buffer, $Offset, $elementID, 0, $elementLength)

    return @{
        ElementID = $elementID
        Length = $elementLength
    }
}

function Read-EbmlUIntStream {
    <#
    .SYNOPSIS
    Reads an EBML variable-length unsigned integer from a stream.

    .PARAMETER Stream
    [System.IO.BinaryReader] or similar object with Read method

    .OUTPUTS
    [hashtable] @{ Value = [uint64], BytesConsumed = [int] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Stream
    )

    $firstByteArray = New-Object byte[] 1
    $Stream.Read($firstByteArray, 0, 1) | Out-Null
    $firstByte = $firstByteArray[0]

    $bytesConsumed = Get-EbmlUIntLength -LengthDescriptor $firstByte

    # Mask out length descriptor bits
    [uint64]$mask = 0xFF -shr $bytesConsumed
    [uint64]$size = [uint64]($firstByte -band $mask)

    # Read and append remaining bytes
    for ($i = 1; $i -lt $bytesConsumed; $i++) {
        $byteArray = New-Object byte[] 1
        $Stream.Read($byteArray, 0, 1) | Out-Null
        $size = ($size -shl 8) + [uint64]$byteArray[0]
    }

    return @{
        Value = $size
        BytesConsumed = $bytesConsumed
    }
}

function Get-EbmlElementFromBuffer {
    <#
    .SYNOPSIS
    Reads a complete EBML element from a buffer (ID + size + data).

    .PARAMETER Buffer
    Byte array to read from

    .PARAMETER Offset
    Starting position in buffer

    .OUTPUTS
    [hashtable] @{ ElementID = [byte[]], DataSize = [uint64], ElementData = [byte[]], TotalLength = [int] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$Buffer,

        [Parameter(Mandatory=$true)]
        [int]$Offset
    )

    # Read element ID
    $idResult = Get-EbmlElementID -Buffer $Buffer -Offset $Offset
    $elementID = $idResult.ElementID
    $idLength = $idResult.Length

    # Read element data size (EBML variable-length integer)
    $sizeOffset = $Offset + $idLength
    $firstByte = $Buffer[$sizeOffset]
    $sizeByteCount = Get-EbmlUIntLength -LengthDescriptor $firstByte
    $dataSize = Get-EbmlUInt -Buffer $Buffer -Offset $sizeOffset -ByteCount $sizeByteCount

    # Extract element data
    $dataOffset = $sizeOffset + $sizeByteCount
    $available = [Math]::Max(0, $Buffer.Length - $dataOffset)
    if ($dataSize -gt $available) {
        # Clamp to available bytes to avoid overrun; caller should treat size as suspicious
        $dataSize = [uint64]$available
    }
    $elementData = New-Object byte[] $dataSize
    [System.Array]::Copy($Buffer, $dataOffset, $elementData, 0, [int]$dataSize)

    $totalLength = $idLength + $sizeByteCount + $dataSize

    return @{
        ElementID = $elementID
        DataSize = $dataSize
        ElementData = $elementData
        TotalLength = $totalLength
    }
}

function ConvertTo-EbmlElementString {
    <#
    .SYNOPSIS
    Converts EBML element ID to hex string for display/comparison.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$ElementID
    )

    return ('0x{0}' -f ($ElementID | ForEach-Object { $_.ToString('X2') } | Join-String))
}

#endregion

#region SRS Parser Functions

# EBML Element IDs for SRS (from pyrescene)
$script:SrsEbmlIDs = @{
    'EBML' = [byte[]]@(0x1A, 0x45, 0xDF, 0xA3)
    'Segment' = [byte[]]@(0x18, 0x53, 0x80, 0x67)
    'ReSample' = [byte[]]@(0xC0)
    'ReSampleFile' = [byte[]]@(0xC1)
    'ReSampleTrack' = [byte[]]@(0xC2)
}

function ConvertTo-ByteString {
    <#
    .SYNOPSIS
    Converts a byte array to a hex string for display.
    #>
    param([byte[]]$Bytes)
    return ($Bytes | ForEach-Object { $_.ToString('X2') } | Join-String)
}

function Compare-ByteArray {
    <#
    .SYNOPSIS
    Compares two byte arrays for equality.
    #>
    param(
        [byte[]]$Array1,
        [byte[]]$Array2
    )

    if ($Array1.Length -ne $Array2.Length) {
        return $false
    }

    for ($i = 0; $i -lt $Array1.Length; $i++) {
        if ($Array1[$i] -ne $Array2[$i]) {
            return $false
        }
    }

    return $true
}

function ConvertFrom-SrsFile {
    <#
    .SYNOPSIS
    Parses an SRS file and extracts metadata and track information.

    .PARAMETER FilePath
    Path to the SRS file

    .OUTPUTS
    [PSCustomObject] containing:
      - FileMetadata: FileData element contents
      - Tracks: Array of TrackData elements
      - RawBytes: All bytes for further processing
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        throw "SRS file not found: $FilePath"
    }

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    Write-Verbose "Read SRS file: $($bytes.Length) bytes"

    # Parse EBML elements
    $offset = 0
    $ebmlHeader = $null
    $segment = $null

    # Expected: EBML element (header)
    $element = Get-EbmlElementFromBuffer -Buffer $bytes -Offset $offset
    Write-Verbose "Element at 0: $(ConvertTo-ByteString -Bytes $element.ElementID) ($($element.DataSize) bytes)"

    $offset += $element.TotalLength

    # Expected: Segment element
    $element = Get-EbmlElementFromBuffer -Buffer $bytes -Offset $offset
    Write-Verbose "Element at ${offset}: $(ConvertTo-ByteString -Bytes $element.ElementID) ($($element.DataSize) bytes)"

    $segment = $element
    $segmentDataOffset = $offset + $element.ElementID.Length

    # Now parse contents of Segment
    # The segment contains ReSample, ReSampleFile, ReSampleTrack elements

    $tracks = @()
    $fileData = $null

    $contentOffset = 0
    while ($contentOffset -lt $segment.DataSize) {
        try {
            $currentOffset = $segmentDataOffset + $contentOffset
            if ($currentOffset + 2 -gt $bytes.Length) {
                break
            }

            $elem = Get-EbmlElementFromBuffer -Buffer $bytes -Offset $currentOffset
            $elemIdHex = ConvertTo-ByteString -Bytes $elem.ElementID

            Write-Verbose "  Element at +${contentOffset}: ${elemIdHex} ($($elem.DataSize) bytes)"

            # Check for ReSampleFile (0xC1)
            if ($elem.ElementID.Length -eq 1 -and $elem.ElementID[0] -eq 0xC1) {
                Write-Verbose "    -> ReSampleFile found"
                $fileData = ConvertFrom-SrsFileData -Data $elem.ElementData
            }
            # Check for ReSampleTrack (0xC2)
            elseif ($elem.ElementID.Length -eq 1 -and $elem.ElementID[0] -eq 0xC2) {
                Write-Verbose "    -> ReSampleTrack found"
                $trackData = ConvertFrom-SrsTrackData -Data $elem.ElementData
                $tracks += $trackData
            }

            $contentOffset += $elem.TotalLength
        }
        catch {
            Write-Verbose "Error parsing element at offset $($segmentDataOffset + $contentOffset): $_"
            break
        }
    }

    return [PSCustomObject]@{
        FileMetadata = $fileData
        Tracks = $tracks
        RawBytes = $bytes
        SegmentDataOffset = $segmentDataOffset
    }
}

function ConvertFrom-SrsFileData {
    <#
    .SYNOPSIS
    Parses FileData element (0xC1) from SRS.

    .DESCRIPTION
    FileData structure (from pyrescene):
      - flags (2 bytes)
      - app_name_len (2 bytes)
      - app_name (variable)
      - file_name_len (2 bytes)
      - file_name (variable)
      - original_size (4 or 8 bytes depending on flags)
      - crc32 (4 bytes)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$Data
    )

    if ($Data.Length -lt 14) {
        throw "FileData too short: $($Data.Length) bytes"
    }

    # Read as binary
    $flags = [BitConverter]::ToUInt16($Data, 0)
    $appNameLen = [BitConverter]::ToUInt16($Data, 2)

    $offset = 4
    $appName = [System.Text.Encoding]::ASCII.GetString($Data, $offset, $appNameLen)
    $offset += $appNameLen

    $fileNameLen = [BitConverter]::ToUInt16($Data, $offset)
    $offset += 2

    $fileName = [System.Text.Encoding]::ASCII.GetString($Data, $offset, $fileNameLen)
    $offset += $fileNameLen

    # Check BIG_FILE flag (bit 0 = 0x0001)
    $isBigFile = ($flags -band 0x0001) -ne 0

    if ($isBigFile) {
        $originalSize = [BitConverter]::ToUInt64($Data, $offset)
        $offset += 8
    }
    else {
        $originalSize = [BitConverter]::ToUInt32($Data, $offset)
        $offset += 4
    }

    $crc32 = [BitConverter]::ToUInt32($Data, $offset)

    return [PSCustomObject]@{
        Flags = $flags
        AppName = $appName
        FileName = $fileName
        OriginalSize = $originalSize
        CRC32 = $crc32
    }
}

function ConvertFrom-SrsTrackData {
    <#
    .SYNOPSIS
    Parses TrackData element (0xC2) from SRS.

    .DESCRIPTION
    TrackData structure (from pyrescene):
      - flags (2 bytes)
      - track_number (2 or 4 bytes)
      - data_length (4 or 8 bytes)
      - match_offset (8 bytes) <- KEY VALUE
      - sig_length (2 bytes)
      - signature_bytes (variable)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$Data
    )

    if ($Data.Length -lt 18) {
        throw "TrackData too short: $($Data.Length) bytes"
    }

    $flags = [BitConverter]::ToUInt16($Data, 0)
    $offset = 2

    # Check if track number is 4 bytes (pyrescene TrackData.BIG_TACK_NUMBER = 0x8)
    $isLargeTrackNum = ($flags -band 0x0008) -ne 0

    if ($isLargeTrackNum) {
        $trackNumber = [BitConverter]::ToUInt32($Data, $offset)
        $offset += 4
    }
    else {
        $trackNumber = [BitConverter]::ToUInt16($Data, $offset)
        $offset += 2
    }

    # Check if BIG_FILE flag (pyrescene TrackData.BIG_FILE = 0x4)
    $isBigFile = ($flags -band 0x0004) -ne 0

    if ($isBigFile) {
        $dataLength = [BitConverter]::ToUInt64($Data, $offset)
        $offset += 8
    }
    else {
        $dataLength = [BitConverter]::ToUInt32($Data, $offset)
        $offset += 4
    }

    # match_offset is always 8 bytes (uint64)
    $matchOffset = [BitConverter]::ToUInt64($Data, $offset)
    $offset += 8

    # Signature bytes length
    $sigLength = [BitConverter]::ToUInt16($Data, $offset)
    $offset += 2

    # Signature bytes
    $signatureBytes = New-Object byte[] $sigLength
    if ($sigLength -gt 0) {
        [System.Array]::Copy($Data, $offset, $signatureBytes, 0, $sigLength)
    }

    return [PSCustomObject]@{
        Flags = $flags
        TrackNumber = $trackNumber
        DataLength = $dataLength
        MatchOffset = $matchOffset
        SignatureLength = $sigLength
        SignatureBytes = $signatureBytes
    }
}

#endregion

#region Public Functions

function Get-SrrBlock {
    <#
    .SYNOPSIS
        Parse an SRR file and return all blocks

    .PARAMETER SrrFile
        Path to the SRR file

    .EXAMPLE
        Get-SrrBlock -SrrFile "release.srr"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$SrrFile
    )

    $reader = [BlockReader]::new($SrrFile)
    try {
        return $reader.ReadAllBlocks()
    }
    finally {
        $reader.Close()
    }
}

function Show-SrrInfo {
    <#
    .SYNOPSIS
        Display information about an SRR file

    .PARAMETER SrrFile
        Path to the SRR file

    .EXAMPLE
        Show-SrrInfo -SrrFile "release.srr"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$SrrFile
    )

    Write-Host "Parsing SRR file: $SrrFile" -ForegroundColor Cyan
    Write-Host ""

    $blocks = Get-SrrBlock -SrrFile $SrrFile

    Write-Host "Total blocks: $($blocks.Count)" -ForegroundColor Green
    Write-Host ""

    # Show SRR header info
    $header = $blocks | Where-Object { $_.HeadType -eq 0x69 } | Select-Object -First 1
    if ($header -and $header.AppName) {
        Write-Host "Creating Application:" -ForegroundColor Yellow
        Write-Host "  $($header.AppName)"
        Write-Host ""
    }

    # Show stored files
    $storedFiles = $blocks | Where-Object { $_.HeadType -eq 0x6A }
    if ($storedFiles.Count -gt 0) {
        Write-Host "Stored files:" -ForegroundColor Yellow
        foreach ($file in $storedFiles) {
            Write-Host ("  {0,12:N0}  {1}" -f $file.FileSize, $file.FileName)
        }
        Write-Host ""
    }

    # Show RAR volumes
    $rarFiles = $blocks | Where-Object { $_.HeadType -eq 0x71 }
    if ($rarFiles.Count -gt 0) {
        Write-Host "RAR files:" -ForegroundColor Yellow
        foreach ($rar in $rarFiles) {
            Write-Host "  $($rar.FileName)"
        }
        Write-Host ""
    }

    # Block type summary
    Write-Host "Block type summary:" -ForegroundColor Yellow
    $blocks | Group-Object HeadType | Sort-Object Name | ForEach-Object {
        $typeName = if ($script:BlockTypeNames.ContainsKey([int]$_.Name)) {
            $script:BlockTypeNames[[int]$_.Name]
        } else {
            "Unknown"
        }
        Write-Host ("  0x{0:X2} {1,-30} {2,3} blocks" -f [int]$_.Name, $typeName, $_.Count)
    }
}

#endregion

#region Helper Functions

function Get-Crc32 {
    <#
    .SYNOPSIS
        Calculate CRC32 hash of a file or portion of a file
    the CRC PowerShell Gallery module.
        Supports offset and length for validating chunks of multi-volume archives.

    .PARAMETER FilePath
        Path to the file to hash

    .PARAMETER Offset
        Optional: Start reading from this byte offset

    .PARAMETER Length
        Optional: Only hash N bytes from the offset
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter()]
        [long]$Offset = 0,

        [Parameter()]
        [long]$Length = -1
    )

    # For offset/length, we need to extract the chunk to a temp file or use streaming
    if ($Offset -gt 0 -or $Length -gt 0) {
        # Read the specific chunk and calculate CRC
        $fs = [System.IO.File]::OpenRead($FilePath)
        try {
            if ($Offset -gt 0) {
                $fs.Seek($Offset, [System.IO.SeekOrigin]::Begin) | Out-Null
            }

            $tempFile = [System.IO.Path]::GetTempFileName()
            $tempFs = [System.IO.File]::Create($tempFile)
            try {
                $buffer = New-Object byte[] 65536
                $totalRead = [long]0
                $bytesRead = 0

                while (($bytesRead = $fs.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    if ($Length -gt 0) {
                        $remaining = $Length - $totalRead
                        if ($remaining -le 0) { break }
                        if ($bytesRead -gt $remaining) {
                            $bytesRead = [int]$remaining
                        }
                    }

                    $tempFs.Write($buffer, 0, $bytesRead)
                    $totalRead += $bytesRead
                }

                $tempFs.Close()
                $result = get-crc32 -Path $tempFile
                return [Convert]::ToUInt32($result.Hash, 16)
            }
            finally {
                if ($tempFs) { $tempFs.Dispose() }
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
        finally {
            $fs.Close()
        }
    }
    else {
        # Use CRC module directly for whole file
        $result = get-crc32 -Path $FilePath
        return [Convert]::ToUInt32($result.Hash, 16)
    }
    # Final XOR - mask to ensure unsigned 32-bit result
    return ($crc -bxor 0xFFFFFFFF) -band 0xFFFFFFFF
}

function Find-SourceFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [string]$SearchPath,

        [Parameter()]
        [uint64]$ExpectedSize
    )

    # Try direct path first
    $directPath = Join-Path $SearchPath $FileName
    if (Test-Path $directPath) {
        $fileInfo = Get-Item $directPath
        if ($ExpectedSize -eq 0 -or $fileInfo.Length -eq $ExpectedSize) {
            return $fileInfo.FullName
        }
    }

    # Search recursively
    $files = Get-ChildItem -Path $SearchPath -Recurse -File -Filter (Split-Path $FileName -Leaf) -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        if ($ExpectedSize -eq 0 -or $file.Length -eq $ExpectedSize) {
            return $file.FullName
        }
    }

    return $null
}

function Export-StoredFile {
    <#
    .SYNOPSIS
        Extract a stored file from SRR blocks to disk

    .PARAMETER SrrFile
        Path to the SRR file

    .PARAMETER FileName
        Name of the stored file to extract (supports wildcards, e.g., "*.sfv")

    .PARAMETER OutputPath
        Where to save the extracted file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SrrFile,

        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $reader = [BlockReader]::new($SrrFile)
    try {
        $blocks = $reader.ReadAllBlocks()

        # Find matching stored file block
        $pattern = $FileName -replace '\*', '.*'
        $stored = $blocks | Where-Object {
            $_.HeadType -eq 0x6A -and $_.FileName -match "^$pattern$"
        } | Select-Object -First 1

        if (-not $stored) {
            throw "Stored file not found in SRR matching pattern: $FileName"
        }

        Write-Host "    Extracting: $($stored.FileName) ($($stored.FileSize) bytes)" -ForegroundColor Gray

        # Read the stored file data from the SRR
        # The data is stored right after the RawData in the block
        $fs = [System.IO.File]::OpenRead($SrrFile)
        try {
            $br = [System.IO.BinaryReader]::new($fs)

            # Seek through blocks to find this one's data
            $currentPos = 0
            foreach ($block in $blocks) {
                $blockSize = $block.HeadSize + $block.AddSize

                if ($block -eq $stored) {
                    # Found it! Read the file data
                    # Position is at: header position + HeadSize
                    $dataStart = $currentPos + $block.HeadSize
                    $fs.Seek($dataStart, [System.IO.SeekOrigin]::Begin) | Out-Null

                    $fileData = $br.ReadBytes($stored.FileSize)
                    [System.IO.File]::WriteAllBytes($OutputPath, $fileData)
                    return
                }

                $currentPos += $blockSize
            }

            throw "Could not find file data in stream"
        }
        finally {
            $br.Dispose()
            $fs.Close()
        }
    }
    finally {
        $reader.Close()
    }
}

function Get-SrsInfo {
    <#
    .SYNOPSIS
        Identify basic SRS type from magic bytes and return info.

    .PARAMETER FilePath
        Path to the .srs file to inspect
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        throw "SRS file not found: $FilePath"
    }

    $type = "Unknown"
    $len = (Get-Item $FilePath).Length

    $fs = [System.IO.File]::OpenRead($FilePath)
    try {
        $br = [System.IO.BinaryReader]::new($fs)
        $magic = $br.ReadBytes(4)

        # ASCII helpers
        $asAscii = [System.Text.Encoding]::ASCII.GetString($magic)

        if ($magic.Length -eq 4) {
            switch -Regex ($asAscii) {
                '^RIFF$' { $type = 'RIFF (AVI/WMV/MP3 containers)'; break }
                '^fLaC$' { $type = 'FLAC'; break }
                '^STRM$' { $type = 'Stream (Generic)'; break }
                '^M2TS$' { $type = 'M2TS Stream'; break }
                default {
                    # EBML (MKV) magic bytes: 1A 45 DF A3
                    if ($magic[0] -eq 0x1A -and $magic[1] -eq 0x45 -and $magic[2] -eq 0xDF -and $magic[3] -eq 0xA3) {
                        $type = 'EBML (MKV)'
                    }
                }
            }
        }
    }
    finally {
        if ($br) { $br.Dispose() }
        $fs.Close()
    }

    [PSCustomObject]@{
        Path = (Resolve-Path $FilePath).Path
        Size = $len
        Type = $type
    }
}

function ConvertFrom-SfvFile {
    <#
    .SYNOPSIS
        Parse an SFV file and return a hash table of filename -> CRC

    .PARAMETER FilePath
        Path to the SFV file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $sfvData = @{}
    $content = Get-Content -Path $FilePath -ErrorAction Stop

    foreach ($line in $content) {
        $line = $line.Trim()

        # Skip comments and empty lines
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(';')) {
            continue
        }

        # Parse format: filename CRC
        # Example: archive.rar 12345678
        $match = [regex]::Match($line, '^(.+?)\s+([0-9A-Fa-f]{8})$')
        if ($match.Success) {
            $fileName = $match.Groups[1].Value
            $crc = $match.Groups[2].Value
            $sfvData[$fileName] = [Convert]::ToUInt32($crc, 16)
        }
    }

    return $sfvData
}

function ConvertFrom-SrsFileMetadata {
    <#
    .SYNOPSIS
        Parse EBML SRS file to extract track metadata and match offsets.

    .PARAMETER SrsFilePath
        Path to the extracted .srs file (EBML format).

    .DESCRIPTION
        Reads SRS file structure to extract:
        - FileData: original file size, CRC32, filename
        - TrackData: match_offset, data_length, signature_bytes for each track

        This metadata is used to know WHERE and HOW MUCH to extract from the main file.

    .RETURNS
        Hashtable with keys: FileData, Tracks (array), SrsSize
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SrsFilePath
    )

    if (-not (Test-Path $SrsFilePath)) {
        throw "SRS file not found: $SrsFilePath"
    }

    try {
        $fs = [System.IO.File]::OpenRead($SrsFilePath)
        $br = [BinaryReader]::new($fs)
        $srsSize = $fs.Length

        $metadata = @{
            FileData = $null
            Tracks = @()
            SrsSize = $srsSize
        }

        # Helper functions to parse EBML variable-length integers and IDs (based on pyrescene)
        function Get-UIntLength {
            param([byte]$LengthDescriptor)
            for ($i = 0; $i -lt 8; $i++) {
                $bit = 0x80 -shr $i
                if (($LengthDescriptor -band $bit) -ne 0) { return $i + 1 }
            }
            return 0
        }

        function Read-EbmlVarInt {
            param([BinaryReader]$Reader)
            $firstByte = $Reader.ReadByte()
            $bytes = Get-UIntLength -LengthDescriptor $firstByte
            [uint64]$mask = 0xFF -shr $bytes
            [uint64]$value = ($firstByte -band $mask)
            for ($i = 1; $i -lt $bytes; $i++) { $value = ($value -shl 8) + $Reader.ReadByte() }
            return @{ Value = $value; Bytes = $bytes }
        }

        function Read-EbmlElementId {
            param([BinaryReader]$Reader)
            $firstByte = $Reader.ReadByte()
            $len = Get-UIntLength -LengthDescriptor $firstByte
            $id = New-Object byte[] $len
            $id[0] = $firstByte
            for ($i = 1; $i -lt $len; $i++) { $id[$i] = $Reader.ReadByte() }
            return $id
        }

        # Helper function to read 64-bit little-endian integer (used for offsets/lengths)
        function Read-UInt64LE {
            param([BinaryReader]$Reader)
            $bytes = $Reader.ReadBytes(8)
            [uint64]$value = 0
            for ($i = 7; $i -ge 0; $i--) {
                $value = ($value -shl 8) -bor $bytes[$i]
            }
            return $value
        }

        # Helper function to read 16-bit little-endian integer
        function Read-UInt16LE {
            param([BinaryReader]$Reader)
            $low = $Reader.ReadByte()
            $high = $Reader.ReadByte()
            return (($high -shl 8) -bor $low)
        }

        # EBML IDs from pyrescene
        $EbmlId_Resample = [byte[]]@(0x1F,0x69,0x75,0x76)
        $EbmlId_ResampleFile = [byte[]]@(0x6A,0x75)
        $EbmlId_ResampleTrack = [byte[]]@(0x6B,0x75)

        function Test-BytesEqual {
            param([byte[]]$A,[byte[]]$B)
            if ($A.Length -ne $B.Length) { return $false }
            for ($i=0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }
            return $true
        }

        # Parse EBML: read EBML header, then Segment, then inner ReSample elements
        # EBML Header
        $ebmlId = Read-EbmlElementId -Reader $br
        $ebmlSizeInfo = Read-EbmlVarInt -Reader $br
        $fs.Seek([int64]$ebmlSizeInfo.Value, [System.IO.SeekOrigin]::Current) | Out-Null

        # Segment
        $segId = Read-EbmlElementId -Reader $br
        $segSizeInfo = Read-EbmlVarInt -Reader $br
        $segmentStart = $fs.Position
        # Handle unknown size (all ones): treat as until end of file
        $segUnknownMax = [uint64]([math]::Pow(2, 7 * $segSizeInfo.Bytes) - 1)
        if ($segSizeInfo.Value -eq $segUnknownMax) { $segmentEnd = $srsSize } else { $segmentEnd = $segmentStart + [int64]$segSizeInfo.Value }

        while ($fs.Position -lt $segmentEnd) {
            $remaining = $segmentEnd - $fs.Position
            if ($remaining -le 0) { break }
            try {
                $elemStart = $fs.Position
                $idBytes = Read-EbmlElementId -Reader $br
                $sizeInfo = Read-EbmlVarInt -Reader $br
                $dataSize = [int64]$sizeInfo.Value
                if ($dataSize -gt ($segmentEnd - $fs.Position)) { break }

            if (Test-BytesEqual -A $idBytes -B $EbmlId_Resample) {
                # ReSample container: iterate its children
                $containerStart = $fs.Position
                $containerEnd = $containerStart + $dataSize
                while ($fs.Position -lt $containerEnd) {
                    $cRemain = $containerEnd - $fs.Position
                    if ($cRemain -le 0) { break }
                    try {
                        $cid = Read-EbmlElementId -Reader $br
                        $csizeInfo = Read-EbmlVarInt -Reader $br
                        $cdataSize = [int64]$csizeInfo.Value

                        if (Test-BytesEqual -A $cid -B $EbmlId_ResampleFile) {
                            $data = $br.ReadBytes([int]$cdataSize)
                            $flags = [BitConverter]::ToUInt16($data, 0)
                            $appLen = [BitConverter]::ToUInt16($data, 2)
                            $off = 4
                            $appName = [System.Text.Encoding]::UTF8.GetString($data, $off, $appLen)
                            $off += $appLen
                            $nameLen = [BitConverter]::ToUInt16($data, $off)
                            $off += 2
                            $sampleName = [System.Text.Encoding]::UTF8.GetString($data, $off, $nameLen)
                            $off += $nameLen
                            $originalSize = [BitConverter]::ToUInt64($data, $off)
                            $off += 8
                            $crc32 = [BitConverter]::ToUInt32($data, $off)

                            $metadata.FileData = @{
                                Flags = $flags
                                AppName = $appName
                                SampleName = $sampleName
                                OriginalSize = $originalSize
                                CRC32 = $crc32
                            }
                        }
                        elseif (Test-BytesEqual -A $cid -B $EbmlId_ResampleTrack) {
                            $data = $br.ReadBytes([int]$cdataSize)
                            $off = 0
                            $flags = [BitConverter]::ToUInt16($data, $off)
                            $off += 2
                            $bigTrack = ($flags -band 0x8) -ne 0
                            if ($bigTrack) { $trackNumber = [BitConverter]::ToUInt32($data, $off); $off += 4 } else { $trackNumber = [BitConverter]::ToUInt16($data, $off); $off += 2 }
                            $bigFile = ($flags -band 0x4) -ne 0
                            if ($bigFile) { $dataLength = [BitConverter]::ToUInt64($data, $off); $off += 8 } else { $dataLength = [BitConverter]::ToUInt32($data, $off); $off += 4 }
                            $matchOffset = [BitConverter]::ToUInt64($data, $off); $off += 8
                            $sigLen = [BitConverter]::ToUInt16($data, $off); $off += 2
                            $sigBytes = New-Object byte[] $sigLen
                            if ($sigLen -gt 0 -and ($off + $sigLen) -le $data.Length) { [System.Array]::Copy($data, $off, $sigBytes, 0, $sigLen) }
                            $metadata.Tracks += @{
                                Flags = $flags
                                TrackNumber = $trackNumber
                                DataLength = [uint64]$dataLength
                                MatchOffset = [uint64]$matchOffset
                                SignatureBytesLength = $sigLen
                                SignatureBytes = $sigBytes
                            }
                        }
                        else {
                            $fs.Seek($cdataSize, [System.IO.SeekOrigin]::Current) | Out-Null
                        }
                    }
                    catch { break }
                }
            }
            elseif (Test-BytesEqual -A $idBytes -B $EbmlId_ResampleFile) {
                # ReSampleFile (FileData)
                $data = $br.ReadBytes([int]$dataSize)
                $flags = [BitConverter]::ToUInt16($data, 0)
                $appLen = [BitConverter]::ToUInt16($data, 2)
                $off = 4
                $appName = [System.Text.Encoding]::UTF8.GetString($data, $off, $appLen)
                $off += $appLen
                $nameLen = [BitConverter]::ToUInt16($data, $off)
                $off += 2
                $sampleName = [System.Text.Encoding]::UTF8.GetString($data, $off, $nameLen)
                $off += $nameLen
                $originalSize = [BitConverter]::ToUInt64($data, $off)
                $off += 8
                $crc32 = [BitConverter]::ToUInt32($data, $off)

                $metadata.FileData = @{
                    Flags = $flags
                    AppName = $appName
                    SampleName = $sampleName
                    OriginalSize = $originalSize
                    CRC32 = $crc32
                }
            }
            elseif (Test-BytesEqual -A $idBytes -B $EbmlId_ResampleTrack) {
                # ReSampleTrack (TrackData)
                $data = $br.ReadBytes([int]$dataSize)
                $off = 0
                $flags = [BitConverter]::ToUInt16($data, $off)
                $off += 2

                $bigTrack = ($flags -band 0x8) -ne 0  # BIG_TACK_NUMBER
                if ($bigTrack) { $trackNumber = [BitConverter]::ToUInt32($data, $off); $off += 4 }
                else { $trackNumber = [BitConverter]::ToUInt16($data, $off); $off += 2 }

                $bigFile = ($flags -band 0x4) -ne 0  # BIG_FILE
                if ($bigFile) { $dataLength = [BitConverter]::ToUInt64($data, $off); $off += 8 }
                else { $dataLength = [BitConverter]::ToUInt32($data, $off); $off += 4 }

                $matchOffset = [BitConverter]::ToUInt64($data, $off); $off += 8
                $sigLen = [BitConverter]::ToUInt16($data, $off); $off += 2
                $sigBytes = New-Object byte[] $sigLen
                if ($sigLen -gt 0 -and ($off + $sigLen) -le $data.Length) {
                    [System.Array]::Copy($data, $off, $sigBytes, 0, $sigLen)
                }

                $metadata.Tracks += @{
                    Flags = $flags
                    TrackNumber = $trackNumber
                    DataLength = [uint64]$dataLength
                    MatchOffset = [uint64]$matchOffset
                    SignatureBytesLength = $sigLen
                    SignatureBytes = $sigBytes
                }
            }
            else {
                # Skip other elements in Segment
                $fs.Seek($dataSize, [System.IO.SeekOrigin]::Current) | Out-Null
            }
            }
            catch {
                break
            }
        }

        # Fallback: scan entire file for ReSample container if none parsed
        if (($metadata.Tracks.Count -eq 0) -or (-not $metadata.FileData)) {
            $pos = 0
            while ($pos -lt $srsSize - 2) {
                try {
                    $fs.Seek($pos, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $peek = $br.ReadByte()
                    if ($peek -eq 0xC0) {
                        $sizeInfo = Read-EbmlVarInt -Reader $br
                        $containerStart = $fs.Position
                        $containerEnd = $containerStart + [int64]$sizeInfo.Value
                        while ($fs.Position -lt $containerEnd) {
                            if (($containerEnd - $fs.Position) -le 0) { break }
                            $cid = Read-EbmlElementId -Reader $br
                            $csize = Read-EbmlVarInt -Reader $br
                            $clen = [int64]$csize.Value
                            if ($cid.Length -eq 1 -and $cid[0] -eq 0xC1) {
                                $data = $br.ReadBytes([int]$clen)
                                $flags = [BitConverter]::ToUInt16($data, 0)
                                $appLen = [BitConverter]::ToUInt16($data, 2)
                                $off = 4
                                $appName = [System.Text.Encoding]::UTF8.GetString($data, $off, $appLen)
                                $off += $appLen
                                $nameLen = [BitConverter]::ToUInt16($data, $off)
                                $off += 2
                                $sampleName = [System.Text.Encoding]::UTF8.GetString($data, $off, $nameLen)
                                $off += $nameLen
                                $originalSize = [BitConverter]::ToUInt64($data, $off)
                                $off += 8
                                $crc32 = [BitConverter]::ToUInt32($data, $off)
                                $metadata.FileData = @{
                                    Flags = $flags
                                    AppName = $appName
                                    SampleName = $sampleName
                                    OriginalSize = $originalSize
                                    CRC32 = $crc32
                                }
                            }
                            elseif ($cid.Length -eq 1 -and $cid[0] -eq 0xC2) {
                                $data = $br.ReadBytes([int]$clen)
                                $off = 0
                                $flags = [BitConverter]::ToUInt16($data, $off)
                                $off += 2
                                $bigTrack = ($flags -band 0x8) -ne 0
                                if ($bigTrack) { $trackNumber = [BitConverter]::ToUInt32($data, $off); $off += 4 } else { $trackNumber = [BitConverter]::ToUInt16($data, $off); $off += 2 }
                                $bigFile = ($flags -band 0x4) -ne 0
                                if ($bigFile) { $dataLength = [BitConverter]::ToUInt64($data, $off); $off += 8 } else { $dataLength = [BitConverter]::ToUInt32($data, $off); $off += 4 }
                                $matchOffset = [BitConverter]::ToUInt64($data, $off); $off += 8
                                $sigLen = [BitConverter]::ToUInt16($data, $off); $off += 2
                                $sigBytes = New-Object byte[] $sigLen
                                if ($sigLen -gt 0 -and ($off + $sigLen) -le $data.Length) { [System.Array]::Copy($data, $off, $sigBytes, 0, $sigLen) }
                                $metadata.Tracks += @{
                                    Flags = $flags
                                    TrackNumber = $trackNumber
                                    DataLength = [uint64]$dataLength
                                    MatchOffset = [uint64]$matchOffset
                                    SignatureBytesLength = $sigLen
                                    SignatureBytes = $sigBytes
                                }
                            }
                            else {
                                $fs.Seek($clen, [System.IO.SeekOrigin]::Current) | Out-Null
                            }
                        }
                        if ($metadata.Tracks.Count -gt 0 -or $metadata.FileData) { break }
                    }
                }
                catch {}
                $pos += 1
            }
        }

        $br.Dispose()
        $fs.Close()

        Write-Verbose "Parsed SRS: FileData CRC32=0x$('{0:X8}' -f $metadata.FileData.CRC32), Tracks=$($metadata.Tracks.Count)"
        return $metadata
    }
    catch {
        throw "Failed to parse SRS file: $_"
    }
}

function Export-MkvTrackData {
    <#
    .SYNOPSIS
        Extract track data from main MKV by parsing EBML structure.

    .PARAMETER MainFilePath
        Path to the main MKV file.

    .PARAMETER Tracks
        Hashtable of track metadata from SRS (keyed by track number).
        Each track has: TrackNumber, MatchOffset, DataLength, SignatureBytes

    .PARAMETER OutputFiles
        Hashtable to receive output file paths (keyed by track number).

    .DESCRIPTION
        Parses the main MKV file using EBML structure, extracting frame data
        from each Block/SimpleBlock for the appropriate track. This handles
        the interleaved nature of MKV files where video and audio frames
        are mixed together.

        Based on pyrescene's mkv_extract_sample_streams function.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MainFilePath,

        [Parameter(Mandatory)]
        [hashtable]$Tracks,

        [Parameter(Mandatory)]
        [hashtable]$OutputFiles
    )

    if (-not (Test-Path $MainFilePath)) {
        throw "Main file not found: $MainFilePath"
    }

    # Helper: Get EBML variable-length integer byte count
    function Get-EbmlVarLength {
        param([byte]$FirstByte)
        for ($i = 0; $i -lt 8; $i++) {
            if (($FirstByte -band (0x80 -shr $i)) -ne 0) { return $i + 1 }
        }
        return 0
    }

    # Helper: Read EBML variable-length integer
    function Read-EbmlVarInt {
        param([System.IO.BinaryReader]$Reader)
        $firstByte = $Reader.ReadByte()
        $bytes = Get-EbmlVarLength $firstByte
        [uint64]$mask = 0xFF -shr $bytes
        [uint64]$value = ($firstByte -band $mask)
        $rawBytes = New-Object byte[] $bytes
        $rawBytes[0] = $firstByte
        for ($i = 1; $i -lt $bytes; $i++) {
            $rawBytes[$i] = $Reader.ReadByte()
            $value = ($value -shl 8) + $rawBytes[$i]
        }
        return @{ Value = $value; Bytes = $bytes; RawBytes = $rawBytes }
    }

    # Helper: Read EBML element ID
    function Read-EbmlId {
        param([System.IO.BinaryReader]$Reader)
        $firstByte = $Reader.ReadByte()
        $len = Get-EbmlVarLength $firstByte
        $id = New-Object byte[] $len
        $id[0] = $firstByte
        for ($i = 1; $i -lt $len; $i++) { $id[$i] = $Reader.ReadByte() }
        return $id
    }

    # Helper: Compare byte arrays
    function Compare-Bytes {
        param([byte[]]$A, [byte[]]$B)
        if ($null -eq $A -or $null -eq $B) { return $false }
        if ($A.Length -ne $B.Length) { return $false }
        for ($i = 0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }
        return $true
    }

    # EBML element IDs
    $ID_Segment = [byte[]]@(0x18, 0x53, 0x80, 0x67)
    $ID_Cluster = [byte[]]@(0x1F, 0x43, 0xB6, 0x75)
    $ID_BlockGroup = [byte[]]@(0xA0)
    $ID_Block = [byte[]]@(0xA1)
    $ID_SimpleBlock = [byte[]]@(0xA3)

    try {
        $fs = [System.IO.File]::OpenRead($MainFilePath)
        $reader = [System.IO.BinaryReader]::new($fs)
        $fileSize = $fs.Length

        # Find earliest match_offset to skip clusters before it
        [uint64]$startOffset = [uint64]::MaxValue
        foreach ($trackNum in $Tracks.Keys) {
            $track = $Tracks[$trackNum]
            if ($track.MatchOffset -gt 0 -and $track.MatchOffset -lt $startOffset) {
                $startOffset = $track.MatchOffset
            }
        }

        # Initialize track output streams
        $trackStreams = @{}
        $trackBytesWritten = @{}
        foreach ($trackNum in $Tracks.Keys) {
            $tempFile = [System.IO.Path]::GetTempFileName() + ".track$trackNum"
            $trackStreams[$trackNum] = [System.IO.File]::Create($tempFile)
            $trackBytesWritten[$trackNum] = [uint64]0
            $OutputFiles[$trackNum] = $tempFile
        }

        $clusterCount = 0
        $blockCount = 0
        $done = $false

        # Skip EBML header
        $ebmlId = Read-EbmlId -Reader $reader
        $ebmlSize = Read-EbmlVarInt -Reader $reader
        $fs.Seek([int64]$ebmlSize.Value, [System.IO.SeekOrigin]::Current) | Out-Null

        # Read Segment header
        $segId = Read-EbmlId -Reader $reader
        $segSize = Read-EbmlVarInt -Reader $reader
        $segmentStart = $fs.Position

        # Parse through segment looking for blocks
        while ($fs.Position -lt $fileSize -and -not $done) {
            $elemStart = $fs.Position

            try {
                $elemId = Read-EbmlId -Reader $reader
                $sizeInfo = Read-EbmlVarInt -Reader $reader
                $elemSize = $sizeInfo.Value
            } catch {
                break
            }

            $headerLen = $elemId.Length + $sizeInfo.Bytes
            $dataStart = $fs.Position

            # Handle Segment - descend into it
            if (Compare-Bytes -A $elemId -B $ID_Segment) {
                continue  # Already inside segment, just continue
            }

            # Handle Cluster
            if (Compare-Bytes -A $elemId -B $ID_Cluster) {
                $clusterCount++
                if ($clusterCount % 50 -eq 0) {
                    Write-Verbose "Processing cluster $clusterCount..."
                }

                # Skip clusters entirely before startOffset
                $clusterEnd = $elemStart + $headerLen + $elemSize
                if ($clusterEnd -lt $startOffset) {
                    $fs.Seek([int64]$elemSize, [System.IO.SeekOrigin]::Current) | Out-Null
                    continue
                }

                # Descend into cluster (don't skip)
                continue
            }

            # Handle BlockGroup - descend into it
            if (Compare-Bytes -A $elemId -B $ID_BlockGroup) {
                continue
            }

            # Handle Block/SimpleBlock
            if ((Compare-Bytes -A $elemId -B $ID_Block) -or (Compare-Bytes -A $elemId -B $ID_SimpleBlock)) {
                $blockCount++

                # Read block header to get track number
                $blockStart = $fs.Position
                $trackInfo = Read-EbmlVarInt -Reader $reader
                $trackNumber = [uint16]$trackInfo.Value  # Must be uint16 to match hashtable keys

                # Read timecode (2 bytes) + flags (1 byte)
                $tcFlags = $reader.ReadBytes(3)
                $flags = $tcFlags[2]
                $laceType = ($flags -band 0x06) -shr 1

                # Calculate block header size and read lacing info
                $blockHeaderSize = $trackInfo.Bytes + 3
                $frameLengths = @()

                if ($laceType -ne 0) {
                    $frameCountByte = $reader.ReadByte()
                    $blockHeaderSize++
                    $frameCount = $frameCountByte + 1
                    $frameLengths = New-Object int[] $frameCount

                    $lacingBytesRead = 0
                    if ($laceType -eq 1) {
                        # Xiph lacing
                        for ($f = 0; $f -lt ($frameCount - 1); $f++) {
                            $frameSize = 0
                            do {
                                $laceByte = $reader.ReadByte()
                                $lacingBytesRead++
                                $frameSize += $laceByte
                            } while ($laceByte -eq 255)
                            $frameLengths[$f] = $frameSize
                        }
                    } elseif ($laceType -eq 3) {
                        # EBML lacing
                        $firstSizeInfo = Read-EbmlVarInt -Reader $reader
                        $lacingBytesRead += $firstSizeInfo.Bytes
                        $frameLengths[0] = [int]$firstSizeInfo.Value
                        for ($f = 1; $f -lt ($frameCount - 1); $f++) {
                            $deltaInfo = Read-EbmlVarInt -Reader $reader
                            $lacingBytesRead += $deltaInfo.Bytes
                            # Convert unsigned to signed delta
                            $delta = [int64]$deltaInfo.Value - ((1 -shl ($deltaInfo.Bytes * 7)) - 1)
                            $frameLengths[$f] = $frameLengths[$f - 1] + [int]$delta
                        }
                    } elseif ($laceType -eq 2) {
                        # Fixed-size lacing - calculate after we know total size
                    }
                    $blockHeaderSize += $lacingBytesRead
                } else {
                    $frameLengths = @(0)  # Will be set to full data size
                }

                # Frame data size
                $frameDataSize = [int]$elemSize - $blockHeaderSize

                # For fixed-size lacing or no lacing, calculate frame sizes
                if ($laceType -eq 2 -and $frameLengths.Count -gt 0) {
                    # Fixed-size: all frames equal
                    $frameSize = [int]($frameDataSize / $frameLengths.Count)
                    for ($f = 0; $f -lt $frameLengths.Count; $f++) {
                        $frameLengths[$f] = $frameSize
                    }
                } elseif ($laceType -eq 0) {
                    $frameLengths[0] = $frameDataSize
                } elseif ($laceType -ne 0) {
                    # For Xiph/EBML lacing, last frame size is remainder
                    $usedSize = 0
                    for ($f = 0; $f -lt ($frameLengths.Count - 1); $f++) {
                        $usedSize += $frameLengths[$f]
                    }
                    $frameLengths[$frameLengths.Count - 1] = $frameDataSize - $usedSize
                }

                # Check if this track is one we need
                if ($Tracks.ContainsKey($trackNumber)) {
                    $track = $Tracks[$trackNumber]
                    $trackStream = $trackStreams[$trackNumber]

                    # Position where frame data starts
                    $frameDataStart = $blockStart + $blockHeaderSize

                    # Check if this block is past match_offset for this track
                    if ($frameDataStart -ge $track.MatchOffset) {
                        # Only write if we still need more data
                        if ($trackBytesWritten[$trackNumber] -lt $track.DataLength) {
                            # Read and write frame data
                            $fs.Seek($frameDataStart, [System.IO.SeekOrigin]::Begin) | Out-Null
                            $toRead = [Math]::Min($frameDataSize, $track.DataLength - $trackBytesWritten[$trackNumber])
                            $frameData = $reader.ReadBytes([int]$toRead)
                            $trackStream.Write($frameData, 0, $frameData.Length)
                            $trackBytesWritten[$trackNumber] += $frameData.Length
                        }
                    }

                    # Check if all tracks are done
                    $done = $true
                    foreach ($tNum in $Tracks.Keys) {
                        if ($trackBytesWritten[$tNum] -lt $Tracks[$tNum].DataLength) {
                            $done = $false
                            break
                        }
                    }
                }

                # Skip to end of block
                $blockEnd = $elemStart + $headerLen + $elemSize
                $fs.Seek($blockEnd, [System.IO.SeekOrigin]::Begin) | Out-Null
                continue
            }

            # Skip other elements
            $fs.Seek([int64]$elemSize, [System.IO.SeekOrigin]::Current) | Out-Null
        }

        # Close all track streams
        foreach ($stream in $trackStreams.Values) {
            $stream.Flush()
            $stream.Dispose()
        }

        $reader.Dispose()
        $fs.Close()

        Write-Verbose "Extracted tracks from $clusterCount clusters, $blockCount blocks"
        foreach ($trackNum in $Tracks.Keys) {
            $extracted = $trackBytesWritten[$trackNum]
            $expected = $Tracks[$trackNum].DataLength
            Write-Verbose "  Track $trackNum : $extracted / $expected bytes"
        }

        return $true
    }
    catch {
        # Clean up on error
        foreach ($stream in $trackStreams.Values) {
            if ($null -ne $stream) { $stream.Dispose() }
        }
        throw "Failed to extract MKV track data: $_"
    }
}

function Export-SampleTrackData {
    <#
    .SYNOPSIS
        Extract sample track data from main file using match_offset and data_length.
        NOTE: This is a legacy function - use Export-MkvTrackData for MKV files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MainFilePath,

        [Parameter(Mandatory)]
        [uint64]$MatchOffset,

        [Parameter(Mandatory)]
        [uint64]$DataLength,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [byte[]]$SignatureBytes
    )

    # For now, delegate to simple extraction - caller should use Export-MkvTrackData instead
    if (-not (Test-Path $MainFilePath)) {
        throw "Main file not found: $MainFilePath"
    }

    try {
        $fs = [System.IO.File]::OpenRead($MainFilePath)
        $br = [BinaryReader]::new($fs)

        $fs.Seek($MatchOffset, [System.IO.SeekOrigin]::Begin) | Out-Null

        $outputFs = [System.IO.File]::Create($OutputPath)
        $bytesRemaining = $DataLength
        $bufferSize = [Math]::Min($bytesRemaining, 10MB)

        while ($bytesRemaining -gt 0) {
            $chunkSize = [Math]::Min($bufferSize, $bytesRemaining)
            $chunk = $br.ReadBytes([int]$chunkSize)
            if ($chunk.Count -eq 0) { break }
            $outputFs.Write($chunk, 0, $chunk.Length)
            $bytesRemaining -= $chunk.Count
        }

        $outputFs.Close()
        $br.Dispose()
        $fs.Close()

        return $true
    }
    catch {
        throw "Failed to extract track data: $_"
    }
}

function Build-SampleMkvFromSrs {
    <#
    .SYNOPSIS
        Reconstruct sample MKV by hierarchically parsing SRS and injecting track data.

    .DESCRIPTION
        Hierarchical EBML parsing approach (matches pyrescene):
        1. Read SRS file element-by-element using proper EBML VLQ decoding
        2. For container elements (Segment, Cluster, BlockGroup): write header, descend into children
        3. Skip ReSample container entirely (metadata only, not in final output)
        4. For Block/SimpleBlock elements: write header + block header + injected track data
        5. For all other elements: copy header + content directly

        Key insight: Container elements declare their ORIGINAL size (from source file),
        not the actual size in SRS. We must descend into children rather than skip by size.

    .NOTES
        Expected performance: 1-5 seconds for 58MB sample
        Result should match pyrescene: 61,542,372 bytes, CRC32=75BCB5BB
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SrsFilePath,

        [Parameter(Mandatory)]
        [hashtable]$TrackDataFiles,

        [Parameter(Mandatory)]
        [string]$OutputMkvPath
    )

    if (-not (Test-Path $SrsFilePath)) {
        throw "SRS file not found: $SrsFilePath"
    }

    try {
        # Helper: Get EBML variable-length integer byte count
        function Get-EbmlVarLength {
            param([byte]$FirstByte)
            for ($i = 0; $i -lt 8; $i++) {
                if (($FirstByte -band (0x80 -shr $i)) -ne 0) { return $i + 1 }
            }
            return 0
        }

        # Helper: Read EBML variable-length integer, returns value and raw bytes
        function Read-EbmlVarInt {
            param([System.IO.BinaryReader]$Reader)
            $firstByte = $Reader.ReadByte()
            $bytes = Get-EbmlVarLength $firstByte
            [uint64]$mask = 0xFF -shr $bytes
            [uint64]$value = ($firstByte -band $mask)

            $rawBytes = New-Object byte[] $bytes
            $rawBytes[0] = $firstByte

            for ($i = 1; $i -lt $bytes; $i++) {
                $rawBytes[$i] = $Reader.ReadByte()
                $value = ($value -shl 8) + $rawBytes[$i]
            }
            return @{ Value = $value; Bytes = $bytes; RawBytes = $rawBytes }
        }

        # Helper: Read EBML element ID (1-4 bytes)
        function Read-EbmlId {
            param([System.IO.BinaryReader]$Reader)
            $firstByte = $Reader.ReadByte()
            $len = Get-EbmlVarLength $firstByte
            $id = New-Object byte[] $len
            $id[0] = $firstByte
            for ($i = 1; $i -lt $len; $i++) { $id[$i] = $Reader.ReadByte() }
            return $id
        }

        # Helper: Compare byte arrays (with null safety)
        function Compare-Bytes {
            param([byte[]]$A, [byte[]]$B)
            if ($null -eq $A -or $null -eq $B) { return $false }
            if ($A.Length -ne $B.Length) { return $false }
            for ($i = 0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }
            return $true
        }

        # Helper: Check if element is a container that should descend into children
        function Test-ContainerElement {
            param([byte[]]$ElemId)
            if ($null -eq $ElemId) { return $false }
            # Container elements from pyrescene: Segment, Cluster, BlockGroup, AttachmentList, Attachment
            $containers = @(
                [byte[]]@(0x18, 0x53, 0x80, 0x67),  # Segment
                [byte[]]@(0x1F, 0x43, 0xB6, 0x75),  # Cluster
                [byte[]]@(0xA0),                     # BlockGroup
                [byte[]]@(0x19, 0x41, 0xA4, 0x69),  # AttachmentList
                [byte[]]@(0x61, 0xA7)               # Attachment
            )
            foreach ($c in $containers) {
                if (Compare-Bytes -A $ElemId -B $c) { return $true }
            }
            return $false
        }

        # EBML element IDs
        $ID_Resample = [byte[]]@(0x1F, 0x69, 0x75, 0x76)
        $ID_Block = [byte[]]@(0xA1)
        $ID_SimpleBlock = [byte[]]@(0xA3)

        # Load track data files into ordered dictionary by track number
        $trackDataStreams = [ordered]@{}
        foreach ($key in ($TrackDataFiles.Keys | Sort-Object)) {
            $trackFile = $TrackDataFiles[$key]
            if (Test-Path $trackFile) {
                $trackDataStreams[$key] = [System.IO.File]::OpenRead($trackFile)
                Write-Verbose "Opened track data file for track $key : $trackFile"
            }
        }

        # Open streams
        $srsFs = [System.IO.File]::OpenRead($SrsFilePath)
        $srsReader = [System.IO.BinaryReader]::new($srsFs)
        $srsSize = $srsFs.Length

        $outFs = [System.IO.File]::Create($OutputMkvPath)
        $outWriter = [System.IO.BinaryWriter]::new($outFs)

        try {
            $elemCount = 0
            $blockCount = 0
            $clusterCount = 0

            # Hierarchical EBML parsing - read until EOF
            while ($srsFs.Position -lt $srsSize) {
                $startPos = $srsFs.Position

                # Need at least 2 bytes for ID + size
                if ($startPos + 2 > $srsSize) { break }

                try {
                    # Read element ID
                    $elemId = Read-EbmlId -Reader $srsReader
                    if ($null -eq $elemId -or $elemId.Length -eq 0) { break }

                    # Read element size
                    $sizeInfo = Read-EbmlVarInt -Reader $srsReader
                    if ($null -eq $sizeInfo -or $null -eq $sizeInfo.RawBytes) {
                        Write-Warning "Failed to read size at offset $startPos"
                        break
                    }
                    $elemSize = $sizeInfo.Value

                    # Build raw header (ID + size bytes)
                    $rawHeader = New-Object byte[] ($elemId.Length + $sizeInfo.RawBytes.Length)
                    [System.Array]::Copy($elemId, 0, $rawHeader, 0, $elemId.Length)
                    [System.Array]::Copy($sizeInfo.RawBytes, 0, $rawHeader, $elemId.Length, $sizeInfo.RawBytes.Length)
                } catch {
                    Write-Warning "Error parsing element at offset $startPos : $_"
                    break
                }

                # Handle ReSample container - skip entirely (don't write to output)
                if (Compare-Bytes -A $elemId -B $ID_Resample) {
                    # Skip ReSample and all its children
                    $srsFs.Seek($elemSize, [System.IO.SeekOrigin]::Current) | Out-Null
                    Write-Verbose "Skipped ReSample container at $startPos"
                    continue
                }

                # Handle container elements - write header, then descend into children
                if (Test-ContainerElement -ElemId $elemId) {
                    # Write header to output
                    $outWriter.Write($rawHeader, 0, $rawHeader.Length)

                    # Track clusters for progress
                    if (Compare-Bytes -A $elemId -B ([byte[]]@(0x1F, 0x43, 0xB6, 0x75))) {
                        $clusterCount++
                        if ($clusterCount % 10 -eq 0) {
                            Write-Verbose "Processing cluster $clusterCount..."
                        }
                    }

                    # Don't skip - continue to read children (move_to_child behavior)
                    $elemCount++
                    continue
                }

                # Handle Block/SimpleBlock elements
                if ((Compare-Bytes -A $elemId -B $ID_Block) -or (Compare-Bytes -A $elemId -B $ID_SimpleBlock)) {
                    $blockCount++

                    try {
                        # Read block header: track number (VLQ) + timecode (2 bytes) + flags (1 byte) + optional lacing
                        $trackInfo = Read-EbmlVarInt -Reader $srsReader
                        if ($null -eq $trackInfo -or $null -eq $trackInfo.RawBytes) {
                            Write-Warning "Block $blockCount at $startPos : Failed to read track number"
                            break
                        }
                        $trackNumber = $trackInfo.Value

                        # Read timecode (2 bytes) + flags (1 byte) = 3 more bytes
                        $tcFlags = $srsReader.ReadBytes(3)
                        if ($null -eq $tcFlags -or $tcFlags.Length -lt 3) {
                            Write-Warning "Block $blockCount at $startPos : Failed to read tcFlags (got $($tcFlags.Length) bytes)"
                            break
                        }

                        # Check for lacing in flags byte (bits 1-2)
                        $flags = $tcFlags[2]
                        $laceType = ($flags -band 0x06) -shr 1  # 0=none, 1=Xiph, 2=fixed, 3=EBML

                        # Build block header starting with track + timecode + flags
                        $blockHeaderList = [System.Collections.Generic.List[byte]]::new()
                        foreach ($b in $trackInfo.RawBytes) { $blockHeaderList.Add($b) }
                        foreach ($b in $tcFlags) { $blockHeaderList.Add($b) }

                        # If lacing is enabled, read lacing info from SRS
                        if ($laceType -ne 0) {
                            # Read frame count (number of frames in block - 1)
                            $frameCountByte = $srsReader.ReadByte()
                            $blockHeaderList.Add($frameCountByte)
                            $frameCount = $frameCountByte + 1

                            if ($laceType -eq 1) {
                                # Xiph lacing: frame sizes as sequences of 255 + remainder
                                for ($f = 0; $f -lt ($frameCount - 1); $f++) {
                                    do {
                                        $laceByte = $srsReader.ReadByte()
                                        $blockHeaderList.Add($laceByte)
                                    } while ($laceByte -eq 255)
                                }
                            } elseif ($laceType -eq 3) {
                                # EBML lacing: first size is VLQ, rest are signed VLQ deltas
                                $firstSizeInfo = Read-EbmlVarInt -Reader $srsReader
                                foreach ($b in $firstSizeInfo.RawBytes) { $blockHeaderList.Add($b) }
                                for ($f = 1; $f -lt ($frameCount - 1); $f++) {
                                    $deltaInfo = Read-EbmlVarInt -Reader $srsReader
                                    foreach ($b in $deltaInfo.RawBytes) { $blockHeaderList.Add($b) }
                                }
                            }
                            # Fixed-size lacing (type 2) has no additional size data
                        }

                        $blockHeader = $blockHeaderList.ToArray()

                        # Calculate frame data size (element size minus block header)
                        $frameDataSize = $elemSize - $blockHeader.Length

                        # Safety check for negative frame size
                        if ($frameDataSize -lt 0) {
                            Write-Warning "Block $blockCount at $startPos : Invalid frameDataSize=$frameDataSize (elemSize=$elemSize, headerLen=$($blockHeader.Length))"
                            $frameDataSize = 0
                        }

                        # Write element header + block header to output
                        $outWriter.Write($rawHeader, 0, $rawHeader.Length)
                        $outWriter.Write($blockHeader, 0, $blockHeader.Length)

                        # Get track data stream for this track number
                        $trackStream = $null
                        foreach ($key in $trackDataStreams.Keys) {
                            if ($key -eq $trackNumber) {
                                $trackStream = $trackDataStreams[$key]
                                break
                            }
                        }

                        if ($null -ne $trackStream -and $trackStream.Position -lt $trackStream.Length -and $frameDataSize -gt 0) {
                            # Read frame data from track data file and write to output
                            $frameData = New-Object byte[] $frameDataSize
                            $bytesRead = $trackStream.Read($frameData, 0, [int]$frameDataSize)
                            $outWriter.Write($frameData, 0, $bytesRead)
                        } elseif ($frameDataSize -gt 0) {
                            # No track data available - write zeros as placeholder
                            $zeros = New-Object byte[] $frameDataSize
                            $outWriter.Write($zeros, 0, $zeros.Length)
                            Write-Warning "Block $blockCount (track $trackNumber): No track data, wrote $frameDataSize zeros"
                        }
                    } catch {
                        Write-Warning "Block $blockCount at $startPos error: $_"
                        break
                    }

                    $elemCount++
                    continue
                }

                # All other elements - copy header + content directly
                # BUT: In SRS, element sizes reflect ORIGINAL sizes, not actual SRS content
                # We need to read only what's actually present in the SRS
                $outWriter.Write($rawHeader, 0, $rawHeader.Length)

                # For non-container elements, read the actual content that exists
                # Check how much data is actually available before next element
                $remaining = $srsSize - $srsFs.Position

                # Peek ahead to find next element boundary
                # Content should be min(declared size, remaining before EOF)
                $bytesToRead = [Math]::Min([uint64]$elemSize, [uint64]$remaining)

                if ($bytesToRead -gt 0 -and $bytesToRead -le $remaining) {
                    # Read and copy content in chunks
                    $chunkSize = 1MB
                    $bytesLeft = $bytesToRead
                    while ($bytesLeft -gt 0) {
                        $toRead = [Math]::Min($chunkSize, $bytesLeft)
                        $chunk = $srsReader.ReadBytes([int]$toRead)
                        if ($chunk.Length -eq 0) { break }
                        $outWriter.Write($chunk, 0, $chunk.Length)
                        $bytesLeft -= $chunk.Length
                    }
                }

                $elemCount++
            }

            $outWriter.Flush()
            Write-Verbose "Rebuilt complete: $elemCount elements, $blockCount blocks, $clusterCount clusters"

            $outSize = $outFs.Length
            Write-Verbose "Output file: $OutputMkvPath ($outSize bytes)"
            return $true
        }
        finally {
            # Clean up track data streams
            foreach ($stream in $trackDataStreams.Values) {
                if ($null -ne $stream) { $stream.Dispose() }
            }
            if ($null -ne $outWriter) { $outWriter.Dispose() }
            if ($null -ne $srsReader) { $srsReader.Dispose() }
            if ($null -ne $outFs) { $outFs.Dispose() }
            if ($null -ne $srsFs) { $srsFs.Dispose() }
        }
    }
    catch {
        throw "Failed to rebuild sample: $_"
    }
}

function Restore-SrsVideo {
    <#
    .SYNOPSIS
        Reconstruct a sample video from an EBML SRS file and source MKV.

    .PARAMETER SrsFilePath
        Path to the extracted .srs file (EBML format).

    .PARAMETER SourceMkvPath
        Path to the source MKV file (main movie).

    .PARAMETER OutputMkvPath
        Path for the reconstructed sample MKV.

    .NOTES
        Uses match_offset from SRS metadata to extract ONLY the sample portion
        from the main file, not the entire file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SrsFilePath,

        [Parameter(Mandatory)]
        [string]$SourceMkvPath,

        [Parameter(Mandatory)]
        [string]$OutputMkvPath
    )

    if (-not (Test-Path $SrsFilePath)) {
        throw "SRS file not found: $SrsFilePath"
    }

    if (-not (Test-Path $SourceMkvPath)) {
        throw "Source MKV not found: $SourceMkvPath"
    }

    # Verify SRS is EBML type
    $srsInfo = Get-SrsInfo -FilePath $SrsFilePath
    if ($srsInfo.Type -notmatch 'EBML') {
        Write-Warning "SRS type '$($srsInfo.Type)' is not EBML; skipping video reconstruction"
        return $false
    }

    try {
        # Parse SRS metadata to get track offsets
        Write-Verbose "Parsing SRS file metadata..."
        $srsMetadata = ConvertFrom-SrsFileMetadata -SrsFilePath $SrsFilePath

        # Build tracks hashtable keyed by track number for Export-MkvTrackData
        $tracksForExtraction = @{}
        foreach ($track in $srsMetadata.Tracks) {
            $tracksForExtraction[$track.TrackNumber] = $track
        }

        Write-Verbose "Extracting track data from main MKV (parsing $($tracksForExtraction.Count) tracks)..."
        $trackDataFiles = @{}

        if ($tracksForExtraction.Count -gt 0) {
            # Use MKV-aware extraction that properly handles interleaved track data
            $extracted = Export-MkvTrackData `
                -MainFilePath $SourceMkvPath `
                -Tracks $tracksForExtraction `
                -OutputFiles $trackDataFiles

            if (-not $extracted) {
                throw "Failed to extract track data from main MKV"
            }

            # Log extracted track sizes
            foreach ($trackNum in $trackDataFiles.Keys) {
                $trackFile = $trackDataFiles[$trackNum]
                if (Test-Path $trackFile) {
                    $size = (Get-Item $trackFile).Length
                    Write-Verbose "  Track $trackNum : extracted $size bytes"
                }
            }
        }

        # Rebuild sample from SRS + extracted track data
        Write-Verbose "Rebuilding sample MKV..."
        $rebuilt = Build-SampleMkvFromSrs `
            -SrsFilePath $SrsFilePath `
            -TrackDataFiles $trackDataFiles `
            -OutputMkvPath $OutputMkvPath

        if ($rebuilt) {
            Write-Host "  [OK] Reconstructed video sample: $(Split-Path $OutputMkvPath -Leaf)" -ForegroundColor Green

            # Cleanup temp track files
            foreach ($tempFile in $trackDataFiles.Values) {
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -ErrorAction SilentlyContinue
                }
            }

            return $true
        }

        return $false
    }
    catch {
        Write-Warning "Failed to reconstruct video sample: $_"
        return $false
    }
}

function Test-ReconstructedRar {
    <#
    .SYNOPSIS
        Validate reconstructed RAR files against SFV CRCs

    .PARAMETER SrrFile
        Path to the SRR file (to extract SFV)

    .PARAMETER OutputPath
        Directory containing the reconstructed RAR files
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SrrFile,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    Write-Host "Validating reconstructed RAR files..." -ForegroundColor Cyan

    # Extract SFV file from SRR
    $tempSfv = [System.IO.Path]::GetTempFileName() + ".sfv"
    try {
        Write-Host "  Extracting SFV from SRR..." -ForegroundColor Gray
        Export-StoredFile -SrrFile $SrrFile -FileName "*.sfv" -OutputPath $tempSfv -ErrorAction SilentlyContinue

        if (-not (Test-Path $tempSfv)) {
            Write-Warning "SFV file not found in SRR, skipping CRC validation"
            return
        }

        # Parse SFV
        $sfvData = ConvertFrom-SfvFile -FilePath $tempSfv

        Write-Host "  Found $($sfvData.Count) entries in SFV" -ForegroundColor Green

        # Validate each RAR file
        $allValid = $true
        $validCount = 0
        $failCount = 0

        foreach ($rarFile in $sfvData.Keys | Sort-Object) {
            $rarPath = Join-Path $OutputPath $rarFile

            if (-not (Test-Path $rarPath)) {
                Write-Host "    [X] $rarFile - NOT FOUND" -ForegroundColor Red
                $allValid = $false
                $failCount++
                continue
            }

            $expectedCrc = $sfvData[$rarFile]
            $actualCrc = (get-crc32 -Path $rarPath).Hash
            $actualCrcInt = [Convert]::ToUInt32($actualCrc, 16)

            if ($actualCrcInt -eq $expectedCrc) {
                Write-Host "    [OK] $rarFile" -ForegroundColor Green
                $validCount++
            }
            else {
                Write-Host ("    [X] $rarFile - CRC mismatch: Expected 0x{0:X8}, got 0x{1:X8}" -f $expectedCrc, $actualCrcInt) -ForegroundColor Red
                $allValid = $false
                $failCount++
            }
        }

        Write-Host ""
        if ($allValid) {
            Write-Host "All RAR files validated successfully!" -ForegroundColor Green
        }
        else {
            Write-Host "$validCount valid, $failCount failed" -ForegroundColor Yellow
        }
    }
    finally {
        Remove-Item $tempSfv -Force -ErrorAction SilentlyContinue
    }
}

#endregion

#region Reconstruction Functions

function Invoke-SrrReconstruct {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SrrFile,

        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [switch]$SkipValidation,

        [Parameter()]
        [switch]$ExtractStoredFiles
    )

    # Resolve all paths to absolute paths
    $SrrFile = (Resolve-Path -Path $SrrFile -ErrorAction Stop).Path
    $SourcePath = (Resolve-Path -Path $SourcePath -ErrorAction Stop).Path
    $OutputPath = (Resolve-Path -Path $OutputPath -ErrorAction Stop).Path

    Write-Host "Starting SRR reconstruction..." -ForegroundColor Cyan
    Write-Host "  SRR file: $SrrFile"
    Write-Host "  Source: $SourcePath"
    Write-Host "  Output: $OutputPath"
    Write-Host ""

    # Read all blocks
    $reader = [BlockReader]::new($SrrFile)
    $blocks = $reader.ReadAllBlocks()

    Write-Host "Parsed $($blocks.Count) blocks from SRR file" -ForegroundColor Green

    # Optionally extract stored files (NFO/SFV/etc.) alongside reconstructed volumes
    if ($ExtractStoredFiles) {
        $storedBlocks = $blocks | Where-Object { $_ -is [SrrStoredFileBlock] }
        if ($storedBlocks.Count -eq 0) {
            Write-Host "No stored files found in SRR" -ForegroundColor Yellow
        }
        else {
            Write-Host "Extracting stored files..." -ForegroundColor Cyan

            $fs = [System.IO.File]::OpenRead($SrrFile)
            try {
                $br = [BinaryReader]::new($fs)
                $currentPos = 0

                foreach ($block in $blocks) {
                    $blockSize = $block.HeadSize + $block.AddSize

                    if ($block -is [SrrStoredFileBlock]) {
                        # Guard against rooted paths and preserve relative names
                        $relativePath = $block.FileName.TrimStart([char]92, [char]47)
                        $targetPath = Join-Path $OutputPath $relativePath
                        $targetDir = Split-Path $targetPath -Parent
                        if ($targetDir -and -not (Test-Path $targetDir)) {
                            if ($PSCmdlet.ShouldProcess($targetDir, "Create directory")) {
                                [System.IO.Directory]::CreateDirectory($targetDir) | Out-Null
                            }
                        }

                        $dataStart = $currentPos + $block.HeadSize
                        $fs.Seek($dataStart, [SeekOrigin]::Begin) | Out-Null

                        $fileData = $br.ReadBytes([int]$block.FileSize)
                        [System.IO.File]::WriteAllBytes($targetPath, $fileData)

                        Write-Host "  Extracted stored file: $($block.FileName) ($($block.FileSize) bytes)" -ForegroundColor Gray
                    }

                    $currentPos += $blockSize
                }
            }
            finally {
                $br.Dispose()
                $fs.Close()
            }
        }
    }

    # Group blocks by RAR volume
    $rarVolumes = @{}
    $currentVolume = $null

    foreach ($block in $blocks) {
        if ($block -is [SrrRarFileBlock]) {
            $currentVolume = $block.FileName
            $rarVolumes[$currentVolume] = @{
                RarFileBlock = $block
                Blocks = [System.Collections.Generic.List[Object]]::new()
            }
        }
        elseif ($currentVolume -and (
            $block -is [RarMarkerBlock] -or
            $block -is [RarVolumeHeaderBlock] -or
            $block -is [RarPackedFileBlock] -or
            $block -is [RarEndArchiveBlock]
        )) {
            $rarVolumes[$currentVolume].Blocks.Add($block)
        }
    }

    Write-Host "Found $($rarVolumes.Count) RAR volumes to reconstruct" -ForegroundColor Green

    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory | Out-Null
    }

    # Process each volume
    $sourceFile = $null
    $sourceFileHandle = $null
    $sourceFileOffset = [long]0

    try {
        # Sort volumes: .rar first, then .r00, .r01, etc
        $sortedVolumes = $rarVolumes.Keys | Sort-Object {
            if ($_ -match '\.rar$') { 0 }  # .rar is first
            elseif ($_ -match '\.r(\d+)$') { [int]$matches[1] + 1 }  # .r00=1, .r01=2, etc
            else { 999 }
        }
        foreach ($volumeName in $sortedVolumes) {
            $volumeData = $rarVolumes[$volumeName]
            $outputFile = Join-Path $OutputPath $volumeName

            Write-Host "Reconstructing: $volumeName" -ForegroundColor Yellow

            # Create output file
            $rarStream = [System.IO.FileStream]::new($outputFile, [System.IO.FileMode]::Create)

            try {
                foreach ($block in $volumeData.Blocks) {
                    if ($block -is [RarMarkerBlock]) {
                        # Write marker block (7 bytes fixed)
                        $markerBytes = [byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00)
                        $rarStream.Write($markerBytes, 0, $markerBytes.Length)
                    }
                    elseif ($block -is [RarVolumeHeaderBlock]) {
                        # Write archive header block from original SRR data
                        $blockBytes = $block.GetBlockBytes()
                        $rarStream.Write($blockBytes, 0, $blockBytes.Length)
                    }
                    elseif ($block -is [RarPackedFileBlock]) {
                        # Find and validate source file if not already open
                        if ($sourceFile -ne $block.FileName) {
                            if ($sourceFileHandle) {
                                $sourceFileHandle.Close()
                                $sourceFileHandle = $null
                            }

                            $sourceFile = $block.FileName
                            $sourceFileOffset = 0

                            # Locate source file
                            $sourcePath = Find-SourceFile -FileName $block.FileName -SearchPath $SourcePath -ExpectedSize $block.FullUnpackedSize

                            if (-not $sourcePath) {
                                throw "Source file not found: $($block.FileName)"
                            }

                            Write-Host "  Using source: $sourcePath" -ForegroundColor Gray

                            $sourceFileHandle = [System.IO.File]::OpenRead($sourcePath)

                            # Validate source file size on first use
                            if (-not $SkipValidation) {
                                $fileInfo = Get-Item $sourcePath
                                if ($fileInfo.Length -ne $block.FullUnpackedSize) {
                                    throw "Source file size mismatch: Expected $($block.FullUnpackedSize) bytes, found $($fileInfo.Length) bytes"
                                }
                            }
                        }

                        # Write RAR packed file header from SRR
                        $blockBytes = $block.GetBlockBytes()
                        $rarStream.Write($blockBytes, 0, $blockBytes.Length)

                        # Copy packed data from source file at current offset
                        # For STORING (no compression), packed size = unpacked chunk size in this volume
                        if ($block.FullPackedSize -gt 0) {
                            # Seek to correct position in source file
                            $sourceFileHandle.Seek($sourceFileOffset, [System.IO.SeekOrigin]::Begin) | Out-Null

                            $buffer = New-Object byte[] 65536
                            $remaining = [long]$block.FullPackedSize

                            while ($remaining -gt 0) {
                                $toRead = [Math]::Min($remaining, $buffer.Length)
                                $bytesRead = $sourceFileHandle.Read($buffer, 0, $toRead)
                                if ($bytesRead -eq 0) { break }

                                $rarStream.Write($buffer, 0, $bytesRead)
                                $remaining -= $bytesRead
                                $sourceFileOffset += $bytesRead
                            }
                        }
                    }
                    elseif ($block -is [RarEndArchiveBlock]) {
                        # Write end archive block from SRR
                        $blockBytes = $block.GetBlockBytes()
                        $rarStream.Write($blockBytes, 0, $blockBytes.Length)
                    }
                }

                Write-Host "  Created: $outputFile ($($rarStream.Length) bytes)" -ForegroundColor Green
            }
            finally {
                $rarStream.Close()
            }
        }
    }
    finally {
        if ($sourceFileHandle) {
            $sourceFileHandle.Close()
        }
    }

    Write-Host ""
    Write-Host "Reconstruction complete!" -ForegroundColor Green

    # Validate reconstructed files
    Test-ReconstructedRar -SrrFile $SrrFile -OutputPath $OutputPath
}

#endregion

#region Main Entry Point

function Invoke-SrrRestore {
    <#
    .SYNOPSIS
        Complete SRR restoration - extracts stored files, reconstructs archives, validates, and cleans up.

    .DESCRIPTION
        This is the main entry point for SRR restoration. It performs:
        - Auto-detection of SRR file if not specified
        - Auto-detection of source files
        - Extraction of all stored files (NFO, SFV, etc.)
        - Reconstruction of RAR volumes
        - CRC validation against SFV
        - Cleanup of temporary and source files (with confirmation)

    .PARAMETER SrrFile
        Path to SRR file. If not specified, searches current directory for a single .srr file.

    .PARAMETER SourcePath
        Directory containing source files. Defaults to current directory.

    .PARAMETER OutputPath
        Directory for reconstructed release. Defaults to current directory.

    .PARAMETER KeepSrr
        If specified, do not delete SRR file after successful restoration.

    .PARAMETER KeepSources
        If specified, do not delete source files (e.g., .mkv) after successful restoration.

    .EXAMPLE
        Invoke-SrrRestore
        # Simplest usage - auto-detects SRR, sources in CWD, outputs to CWD

    .EXAMPLE
        Invoke-SrrRestore -SrrFile "Release.srr" -KeepSrr
        # Specify SRR explicitly and keep it after restoration
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter()]
        [string]$SrrFile = "",

        [Parameter()]
        [string]$SourcePath = ".",

        [Parameter()]
        [string]$OutputPath = ".",

        [Parameter()]
        [switch]$KeepSrr,

        [Parameter()]
        [switch]$KeepSources
    )

    Write-Host ""
    Write-Host "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Cyan
    Write-Host "              SRR Release Restoration" -ForegroundColor Cyan
    Write-Host "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Cyan
    Write-Host ""

    # Track files we create for potential cleanup
    $script:createdFiles = @()
    $script:validationPassed = $false

    try {
        # Step 1: Auto-detect or validate SRR file
        Write-Host "[1/6] Locating SRR file..." -ForegroundColor Yellow

        if ([string]::IsNullOrWhiteSpace($SrrFile)) {
            # Auto-detect SRR in current directory
            $srrFiles = Get-ChildItem -Path $SourcePath -Filter "*.srr" -File -ErrorAction SilentlyContinue

            if ($srrFiles.Count -eq 0) {
                throw "No SRR file found in current directory. Specify -SrrFile parameter or place .srr file in current directory."
            }
            elseif ($srrFiles.Count -gt 1) {
                Write-Host "  Multiple SRR files found:" -ForegroundColor Red
                foreach ($f in $srrFiles) {
                    Write-Host "    - $($f.Name)" -ForegroundColor Red
                }
                throw "Multiple SRR files found. Please specify which SRR to process using -SrrFile parameter."
            }
            else {
                $SrrFile = $srrFiles[0].FullName
                Write-Host "  [OK] Auto-detected: $($srrFiles[0].Name)" -ForegroundColor Green
            }
        }
        else {
            # Resolve provided path
            $SrrFile = (Resolve-Path -Path $SrrFile -ErrorAction Stop).Path
            Write-Host "  [OK] Using: $(Split-Path $SrrFile -Leaf)" -ForegroundColor Green
        }

        # Resolve other paths
        $SourcePath = (Resolve-Path -Path $SourcePath -ErrorAction Stop).Path

        # Normalize and ensure OutputPath exists (respect -WhatIf)
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        if (-not [System.IO.Directory]::Exists($OutputPath)) {
            if ($PSCmdlet.ShouldProcess($OutputPath, "Create directory")) {
                [System.IO.Directory]::CreateDirectory($OutputPath) | Out-Null
            }
        }

        Write-Host ""

        # Step 2: Parse SRR and discover source files
        Write-Host "[2/6] Parsing SRR and discovering source files..." -ForegroundColor Yellow

        $reader = [BlockReader]::new($SrrFile)
        $blocks = $reader.ReadAllBlocks()
        $reader.Close()

        Write-Host "  Parsed $($blocks.Count) blocks" -ForegroundColor Gray

        # Find all unique source files referenced in RAR packed file blocks
        $sourceFiles = @{}
        $packedBlocks = $blocks | Where-Object { $_ -is [RarPackedFileBlock] }

        foreach ($block in $packedBlocks) {
            if (-not $sourceFiles.ContainsKey($block.FileName)) {
                $sourceFiles[$block.FileName] = @{
                    Name = $block.FileName
                    Size = $block.FullUnpackedSize
                    Path = $null
                }
            }
        }

        if ($sourceFiles.Count -eq 0) {
            throw "No source files found in SRR metadata"
        }

        Write-Host "  Required source files: $($sourceFiles.Count)" -ForegroundColor Gray

        # Auto-detect each source file
        $allFound = $true
        foreach ($fileName in $sourceFiles.Keys) {
            $fileInfo = $sourceFiles[$fileName]
            $foundPath = Find-SourceFile -FileName $fileName -SearchPath $SourcePath -ExpectedSize $fileInfo.Size

            if ($foundPath) {
                $sourceFiles[$fileName].Path = $foundPath
                Write-Host "  [OK] Found: $fileName" -ForegroundColor Green
            }
            else {
                $sizeGB = [Math]::Round($fileInfo.Size / 1GB, 2)
                Write-Host ("  [X] Missing: {0} ({1} GB)" -f $fileName, $sizeGB) -ForegroundColor Red
                $allFound = $false
            }
        }

        if (-not $allFound) {
            throw "Required source file(s) not found. Searched in: $SourcePath"
        }

        Write-Host ""

        # Step 3: Extract all stored files
        Write-Host "[3/6] Extracting stored files..." -ForegroundColor Yellow

        $storedBlocks = $blocks | Where-Object { $_ -is [SrrStoredFileBlock] }

        if ($storedBlocks.Count -eq 0) {
            Write-Host "  No stored files found in SRR" -ForegroundColor Gray
        }
        else {
            $fs = [System.IO.File]::OpenRead($SrrFile)
            try {
                $br = [BinaryReader]::new($fs)
                $currentPos = 0

                foreach ($block in $blocks) {
                    $blockSize = $block.HeadSize + $block.AddSize

                    if ($block -is [SrrStoredFileBlock]) {
                        # Skip SRR container itself if present in stored list
                        if ($block.FileName -match '\.srr$') {
                            $currentPos += $blockSize
                            continue
                        }

                        # Guard against rooted paths and preserve relative names
                        $relativePath = $block.FileName.TrimStart('\', '/')
                        $targetPath = Join-Path $OutputPath $relativePath
                        $targetDir = Split-Path $targetPath -Parent

                        if ($targetDir -and -not (Test-Path $targetDir)) {
                            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                        }

                        $dataStart = $currentPos + $block.HeadSize
                        $fs.Seek($dataStart, [SeekOrigin]::Begin) | Out-Null

                        $fileData = $br.ReadBytes([int]$block.FileSize)
                        if ($PSCmdlet.ShouldProcess($targetPath, "Write stored file")) {
                            [System.IO.File]::WriteAllBytes($targetPath, $fileData)
                            $script:createdFiles += $targetPath
                            if ($targetPath.ToLower().EndsWith('.srs')) {
                                $info = Get-SrsInfo -FilePath $targetPath
                                Write-Host ("  [OK] Extracted SRS: {0} [{1}]" -f $block.FileName, $info.Type) -ForegroundColor Green
                            }
                            else {
                                Write-Host "  [OK] Extracted: $($block.FileName)" -ForegroundColor Green
                            }
                        }
                    }

                    $currentPos += $blockSize
                }
            }
            finally {
                $br.Dispose()
                $fs.Close()
            }
        }

        Write-Host ""

        # Step 3.5: Reconstruct video samples from SRS (if present and not under -WhatIf)
        $srsFiles = $storedBlocks | Where-Object { $_.FileName -match '\.srs$' }
        if ($srsFiles.Count -gt 0 -and -not $WhatIfPreference) {
            Write-Host "[3b/6] Reconstructing video samples from SRS..." -ForegroundColor Yellow

            foreach ($srsBlock in $srsFiles) {
                $srsPath = Join-Path $OutputPath $srsBlock.FileName

                if (Test-Path $srsPath) {
                    # Determine output sample filename (replace .srs with .mkv or .mp4)
                    $sampleBaseName = $srsPath -replace '\.(srs)$', '.mkv'

                    # Find source file for this sample (usually in source metadata or named similarly)
                    # For now, use the primary source file
                    $sourcePath = $sourceFiles.Values | Select-Object -First 1 | Select-Object -ExpandProperty Path

                    if ($sourcePath -and (Test-Path $sourcePath)) {
                        $reconstructed = Restore-SrsVideo -SrsFilePath $srsPath -SourceMkvPath $sourcePath -OutputMkvPath $sampleBaseName

                        if ($reconstructed) {
                            $script:createdFiles += $sampleBaseName
                        }
                    }
                    else {
                        Write-Warning "  Source file not available for SRS reconstruction"
                    }
                }
            }

            Write-Host ""
        }

        # Step 4: Reconstruct RAR volumes
        Write-Host "[4/6] Reconstructing RAR volumes..." -ForegroundColor Yellow

        # Group blocks by RAR volume
        $rarVolumes = @{}
        $currentVolume = $null

        foreach ($block in $blocks) {
            if ($block -is [SrrRarFileBlock]) {
                $currentVolume = $block.FileName
                $rarVolumes[$currentVolume] = @{
                    RarFileBlock = $block
                    Blocks = [System.Collections.Generic.List[Object]]::new()
                }
            }
            elseif ($currentVolume -and (
                $block -is [RarMarkerBlock] -or
                $block -is [RarVolumeHeaderBlock] -or
                $block -is [RarPackedFileBlock] -or
                $block -is [RarEndArchiveBlock]
            )) {
                $rarVolumes[$currentVolume].Blocks.Add($block)
            }
        }

        Write-Host "  RAR volumes to reconstruct: $($rarVolumes.Count)" -ForegroundColor Gray

        # Sort volumes: .rar first, then .r00, .r01, etc
        $sortedVolumes = $rarVolumes.Keys | Sort-Object {
            if ($_ -match '\.rar$') { 0 }
            elseif ($_ -match '\.r(\d+)$') { [int]$matches[1] + 1 }
            else { 999 }
        }

        # If -WhatIf: preview sources and target output files without writing
        if ($WhatIfPreference) {
            Write-Host "  Preview sources:" -ForegroundColor Gray
            foreach ($sf in $sourceFiles.Values) {
                Write-Host ("    - {0} <= {1}" -f $sf.Name, $sf.Path) -ForegroundColor Gray
            }
            Write-Host "  Preview outputs:" -ForegroundColor Gray
            foreach ($v in $sortedVolumes) {
                $previewPath = Join-Path $OutputPath $v
                Write-Host ("    - {0}" -f $previewPath) -ForegroundColor Gray
            }
        }

        $sourceFileHandle = $null
        $currentSourceFile = $null
        $sourceFileOffset = [long]0

        try {
            foreach ($volumeName in $sortedVolumes) {
                $volumeData = $rarVolumes[$volumeName]
                $outputFile = Join-Path $OutputPath $volumeName

                $proceed = $PSCmdlet.ShouldProcess($outputFile, "Create RAR volume")
                if (-not $proceed) { continue }

                $rarStream = [System.IO.FileStream]::new($outputFile, [System.IO.FileMode]::Create)

                try {
                    foreach ($block in $volumeData.Blocks) {
                        if ($block -is [RarMarkerBlock]) {
                            $markerBytes = [byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00)
                            $rarStream.Write($markerBytes, 0, $markerBytes.Length)
                        }
                        elseif ($block -is [RarVolumeHeaderBlock]) {
                            $blockBytes = $block.GetBlockBytes()
                            $rarStream.Write($blockBytes, 0, $blockBytes.Length)
                        }
                        elseif ($block -is [RarPackedFileBlock]) {
                            # Open source file if needed
                            if ($currentSourceFile -ne $block.FileName) {
                                if ($sourceFileHandle) {
                                    $sourceFileHandle.Close()
                                    $sourceFileHandle = $null
                                }

                                $currentSourceFile = $block.FileName
                                $sourceFileOffset = 0

                                # Get source path from our discovered list
                                $sourcePath = $sourceFiles[$block.FileName].Path

                                if (-not $sourcePath) {
                                    throw "Source file not found: $($block.FileName)"
                                }

                                $sourceFileHandle = [System.IO.File]::OpenRead($sourcePath)
                            }

                            # Write file header
                            $blockBytes = $block.GetBlockBytes()
                            $rarStream.Write($blockBytes, 0, $blockBytes.Length)

                            # Copy chunk data from source
                            $chunkSize = $block.FullPackedSize
                            $buffer = New-Object byte[] ([Math]::Min($chunkSize, 1MB))
                            $remaining = $chunkSize

                            $sourceFileHandle.Seek($sourceFileOffset, [SeekOrigin]::Begin) | Out-Null

                            while ($remaining -gt 0) {
                                $toRead = [Math]::Min($remaining, $buffer.Length)
                                $bytesRead = $sourceFileHandle.Read($buffer, 0, $toRead)

                                if ($bytesRead -eq 0) {
                                    throw "Unexpected end of source file"
                                }

                                $rarStream.Write($buffer, 0, $bytesRead)
                                $remaining -= $bytesRead
                            }

                            $sourceFileOffset += $chunkSize
                        }
                        elseif ($block -is [RarEndArchiveBlock]) {
                            $blockBytes = $block.GetBlockBytes()
                            $rarStream.Write($blockBytes, 0, $blockBytes.Length)
                        }
                    }
                }
                finally {
                    $rarStream.Close()
                }

                $script:createdFiles += $outputFile
                $fileSize = (Get-Item $outputFile).Length
                Write-Host "  [OK] Created: $volumeName ($fileSize bytes)" -ForegroundColor Green
            }
        }
        finally {
            if ($sourceFileHandle) {
                $sourceFileHandle.Close()
            }
        }

        Write-Host ""

        # Step 5: Validate reconstructed archives
        Write-Host "[5/6] Validating reconstructed archives..." -ForegroundColor Yellow

        # Respect -WhatIf: skip validation to avoid temp file writes, but allow cleanup preview
        if ($WhatIfPreference) {
            Write-Host "  Skipping validation under -WhatIf (no temp files written)" -ForegroundColor Gray
            $script:validationPassed = $true
        }
        else {
            # Extract and parse SFV
            $tempSfv = [System.IO.Path]::GetTempFileName() + ".sfv"
            $sfvFound = $false

            try {
                # Try to extract SFV from SRR
                $storedSfv = $storedBlocks | Where-Object { $_.FileName -match '\.sfv$' } | Select-Object -First 1

                if ($storedSfv) {
                    $fs = [System.IO.File]::OpenRead($SrrFile)
                    try {
                        $br = [BinaryReader]::new($fs)
                        $currentPos = 0

                        foreach ($block in $blocks) {
                            $blockSize = $block.HeadSize + $block.AddSize

                            if ($block -eq $storedSfv) {
                                $dataStart = $currentPos + $block.HeadSize
                                $fs.Seek($dataStart, [SeekOrigin]::Begin) | Out-Null
                                $fileData = $br.ReadBytes([int]$block.FileSize)
                                [System.IO.File]::WriteAllBytes($tempSfv, $fileData)
                                $sfvFound = $true
                                break
                            }

                            $currentPos += $blockSize
                        }
                    }
                    finally {
                        $br.Dispose()
                        $fs.Close()
                    }
                }

                if (-not $sfvFound) {
                    Write-Warning "  SFV file not found in SRR, skipping CRC validation"
                }
                else {
                    # Parse SFV
                    $sfvData = ConvertFrom-SfvFile -FilePath $tempSfv
                    Write-Host "  SFV entries: $($sfvData.Count)" -ForegroundColor Gray

                    # Validate each RAR file
                    $allValid = $true
                    $validCount = 0
                    $failCount = 0

                    foreach ($rarFile in $sfvData.Keys | Sort-Object) {
                        $rarPath = Join-Path $OutputPath $rarFile

                        if (-not (Test-Path $rarPath)) {
                            Write-Host "  [X] $rarFile - NOT FOUND" -ForegroundColor Red
                            $allValid = $false
                            $failCount++
                            continue
                        }

                        $expectedCrc = $sfvData[$rarFile]
                        $actualCrc = (get-crc32 -Path $rarPath).Hash
                        $actualCrcInt = [Convert]::ToUInt32($actualCrc, 16)

                        if ($actualCrcInt -eq $expectedCrc) {
                            Write-Host "  [OK] $rarFile" -ForegroundColor Green
                            $validCount++
                        }
                        else {
                            Write-Host ("  [X] $rarFile - CRC mismatch" -f $expectedCrc, $actualCrcInt) -ForegroundColor Red
                            $allValid = $false
                            $failCount++
                        }
                    }

                    if (-not $allValid) {
                        throw "Validation failed! $validCount valid, $failCount failed. Files not cleaned up for inspection."
                    }

                    $script:validationPassed = $true
                    Write-Host "  All $validCount RAR files validated successfully!" -ForegroundColor Green
                }
            }
            finally {
                Remove-Item $tempSfv -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Host ""

        # Step 6: Cleanup (only if validation passed)
            if ($script:validationPassed) {
            Write-Host "[6/6] Cleanup..." -ForegroundColor Yellow

            # SRR deletion via ShouldProcess/-Confirm
            if (-not $KeepSrr) {
                if ($PSCmdlet.ShouldProcess($SrrFile, "Delete SRR")) {
                    if (Test-Path $SrrFile) {
                        Remove-Item $SrrFile -Force -ErrorAction SilentlyContinue
                        Write-Host "  [OK] Deleted SRR: $(Split-Path $SrrFile -Leaf)" -ForegroundColor Gray
                    }
                }
                else {
                    Write-Host "  Keeping SRR (confirmation declined)" -ForegroundColor Gray
                }
            }
            else {
                Write-Host "  Keeping SRR (KeepSrr specified)" -ForegroundColor Gray
            }

            # Source deletions via ShouldProcess/-Confirm
            if (-not $KeepSources) {
                foreach ($fileName in $sourceFiles.Keys) {
                    $srcPath = $sourceFiles[$fileName].Path
                    if ($PSCmdlet.ShouldProcess($srcPath, "Delete source")) {
                        if (Test-Path $srcPath) {
                            Remove-Item $srcPath -Force -ErrorAction SilentlyContinue
                            Write-Host "  [OK] Deleted source: $(Split-Path $srcPath -Leaf)" -ForegroundColor Gray
                        }
                    }
                }
            }
            else {
                Write-Host "  Keeping source files (KeepSources specified)" -ForegroundColor Gray
            }

            # SRS deletions via ShouldProcess/-Confirm
            $srsBlocks = $storedBlocks | Where-Object { $_.FileName -match '\.srs$' }
            foreach ($srsBlock in $srsBlocks) {
                $srsPath = Join-Path $OutputPath $srsBlock.FileName
                if (Test-Path $srsPath) {
                    if ($PSCmdlet.ShouldProcess($srsPath, "Delete SRS")) {
                        Remove-Item $srsPath -Force -ErrorAction SilentlyContinue
                        Write-Host "  [OK] Deleted SRS: $(Split-Path $srsPath -Leaf)" -ForegroundColor Gray
                    }
                }
            }

            Write-Host ""
            Write-Host "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Green
            Write-Host "         Restoration Complete & Validated!" -ForegroundColor Green
            Write-Host "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Green
            Write-Host ""
            Write-Host "Output directory: $OutputPath" -ForegroundColor Cyan
            Write-Host "  - RAR volumes: $($rarVolumes.Count)" -ForegroundColor Gray
            Write-Host "  - Stored files: $($storedBlocks.Count)" -ForegroundColor Gray
            Write-Host ""
        }
        else {
            Write-Host ""
            Write-Host "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Yellow
            Write-Host "     Restoration Complete (Validation Skipped)" -ForegroundColor Yellow
            Write-Host "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Yellow
            Write-Host ""
            Write-Warning "Validation was skipped or failed. No cleanup performed."
            Write-Host "Output directory: $OutputPath" -ForegroundColor Cyan
            Write-Host ""
        }

    }
    catch {
        Write-Host ""
        Write-Host "[X] Restoration failed: $_" -ForegroundColor Red
        Write-Host ""
        throw
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    # SRR functions
    'Get-SrrBlock',
    'Show-SrrInfo',
    'Invoke-SrrReconstruct',
    'Invoke-SrrRestore',
    # SRS/Sample functions
    'ConvertFrom-SrsFileMetadata',
    'Export-SampleTrackData',
    'Restore-SrsVideo',
    'Build-SampleMkvFromSrs',
    # EBML parser functions
    'Get-EbmlUIntLength',
    'Get-EbmlUInt',
    'Get-EbmlElementID',
    'Read-EbmlUIntStream',
    'Get-EbmlElementFromBuffer',
    'ConvertTo-EbmlElementString',
    # SRS parser functions
    'ConvertFrom-SrsFile',
    'ConvertFrom-SrsFileData',
    'ConvertFrom-SrsTrackData',
    'ConvertTo-ByteString',
    'Compare-ByteArray'
)

