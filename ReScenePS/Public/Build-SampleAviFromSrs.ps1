[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Srs is an acronym (Sample ReScene), not a plural')]
function Build-SampleAviFromSrs {
    <#
    .SYNOPSIS
        Reconstructs an AVI sample file from an SRS file and source video.

    .DESCRIPTION
        AVI SRS files store the structure of the original sample (frame headers
        and their sizes) without the actual frame data. This function:
        1. Parses the SRS to get track metadata (match offsets in source)
        2. Parses the source AVI movi structure to find matching chunks
        3. Copies AVI structure from SRS and injects frame data from source

    .PARAMETER SrsData
        Raw bytes of the SRS file.

    .PARAMETER SourcePath
        Path to the source AVI file containing the full movie.

    .PARAMETER OutputPath
        Path for the reconstructed sample AVI file.

    .EXAMPLE
        Build-SampleAviFromSrs -SrsData $srsBytes -SourcePath "movie.avi" -OutputPath "sample.avi"

        Reconstructs the AVI sample file from the SRS metadata and source video.

    .OUTPUTS
        System.Boolean
        Returns $true if reconstruction was successful.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [byte[]]$SrsData,

        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    if (-not (Test-Path $SourcePath)) {
        throw "Source file not found: $SourcePath"
    }

    # Parse SRS metadata
    $srsInfo = ConvertFrom-SrsAviFile -Data $SrsData
    if (-not $srsInfo.FileMetadata) {
        throw "Failed to parse SRS metadata"
    }

    Write-Verbose "SRS Info: $($srsInfo.FileMetadata.FileName), expected size: $($srsInfo.FileMetadata.FileSize)"
    Write-Verbose "Tracks: $($srsInfo.Tracks.Count)"
    foreach ($trackNum in $srsInfo.Tracks.Keys | Sort-Object) {
        $track = $srsInfo.Tracks[$trackNum]
        Write-Verbose "  Track $trackNum : $($track.DataLength) bytes at offset $($track.MatchOffset)"
    }

    # Parse source AVI to build an index of movi chunks
    Write-Verbose "Parsing source AVI movi structure..."
    $sourceChunks = Get-AviMoviChunks -FilePath $SourcePath

    # Find the minimum match offset to determine where the sample region starts
    $minMatchOffset = [long]::MaxValue
    foreach ($trackNum in $srsInfo.Tracks.Keys) {
        $track = $srsInfo.Tracks[$trackNum]
        if ($track.MatchOffset -lt $minMatchOffset) {
            $minMatchOffset = $track.MatchOffset
        }
    }

    # Get all chunks for each track starting from the sample region
    # Don't limit by dataLength - interleaving means the range is much larger
    $trackChunks = @{}
    foreach ($trackNum in $srsInfo.Tracks.Keys) {
        $track = $srsInfo.Tracks[$trackNum]
        $matchOffset = $track.MatchOffset
        $dataLength = $track.DataLength

        # Find the first chunk that contains or starts at the match offset
        $startChunk = $sourceChunks | Where-Object {
            $_.StreamNum -eq $trackNum -and
            $_.DataOffset -le $matchOffset -and
            ($_.DataOffset + $_.Size) -gt $matchOffset
        } | Select-Object -First 1

        if (-not $startChunk) {
            # Match offset is exactly at start of a chunk
            $startChunk = $sourceChunks | Where-Object {
                $_.StreamNum -eq $trackNum -and $_.DataOffset -ge $matchOffset
            } | Sort-Object DataOffset | Select-Object -First 1
        }

        # Get all chunks for this track starting from the start chunk
        $startOffset = if ($startChunk) { $startChunk.DataOffset } else { $matchOffset }
        $chunks = $sourceChunks | Where-Object {
            $_.StreamNum -eq $trackNum -and $_.DataOffset -ge $startOffset
        } | Sort-Object DataOffset

        # Calculate initial skip (if match_offset is inside first chunk)
        $initialSkip = [long]0
        if ($startChunk -and $matchOffset -gt $startChunk.DataOffset) {
            $initialSkip = $matchOffset - $startChunk.DataOffset
        }

        $trackChunks[$trackNum] = @{
            StartOffset = $matchOffset
            DataLength = $dataLength
            Chunks = @($chunks)
            InitialSkip = $initialSkip
        }

        Write-Verbose "  Track $trackNum : found $($chunks.Count) chunks in source (initialSkip=$initialSkip)"
    }

    # Open source file
    $sourceFs = [System.IO.File]::OpenRead($SourcePath)
    $sourceReader = [System.IO.BinaryReader]::new($sourceFs)

    # Create output file
    $outFs = [System.IO.File]::Create($OutputPath)
    $outWriter = [System.IO.BinaryWriter]::new($outFs)

    try {
        $ms = [System.IO.MemoryStream]::new($SrsData)
        $reader = [System.IO.BinaryReader]::new($ms)

        # Track how much data we've read from each track
        # Use [int] keys consistently to avoid type mismatch in lookups
        $trackBytesRead = @{}
        foreach ($trackNum in $srsInfo.Tracks.Keys) {
            $trackBytesRead[[int]$trackNum] = [long]0
        }

        # Build a lookup for source chunks by track and cumulative offset
        # Account for initialSkip in the first chunk
        # Use [int] keys consistently to avoid type mismatch in lookups
        $trackChunkIndex = @{}
        foreach ($trackNum in $srsInfo.Tracks.Keys) {
            $info = $trackChunks[$trackNum]
            $intTrackNum = [int]$trackNum
            $cumulative = [long]0
            $chunkList = [System.Collections.ArrayList]::new()
            $initialSkip = $info.InitialSkip
            $isFirst = $true

            foreach ($chunk in ($info.Chunks | Sort-Object DataOffset)) {
                $chunkUsableStart = 0
                $chunkUsableSize = $chunk.Size

                if ($isFirst -and $initialSkip -gt 0) {
                    # First chunk starts at initialSkip
                    $chunkUsableStart = $initialSkip
                    $chunkUsableSize = $chunk.Size - $initialSkip
                    $isFirst = $false
                }

                if ($chunkUsableSize -gt 0) {
                    [void]$chunkList.Add(@{
                        Chunk = $chunk
                        ChunkDataStart = $chunkUsableStart  # Offset within chunk to start reading
                        CumulativeStart = $cumulative
                        CumulativeEnd = $cumulative + $chunkUsableSize
                    })
                    $cumulative += $chunkUsableSize
                }
            }
            $trackChunkIndex[$intTrackNum] = $chunkList

            # Debug: show first few entries
            if ($chunkList.Count -gt 0) {
                $first = $chunkList[0]
                Write-Verbose "    First entry: Chunk at $($first.Chunk.DataOffset), ChunkDataStart=$($first.ChunkDataStart), Cumulative=[$($first.CumulativeStart),$($first.CumulativeEnd)]"
            }
        }

        # Copy RIFF header (12 bytes: "RIFF" + size + "AVI ")
        $outWriter.Write($reader.ReadBytes(12))
        Write-Verbose "Wrote RIFF header"

        # Process chunks until movi
        while ($ms.Position -lt $SrsData.Length - 8) {
            $chunkId = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
            $chunkSize = $reader.ReadUInt32()

            if ($chunkId -eq 'LIST') {
                $listType = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))

                if ($listType -eq 'movi') {
                    # Write movi LIST header with original declared size
                    $outWriter.Write([byte[]]@(0x4C, 0x49, 0x53, 0x54)) # "LIST"
                    $outWriter.Write([BitConverter]::GetBytes($chunkSize))
                    $outWriter.Write([byte[]]@(0x6D, 0x6F, 0x76, 0x69)) # "movi"

                    Write-Verbose "Writing movi LIST (declared size: $chunkSize)"

                    # Skip SRSF and SRST chunks to find frame index
                    while ($ms.Position -lt $SrsData.Length - 8) {
                        $subId = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
                        $subSize = $reader.ReadUInt32()

                        if ($subId -eq 'SRSF' -or $subId -eq 'SRST') {
                            # Skip ReSample metadata chunks
                            $ms.Seek($subSize, [System.IO.SeekOrigin]::Current) | Out-Null
                            if ($ms.Position % 2 -eq 1) {
                                $ms.Seek(1, [System.IO.SeekOrigin]::Current) | Out-Null
                            }
                            continue
                        }

                        # Seek back to read the first frame header
                        $ms.Seek(-8, [System.IO.SeekOrigin]::Current) | Out-Null

                        # Process frame headers (8 bytes each: FOURCC + size)
                        $frameCount = 0
                        while ($ms.Position -lt $SrsData.Length - 8) {
                            # Check for padding or end
                            $peekByte = $SrsData[$ms.Position]
                            if ($peekByte -eq 0) {
                                $ms.Seek(1, [System.IO.SeekOrigin]::Current) | Out-Null
                                continue
                            }

                            $frameId = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
                            $frameSize = $reader.ReadUInt32()

                            if ($frameId -eq 'idx1') {
                                $ms.Seek(-8, [System.IO.SeekOrigin]::Current) | Out-Null
                                break
                            }

                            if ($frameId -notmatch '^(\d\d)(d[cb]|wb)$') {
                                Write-Verbose "Unknown frame type '$frameId' at position $($ms.Position - 8), stopping"
                                break
                            }

                            $streamNum = [int]$Matches[1]

                            # Write chunk header to output
                            $outWriter.Write([System.Text.Encoding]::ASCII.GetBytes($frameId))
                            $outWriter.Write([BitConverter]::GetBytes([uint32]$frameSize))

                            # Find the source chunk containing this frame's data
                            if ($frameSize -gt 0 -and $trackChunkIndex.ContainsKey($streamNum)) {
                                $currentOffset = $trackBytesRead[$streamNum]
                                $targetEnd = $currentOffset + $frameSize

                                # Find chunks that contain this data range
                                $bytesWritten = 0
                                foreach ($entry in $trackChunkIndex[$streamNum]) {
                                    if ($entry.CumulativeEnd -le $currentOffset) { continue }
                                    if ($entry.CumulativeStart -ge $targetEnd) { break }

                                    $chunk = $entry.Chunk
                                    $chunkBaseOffset = $entry.ChunkDataStart  # Offset within chunk where usable data starts

                                    # Calculate how much to read from this chunk
                                    # offsetInEntry = position within this chunk entry's usable range
                                    $offsetInEntry = [Math]::Max(0, $currentOffset - $entry.CumulativeStart)
                                    $entryUsableSize = $entry.CumulativeEnd - $entry.CumulativeStart
                                    $endInEntry = [Math]::Min($entryUsableSize, $targetEnd - $entry.CumulativeStart)
                                    $bytesToRead = $endInEntry - $offsetInEntry

                                    if ($bytesToRead -gt 0) {
                                        # File position = chunk's data offset + base offset (for first chunk skip) + position in entry
                                        $filePos = $chunk.DataOffset + $chunkBaseOffset + $offsetInEntry
                                        $sourceFs.Seek($filePos, [System.IO.SeekOrigin]::Begin) | Out-Null
                                        $data = $sourceReader.ReadBytes([int]$bytesToRead)
                                        $outWriter.Write($data)
                                        $bytesWritten += $data.Length
                                    }
                                }

                                if ($bytesWritten -lt $frameSize) {
                                    # Pad with zeros if we couldn't find all data
                                    $zeros = New-Object byte[] ($frameSize - $bytesWritten)
                                    $outWriter.Write($zeros)
                                }

                                $trackBytesRead[$streamNum] = $targetEnd
                            }
                            elseif ($frameSize -gt 0) {
                                $zeros = New-Object byte[] $frameSize
                                $outWriter.Write($zeros)
                            }

                            # Word alignment padding in output
                            if ($frameSize % 2 -eq 1) {
                                $outWriter.Write([byte]0)
                            }

                            $frameCount++
                        }

                        Write-Verbose "Processed $frameCount frames"
                        break
                    }

                    # Find and copy idx1 chunk and trailing chunks
                    for ($i = [int]$ms.Position; $i -lt $SrsData.Length - 4; $i++) {
                        if ($SrsData[$i] -eq 0x69 -and $SrsData[$i + 1] -eq 0x64 -and
                            $SrsData[$i + 2] -eq 0x78 -and $SrsData[$i + 3] -eq 0x31) {
                            $ms.Seek($i, [System.IO.SeekOrigin]::Begin) | Out-Null
                            Write-Verbose "Found idx1 at position $i"

                            $idx1Id = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
                            $idx1Size = $reader.ReadUInt32()

                            $outWriter.Write([System.Text.Encoding]::ASCII.GetBytes($idx1Id))
                            $outWriter.Write([BitConverter]::GetBytes($idx1Size))
                            $outWriter.Write($reader.ReadBytes([int]$idx1Size))

                            Write-Verbose "Copied idx1: $idx1Size bytes"

                            # Copy trailing chunks
                            while ($ms.Position -lt $SrsData.Length - 8) {
                                $trailId = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
                                $trailSz = $reader.ReadUInt32()

                                if ($trailId -match '^[A-Za-z0-9 ]{4}$' -and $trailSz -lt 100000) {
                                    $outWriter.Write([System.Text.Encoding]::ASCII.GetBytes($trailId))
                                    $outWriter.Write([BitConverter]::GetBytes($trailSz))
                                    $bytesToRead = [Math]::Min($trailSz, $SrsData.Length - $ms.Position)
                                    if ($bytesToRead -gt 0) {
                                        $outWriter.Write($reader.ReadBytes([int]$bytesToRead))
                                    }
                                    Write-Verbose "Copied trailing chunk '$trailId': $trailSz bytes"
                                }
                                else { break }
                            }
                            break
                        }
                    }

                    break
                }
                else {
                    $outWriter.Write([byte[]]@(0x4C, 0x49, 0x53, 0x54))
                    $outWriter.Write([BitConverter]::GetBytes($chunkSize))
                    $outWriter.Write([System.Text.Encoding]::ASCII.GetBytes($listType))
                    $contentSize = $chunkSize - 4
                    $outWriter.Write($reader.ReadBytes([int]$contentSize))
                    Write-Verbose "Copied LIST '$listType': $chunkSize bytes"
                }
            }
            else {
                $outWriter.Write([System.Text.Encoding]::ASCII.GetBytes($chunkId))
                $outWriter.Write([BitConverter]::GetBytes($chunkSize))
                $outWriter.Write($reader.ReadBytes([int]$chunkSize))
                Write-Verbose "Copied chunk '$chunkId': $chunkSize bytes"
            }

            if ($ms.Position % 2 -eq 1) {
                $ms.Seek(1, [System.IO.SeekOrigin]::Current) | Out-Null
            }
        }

        $outWriter.Flush()
        Write-Verbose "Reconstruction complete: $($outFs.Length) bytes"
        Write-Verbose "Expected size: $($srsInfo.FileMetadata.FileSize) bytes"

        $reader.Dispose()
        $ms.Dispose()

        return $true
    }
    catch {
        throw "Failed to rebuild sample: $_"
    }
    finally {
        if ($null -ne $outWriter) { $outWriter.Dispose() }
        if ($null -ne $outFs) { $outFs.Dispose() }
        if ($null -ne $sourceReader) { $sourceReader.Dispose() }
        if ($null -ne $sourceFs) { $sourceFs.Dispose() }
    }
}

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Chunks is an AVI file format term')]
function Get-AviMoviChunks {
    <#
    .SYNOPSIS
        Parses an AVI file and returns all movi chunks with their positions.

    .OUTPUTS
        System.Collections.ArrayList
        List of chunk objects with Id, Size, and Position properties.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.ArrayList])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $chunks = [System.Collections.ArrayList]::new()

    $fs = [System.IO.File]::OpenRead($FilePath)
    $reader = [System.IO.BinaryReader]::new($fs)

    try {
        # Skip RIFF header
        $fs.Seek(12, [System.IO.SeekOrigin]::Begin) | Out-Null

        # Find movi LIST
        while ($fs.Position -lt $fs.Length - 12) {
            $chunkPos = $fs.Position
            $chunkId = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
            $chunkSize = $reader.ReadUInt32()

            if ($chunkId -eq 'LIST') {
                $listType = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))

                if ($listType -eq 'movi') {
                    # Parse movi chunks
                    $moviEnd = $chunkPos + 8 + $chunkSize

                    while ($fs.Position -lt $moviEnd - 8) {
                        $subPos = $fs.Position
                        $subId = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
                        $subSize = $reader.ReadUInt32()
                        $dataPos = $fs.Position

                        if ($subId -match '^(\d\d)(d[cb]|wb)$') {
                            $streamNum = [int]$Matches[1]
                            [void]$chunks.Add([PSCustomObject]@{
                                FourCC = $subId
                                StreamNum = $streamNum
                                ChunkOffset = $subPos
                                DataOffset = $dataPos
                                Size = $subSize
                            })
                        }

                        # Skip chunk data
                        $fs.Seek($subSize, [System.IO.SeekOrigin]::Current) | Out-Null
                        if ($fs.Position % 2 -eq 1) {
                            $fs.Seek(1, [System.IO.SeekOrigin]::Current) | Out-Null
                        }
                    }

                    break
                }
                else {
                    $fs.Seek($chunkSize - 4, [System.IO.SeekOrigin]::Current) | Out-Null
                }
            }
            else {
                $fs.Seek($chunkSize, [System.IO.SeekOrigin]::Current) | Out-Null
            }

            if ($fs.Position % 2 -eq 1) {
                $fs.Seek(1, [System.IO.SeekOrigin]::Current) | Out-Null
            }
        }
    }
    finally {
        $reader.Dispose()
        $fs.Dispose()
    }

    return $chunks
}
