function ConvertFrom-SrsAviFile {
    <#
    .SYNOPSIS
    Parses an AVI SRS file and extracts metadata and track information.

    .DESCRIPTION
    AVI SRS files are RIFF containers with embedded SRSF (File) and SRST (Track)
    chunks that store metadata about the original sample file for reconstruction.

    .PARAMETER FilePath
    Path to the AVI SRS file

    .PARAMETER Data
    Raw bytes of the AVI SRS data (alternative to FilePath)

    .OUTPUTS
    [PSCustomObject] containing FileMetadata, Tracks, RawBytes, and parsed RIFF structure
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$FilePath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Data')]
        [byte[]]$Data
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path $FilePath)) {
            throw "SRS file not found: $FilePath"
        }
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    }
    else {
        $bytes = $Data
    }

    Write-Verbose "Parsing AVI SRS: $($bytes.Length) bytes"

    $ms = [System.IO.MemoryStream]::new($bytes)
    $reader = [System.IO.BinaryReader]::new($ms)

    try {
        # Read RIFF header
        $riffMagic = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
        if ($riffMagic -ne 'RIFF') {
            throw "Invalid RIFF magic: expected 'RIFF', got '$riffMagic'"
        }

        $riffSize = $reader.ReadUInt32()
        $riffType = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))

        Write-Verbose "RIFF header: size=$riffSize, type=$riffType"

        $fileMetadata = $null
        $tracks = @{}
        $moviPosition = -1
        $moviSize = 0

        # Parse chunks until we find movi LIST
        while ($ms.Position -lt $bytes.Length - 8) {
            $chunkPos = $ms.Position
            $chunkId = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
            $chunkSize = $reader.ReadUInt32()

            Write-Verbose "Chunk at $chunkPos : '$chunkId' ($chunkSize bytes)"

            if ($chunkId -eq 'LIST') {
                $listType = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
                Write-Verbose "  LIST type: $listType"

                if ($listType -eq 'movi') {
                    $moviPosition = $chunkPos
                    $moviSize = $chunkSize

                    # Parse movi contents for SRSF and SRST chunks
                    $moviEnd = [Math]::Min($chunkPos + 8 + $chunkSize, $bytes.Length)

                    while ($ms.Position -lt $moviEnd - 8) {
                        $subPos = $ms.Position
                        $subId = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
                        $subSize = $reader.ReadUInt32()

                        Write-Verbose "  SubChunk at $subPos : '$subId' ($subSize bytes)"

                        if ($subId -eq 'SRSF') {
                            # Parse File metadata
                            $srsData = $reader.ReadBytes($subSize)
                            $fileMetadata = ConvertFrom-SrsAviFileData -Data $srsData
                        }
                        elseif ($subId -eq 'SRST') {
                            # Parse Track metadata
                            $trackData = $reader.ReadBytes($subSize)
                            $track = ConvertFrom-SrsAviTrackData -Data $trackData
                            $tracks[$track.TrackNumber] = $track
                        }
                        else {
                            # Skip other chunks (original AVI index data, etc.)
                            $bytesToSkip = [Math]::Min($subSize, $moviEnd - $ms.Position)
                            if ($bytesToSkip -gt 0) {
                                $ms.Seek($bytesToSkip, [System.IO.SeekOrigin]::Current) | Out-Null
                            }
                        }

                        # Word align
                        if ($ms.Position % 2 -eq 1 -and $ms.Position -lt $moviEnd) {
                            $ms.Seek(1, [System.IO.SeekOrigin]::Current) | Out-Null
                        }
                    }

                    # Stop after movi - we have all we need
                    break
                }
                else {
                    # Skip other LIST contents
                    $skipSize = $chunkSize - 4
                    if ($skipSize -gt 0) {
                        $ms.Seek($skipSize, [System.IO.SeekOrigin]::Current) | Out-Null
                    }
                }
            }
            else {
                # Skip non-LIST chunks
                $ms.Seek($chunkSize, [System.IO.SeekOrigin]::Current) | Out-Null
            }

            # Word align
            if ($ms.Position % 2 -eq 1) {
                $ms.Seek(1, [System.IO.SeekOrigin]::Current) | Out-Null
            }
        }

        return [PSCustomObject]@{
            FileMetadata  = $fileMetadata
            Tracks        = $tracks
            RawBytes      = $bytes
            MoviPosition  = $moviPosition
            MoviSize      = $moviSize
            DeclaredSize  = $riffSize
            ContainerType = $riffType
        }
    }
    finally {
        $reader.Dispose()
        $ms.Dispose()
    }
}

function ConvertFrom-SrsAviFileData {
    <#
    .SYNOPSIS
    Parses SRSF chunk data containing file metadata.

    .DESCRIPTION
    SRSF structure:
    - 2 bytes: flags
    - 2 bytes: app_name_length
    - Variable: app_name (UTF-8)
    - 2 bytes: file_name_length
    - Variable: file_name (UTF-8)
    - 8 bytes: file_size (UInt64 LE)
    - 4 bytes: crc32 (UInt32 LE)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Data
    )

    $ms = [System.IO.MemoryStream]::new($Data)
    $reader = [System.IO.BinaryReader]::new($ms)

    try {
        $flags = $reader.ReadUInt16()
        $appNameLength = $reader.ReadUInt16()
        $appName = if ($appNameLength -gt 0) {
            [System.Text.Encoding]::UTF8.GetString($reader.ReadBytes($appNameLength))
        }
        else { "" }

        $fileNameLength = $reader.ReadUInt16()
        $fileName = if ($fileNameLength -gt 0) {
            [System.Text.Encoding]::UTF8.GetString($reader.ReadBytes($fileNameLength))
        }
        else { "" }

        $fileSize = $reader.ReadUInt64()
        $crc32 = $reader.ReadUInt32()

        return [PSCustomObject]@{
            Flags       = $flags
            Application = $appName
            FileName    = $fileName
            FileSize    = $fileSize
            Crc32       = $crc32
        }
    }
    finally {
        $reader.Dispose()
        $ms.Dispose()
    }
}

function ConvertFrom-SrsAviTrackData {
    <#
    .SYNOPSIS
    Parses SRST chunk data containing track metadata.

    .DESCRIPTION
    SRST structure:
    - 2 bytes: flags (BIG_FILE=0x4, BIG_TRACK_NUMBER=0x8)
    - 2 or 4 bytes: track_number (4 if BIG_TRACK_NUMBER flag set)
    - 4 or 8 bytes: data_length (8 if BIG_FILE flag set)
    - 8 bytes: match_offset (UInt64 LE)
    - 2 bytes: signature_length
    - Variable: signature_bytes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Data
    )

    $BIG_FILE = 0x4
    $BIG_TRACK_NUMBER = 0x8

    $ms = [System.IO.MemoryStream]::new($Data)
    $reader = [System.IO.BinaryReader]::new($ms)

    try {
        $flags = $reader.ReadUInt16()

        # Track number: 2 or 4 bytes based on BIG_TRACK_NUMBER flag
        $trackNumber = if ($flags -band $BIG_TRACK_NUMBER) {
            $reader.ReadUInt32()
        }
        else {
            $reader.ReadUInt16()
        }

        # Data length: 4 or 8 bytes based on BIG_FILE flag
        $dataLength = if ($flags -band $BIG_FILE) {
            $reader.ReadUInt64()
        }
        else {
            [UInt64]$reader.ReadUInt32()
        }

        # Match offset: always 8 bytes
        $matchOffset = $reader.ReadUInt64()

        # Signature bytes
        $signatureLength = $reader.ReadUInt16()
        $signatureBytes = if ($signatureLength -gt 0 -and $ms.Position + $signatureLength -le $Data.Length) {
            $reader.ReadBytes($signatureLength)
        }
        else {
            @()
        }

        return [PSCustomObject]@{
            Flags          = $flags
            TrackNumber    = $trackNumber
            DataLength     = $dataLength
            MatchOffset    = $matchOffset
            SignatureBytes = $signatureBytes
        }
    }
    finally {
        $reader.Dispose()
        $ms.Dispose()
    }
}
