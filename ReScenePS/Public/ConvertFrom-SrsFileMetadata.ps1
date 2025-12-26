function ConvertFrom-SrsFileMetadata {
    <#
    .SYNOPSIS
        Parse EBML SRS file to extract track metadata and match offsets.

    .DESCRIPTION
        Reads SRS file structure to extract:
        - FileData: original file size, CRC32, filename
        - TrackData: match_offset, data_length, signature_bytes for each track

        This metadata is used to know WHERE and HOW MUCH to extract from the main file.

    .PARAMETER SrsFilePath
        Path to the extracted .srs file (EBML format).

    .EXAMPLE
        $metadata = ConvertFrom-SrsFileMetadata -SrsFilePath "sample.srs"
        $metadata.Tracks | ForEach-Object { "Track $($_.TrackNumber): offset $($_.MatchOffset)" }

    .OUTPUTS
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
        $br = [System.IO.BinaryReader]::new($fs)
        $srsSize = $fs.Length

        $metadata = @{
            FileData = $null
            Tracks = @()
            SrsSize = $srsSize
        }

        # Helper functions to parse EBML variable-length integers and IDs
        function Get-UIntLength {
            param([byte]$LengthDescriptor)
            for ($i = 0; $i -lt 8; $i++) {
                $bit = 0x80 -shr $i
                if (($LengthDescriptor -band $bit) -ne 0) { return $i + 1 }
            }
            return 0
        }

        function Read-EbmlVarInt {
            param([System.IO.BinaryReader]$Reader)
            $firstByte = $Reader.ReadByte()
            $bytes = Get-UIntLength -LengthDescriptor $firstByte
            [uint64]$mask = 0xFF -shr $bytes
            [uint64]$value = ($firstByte -band $mask)
            for ($i = 1; $i -lt $bytes; $i++) { $value = ($value -shl 8) + $Reader.ReadByte() }
            return @{ Value = $value; Bytes = $bytes }
        }

        function Read-EbmlElementId {
            param([System.IO.BinaryReader]$Reader)
            $firstByte = $Reader.ReadByte()
            $len = Get-UIntLength -LengthDescriptor $firstByte
            $id = New-Object byte[] $len
            $id[0] = $firstByte
            for ($i = 1; $i -lt $len; $i++) { $id[$i] = $Reader.ReadByte() }
            return $id
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
        $ebmlId = Read-EbmlElementId -Reader $br
        $ebmlSizeInfo = Read-EbmlVarInt -Reader $br
        $fs.Seek([int64]$ebmlSizeInfo.Value, [System.IO.SeekOrigin]::Current) | Out-Null

        # Segment
        $segId = Read-EbmlElementId -Reader $br
        $segSizeInfo = Read-EbmlVarInt -Reader $br
        $segmentStart = $fs.Position
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
                    $data = $br.ReadBytes([int]$dataSize)
                    $off = 0
                    $flags = [BitConverter]::ToUInt16($data, $off)
                    $off += 2

                    $bigTrack = ($flags -band 0x8) -ne 0
                    if ($bigTrack) { $trackNumber = [BitConverter]::ToUInt32($data, $off); $off += 4 }
                    else { $trackNumber = [BitConverter]::ToUInt16($data, $off); $off += 2 }

                    $bigFile = ($flags -band 0x4) -ne 0
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
