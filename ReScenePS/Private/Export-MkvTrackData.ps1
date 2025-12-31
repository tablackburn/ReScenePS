function Export-MkvTrackData {
    <#
    .SYNOPSIS
    Extract track data from main MKV by parsing EBML structure.

    .PARAMETER MainFilePath
    Path to the main MKV file.

    .PARAMETER Tracks
    Hashtable of track metadata from SRS (keyed by track number).

    .PARAMETER OutputFiles
    Hashtable to receive output file paths (keyed by track number).

    .OUTPUTS
    System.Boolean
    Returns $true if extraction was successful.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Compare-Bytes', Justification = 'Bytes refers to byte arrays being compared')]
    [CmdletBinding()]
    [OutputType([bool])]
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

    function Get-EbmlVarLength { param([byte]$FirstByte); for ($i = 0; $i -lt 8; $i++) { if (($FirstByte -band (0x80 -shr $i)) -ne 0) { return $i + 1 } }; return 0 }
    function Read-EbmlVarInt { param([System.IO.BinaryReader]$Reader); $firstByte = $Reader.ReadByte(); $bytes = Get-EbmlVarLength $firstByte; [uint64]$mask = 0xFF -shr $bytes; [uint64]$value = ($firstByte -band $mask); $rawBytes = New-Object byte[] $bytes; $rawBytes[0] = $firstByte; for ($i = 1; $i -lt $bytes; $i++) { $rawBytes[$i] = $Reader.ReadByte(); $value = ($value -shl 8) + $rawBytes[$i] }; return @{ Value = $value; Bytes = $bytes; RawBytes = $rawBytes } }
    function Read-EbmlId { param([System.IO.BinaryReader]$Reader); $firstByte = $Reader.ReadByte(); $len = Get-EbmlVarLength $firstByte; $id = New-Object byte[] $len; $id[0] = $firstByte; for ($i = 1; $i -lt $len; $i++) { $id[$i] = $Reader.ReadByte() }; return $id }
    function Compare-Bytes { param([byte[]]$A, [byte[]]$B); if ($null -eq $A -or $null -eq $B) { return $false }; if ($A.Length -ne $B.Length) { return $false }; for ($i = 0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }; return $true }

    $ID_Segment = [byte[]]@(0x18, 0x53, 0x80, 0x67); $ID_Cluster = [byte[]]@(0x1F, 0x43, 0xB6, 0x75); $ID_BlockGroup = [byte[]]@(0xA0); $ID_Block = [byte[]]@(0xA1); $ID_SimpleBlock = [byte[]]@(0xA3)

    try {
        $fs = [System.IO.File]::OpenRead($MainFilePath)
        $reader = [System.IO.BinaryReader]::new($fs)
        $fileSize = $fs.Length

        [uint64]$startOffset = [uint64]::MaxValue
        foreach ($trackNum in $Tracks.Keys) { $track = $Tracks[$trackNum]; if ($track.MatchOffset -gt 0 -and $track.MatchOffset -lt $startOffset) { $startOffset = $track.MatchOffset } }

        $trackStreams = @{}; $trackBytesWritten = @{}
        foreach ($trackNum in $Tracks.Keys) { $tempFile = [System.IO.Path]::GetTempFileName() + ".track$trackNum"; $trackStreams[$trackNum] = [System.IO.File]::Create($tempFile); $trackBytesWritten[$trackNum] = [uint64]0; $OutputFiles[$trackNum] = $tempFile }

        $clusterCount = 0; $blockCount = 0; $done = $false

        $null = Read-EbmlId -Reader $reader; $ebmlSize = Read-EbmlVarInt -Reader $reader; $fs.Seek([int64]$ebmlSize.Value, [System.IO.SeekOrigin]::Current) | Out-Null
        $null = Read-EbmlId -Reader $reader; $null = Read-EbmlVarInt -Reader $reader

        while ($fs.Position -lt $fileSize -and -not $done) {
            $elemStart = $fs.Position
            try { $elemId = Read-EbmlId -Reader $reader; $sizeInfo = Read-EbmlVarInt -Reader $reader; $elemSize = $sizeInfo.Value } catch { break }
            $headerLen = $elemId.Length + $sizeInfo.Bytes

            if (Compare-Bytes -A $elemId -B $ID_Segment) { continue }
            if (Compare-Bytes -A $elemId -B $ID_Cluster) { $clusterCount++; $clusterEnd = $elemStart + $headerLen + $elemSize; if ($clusterEnd -lt $startOffset) { $fs.Seek([int64]$elemSize, [System.IO.SeekOrigin]::Current) | Out-Null; continue }; continue }
            if (Compare-Bytes -A $elemId -B $ID_BlockGroup) { continue }

            if ((Compare-Bytes -A $elemId -B $ID_Block) -or (Compare-Bytes -A $elemId -B $ID_SimpleBlock)) {
                $blockCount++; $blockStart = $fs.Position; $trackInfo = Read-EbmlVarInt -Reader $reader; $trackNumber = [uint16]$trackInfo.Value
                $tcFlags = $reader.ReadBytes(3); $flags = $tcFlags[2]; $laceType = ($flags -band 0x06) -shr 1
                $blockHeaderSize = $trackInfo.Bytes + 3; $frameLengths = @()
                if ($laceType -ne 0) { $frameCountByte = $reader.ReadByte(); $blockHeaderSize++; $frameCount = $frameCountByte + 1; $frameLengths = New-Object int[] $frameCount; $lacingBytesRead = 0
                    if ($laceType -eq 1) { for ($f = 0; $f -lt ($frameCount - 1); $f++) { $frameSize = 0; do { $laceByte = $reader.ReadByte(); $lacingBytesRead++; $frameSize += $laceByte } while ($laceByte -eq 255); $frameLengths[$f] = $frameSize } }
                    elseif ($laceType -eq 3) { $firstSizeInfo = Read-EbmlVarInt -Reader $reader; $lacingBytesRead += $firstSizeInfo.Bytes; $frameLengths[0] = [int]$firstSizeInfo.Value; for ($f = 1; $f -lt ($frameCount - 1); $f++) { $deltaInfo = Read-EbmlVarInt -Reader $reader; $lacingBytesRead += $deltaInfo.Bytes; $delta = [int64]$deltaInfo.Value - ((1 -shl ($deltaInfo.Bytes * 7)) - 1); $frameLengths[$f] = $frameLengths[$f - 1] + [int]$delta } }
                    $blockHeaderSize += $lacingBytesRead
                } else { $frameLengths = @(0) }
                $frameDataSize = [int]$elemSize - $blockHeaderSize
                if ($laceType -eq 2 -and $frameLengths.Count -gt 0) { $frameSize = [int]($frameDataSize / $frameLengths.Count); for ($f = 0; $f -lt $frameLengths.Count; $f++) { $frameLengths[$f] = $frameSize } }
                elseif ($laceType -eq 0) { $frameLengths[0] = $frameDataSize }
                elseif ($laceType -ne 0) { $usedSize = 0; for ($f = 0; $f -lt ($frameLengths.Count - 1); $f++) { $usedSize += $frameLengths[$f] }; $frameLengths[$frameLengths.Count - 1] = $frameDataSize - $usedSize }

                if ($Tracks.ContainsKey($trackNumber)) {
                    $track = $Tracks[$trackNumber]; $trackStream = $trackStreams[$trackNumber]; $frameDataStart = $blockStart + $blockHeaderSize
                    if ($frameDataStart -ge $track.MatchOffset) { if ($trackBytesWritten[$trackNumber] -lt $track.DataLength) { $fs.Seek($frameDataStart, [System.IO.SeekOrigin]::Begin) | Out-Null; $toRead = [Math]::Min($frameDataSize, $track.DataLength - $trackBytesWritten[$trackNumber]); $frameData = $reader.ReadBytes([int]$toRead); $trackStream.Write($frameData, 0, $frameData.Length); $trackBytesWritten[$trackNumber] += $frameData.Length } }
                    $done = $true; foreach ($tNum in $Tracks.Keys) { if ($trackBytesWritten[$tNum] -lt $Tracks[$tNum].DataLength) { $done = $false; break } }
                }
                $blockEnd = $elemStart + $headerLen + $elemSize; $fs.Seek($blockEnd, [System.IO.SeekOrigin]::Begin) | Out-Null; continue
            }
            $fs.Seek([int64]$elemSize, [System.IO.SeekOrigin]::Current) | Out-Null
        }

        foreach ($stream in $trackStreams.Values) { $stream.Flush(); $stream.Dispose() }
        $reader.Dispose(); $fs.Close()
        Write-Verbose "Extracted tracks from $clusterCount clusters, $blockCount blocks"
        return $true
    }
    catch { foreach ($stream in $trackStreams.Values) { if ($null -ne $stream) { $stream.Dispose() } }; throw "Failed to extract MKV track data: $_" }
}
