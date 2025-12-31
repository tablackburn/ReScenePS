function Build-SampleMkvFromSrs {
    <#
    .SYNOPSIS
        Reconstruct sample MKV by hierarchically parsing SRS and injecting track data.

    .DESCRIPTION
        Hierarchical EBML parsing approach:
        1. Read SRS file element-by-element using proper EBML VLQ decoding
        2. For container elements (Segment, Cluster, BlockGroup): write header, descend into children
        3. Skip ReSample container entirely (metadata only, not in final output)
        4. For Block/SimpleBlock elements: write header + block header + injected track data
        5. For all other elements: copy header + content directly

    .PARAMETER SrsFilePath
        Path to the SRS file containing sample structure.

    .PARAMETER TrackDataFiles
        Hashtable mapping track numbers to extracted track data file paths.

    .PARAMETER OutputMkvPath
        Path for the output reconstructed MKV file.

    .EXAMPLE
        Build-SampleMkvFromSrs -SrsFilePath "sample.srs" -TrackDataFiles @{1="track1.dat"; 2="track2.dat"} -OutputMkvPath "sample.mkv"

        Reconstructs the MKV sample by combining the SRS structure with pre-extracted track data files.

    .OUTPUTS
        System.Boolean
        Returns $true if reconstruction was successful.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Srs is an acronym (Sample ReScene), not a plural')]
    [CmdletBinding()]
    [OutputType([bool])]
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
        function Get-EbmlVarLength { param([byte]$FirstByte); for ($i = 0; $i -lt 8; $i++) { if (($FirstByte -band (0x80 -shr $i)) -ne 0) { return $i + 1 } }; return 0 }
        function Read-EbmlVarInt { param([System.IO.BinaryReader]$Reader); $firstByte = $Reader.ReadByte(); $bytes = Get-EbmlVarLength $firstByte; [uint64]$mask = 0xFF -shr $bytes; [uint64]$value = ($firstByte -band $mask); $rawBytes = New-Object byte[] $bytes; $rawBytes[0] = $firstByte; for ($i = 1; $i -lt $bytes; $i++) { $rawBytes[$i] = $Reader.ReadByte(); $value = ($value -shl 8) + $rawBytes[$i] }; return @{ Value = $value; Bytes = $bytes; RawBytes = $rawBytes } }
        function Read-EbmlId { param([System.IO.BinaryReader]$Reader); $firstByte = $Reader.ReadByte(); $len = Get-EbmlVarLength $firstByte; $id = New-Object byte[] $len; $id[0] = $firstByte; for ($i = 1; $i -lt $len; $i++) { $id[$i] = $Reader.ReadByte() }; return $id }
        function Compare-Bytes { param([byte[]]$A, [byte[]]$B); if ($null -eq $A -or $null -eq $B) { return $false }; if ($A.Length -ne $B.Length) { return $false }; for ($i = 0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }; return $true }
        function Test-ContainerElement { param([byte[]]$ElemId); if ($null -eq $ElemId) { return $false }; $containers = @([byte[]]@(0x18, 0x53, 0x80, 0x67), [byte[]]@(0x1F, 0x43, 0xB6, 0x75), [byte[]]@(0xA0), [byte[]]@(0x19, 0x41, 0xA4, 0x69), [byte[]]@(0x61, 0xA7)); foreach ($c in $containers) { if (Compare-Bytes -A $ElemId -B $c) { return $true } }; return $false }

        $ID_Resample = [byte[]]@(0x1F, 0x69, 0x75, 0x76); $ID_Block = [byte[]]@(0xA1); $ID_SimpleBlock = [byte[]]@(0xA3)

        $trackDataStreams = @{}
        foreach ($key in ($TrackDataFiles.Keys | Sort-Object)) { $trackFile = $TrackDataFiles[$key]; if (Test-Path $trackFile) { $trackDataStreams[$key] = [System.IO.File]::OpenRead($trackFile); Write-Verbose "Opened track data file for track $key : $trackFile" } }

        $srsFs = [System.IO.File]::OpenRead($SrsFilePath)
        $srsReader = [System.IO.BinaryReader]::new($srsFs)
        $srsSize = $srsFs.Length

        $outFs = [System.IO.File]::Create($OutputMkvPath)
        $outWriter = [System.IO.BinaryWriter]::new($outFs)

        try {
            $elemCount = 0; $blockCount = 0; $clusterCount = 0

            while ($srsFs.Position -lt $srsSize) {
                $startPos = $srsFs.Position
                if ($startPos + 2 -gt $srsSize) { break }

                try {
                    $elemId = Read-EbmlId -Reader $srsReader
                    if ($null -eq $elemId -or $elemId.Length -eq 0) { break }
                    $sizeInfo = Read-EbmlVarInt -Reader $srsReader
                    if ($null -eq $sizeInfo -or $null -eq $sizeInfo.RawBytes) { break }
                    $elemSize = $sizeInfo.Value
                    $rawHeader = New-Object byte[] ($elemId.Length + $sizeInfo.RawBytes.Length)
                    [System.Array]::Copy($elemId, 0, $rawHeader, 0, $elemId.Length)
                    [System.Array]::Copy($sizeInfo.RawBytes, 0, $rawHeader, $elemId.Length, $sizeInfo.RawBytes.Length)
                } catch { break }

                if (Compare-Bytes -A $elemId -B $ID_Resample) { $srsFs.Seek($elemSize, [System.IO.SeekOrigin]::Current) | Out-Null; continue }

                if (Test-ContainerElement -ElemId $elemId) {
                    $outWriter.Write($rawHeader, 0, $rawHeader.Length)
                    if (Compare-Bytes -A $elemId -B ([byte[]]@(0x1F, 0x43, 0xB6, 0x75))) { $clusterCount++ }
                    $elemCount++; continue
                }

                if ((Compare-Bytes -A $elemId -B $ID_Block) -or (Compare-Bytes -A $elemId -B $ID_SimpleBlock)) {
                    $blockCount++
                    try {
                        $trackInfo = Read-EbmlVarInt -Reader $srsReader
                        if ($null -eq $trackInfo) { break }
                        $trackNumber = $trackInfo.Value
                        $tcFlags = $srsReader.ReadBytes(3)
                        if ($null -eq $tcFlags -or $tcFlags.Length -lt 3) { break }
                        $flags = $tcFlags[2]; $laceType = ($flags -band 0x06) -shr 1
                        $blockHeaderList = [System.Collections.Generic.List[byte]]::new()
                        foreach ($b in $trackInfo.RawBytes) { $blockHeaderList.Add($b) }
                        foreach ($b in $tcFlags) { $blockHeaderList.Add($b) }

                        if ($laceType -ne 0) {
                            $frameCountByte = $srsReader.ReadByte(); $blockHeaderList.Add($frameCountByte); $frameCount = $frameCountByte + 1
                            if ($laceType -eq 1) { for ($f = 0; $f -lt ($frameCount - 1); $f++) { do { $laceByte = $srsReader.ReadByte(); $blockHeaderList.Add($laceByte) } while ($laceByte -eq 255) } }
                            elseif ($laceType -eq 3) { $firstSizeInfo = Read-EbmlVarInt -Reader $srsReader; foreach ($b in $firstSizeInfo.RawBytes) { $blockHeaderList.Add($b) }; for ($f = 1; $f -lt ($frameCount - 1); $f++) { $deltaInfo = Read-EbmlVarInt -Reader $srsReader; foreach ($b in $deltaInfo.RawBytes) { $blockHeaderList.Add($b) } } }
                        }
                        $blockHeader = $blockHeaderList.ToArray()
                        $frameDataSize = $elemSize - $blockHeader.Length
                        if ($frameDataSize -lt 0) { $frameDataSize = 0 }

                        $outWriter.Write($rawHeader, 0, $rawHeader.Length)
                        $outWriter.Write($blockHeader, 0, $blockHeader.Length)

                        $trackStream = $null
                        foreach ($key in $trackDataStreams.Keys) { if ($key -eq $trackNumber) { $trackStream = $trackDataStreams[$key]; break } }

                        if ($null -ne $trackStream -and $trackStream.Position -lt $trackStream.Length -and $frameDataSize -gt 0) {
                            $frameData = New-Object byte[] $frameDataSize; $bytesRead = $trackStream.Read($frameData, 0, [int]$frameDataSize); $outWriter.Write($frameData, 0, $bytesRead)
                        } elseif ($frameDataSize -gt 0) {
                            $zeros = New-Object byte[] $frameDataSize; $outWriter.Write($zeros, 0, $zeros.Length)
                        }
                        # Skip past placeholder frame data in SRS file
                        if ($frameDataSize -gt 0) { $srsReader.ReadBytes([int]$frameDataSize) | Out-Null }
                    } catch { break }
                    $elemCount++; continue
                }

                $outWriter.Write($rawHeader, 0, $rawHeader.Length)
                $remaining = $srsSize - $srsFs.Position
                $bytesToRead = [Math]::Min([uint64]$elemSize, [uint64]$remaining)
                if ($bytesToRead -gt 0 -and $bytesToRead -le $remaining) {
                    $chunkSize = 1MB; $bytesLeft = $bytesToRead
                    while ($bytesLeft -gt 0) { $toRead = [Math]::Min($chunkSize, $bytesLeft); $chunk = $srsReader.ReadBytes([int]$toRead); if ($chunk.Length -eq 0) { break }; $outWriter.Write($chunk, 0, $chunk.Length); $bytesLeft -= $chunk.Length }
                }
                $elemCount++
            }

            $outWriter.Flush()
            Write-Verbose "Rebuilt complete: $elemCount elements, $blockCount blocks, $clusterCount clusters"
            return $true
        }
        finally {
            foreach ($stream in $trackDataStreams.Values) { if ($null -ne $stream) { $stream.Dispose() } }
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
