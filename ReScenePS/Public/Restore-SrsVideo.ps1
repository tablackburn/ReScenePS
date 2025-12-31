function Restore-SrsVideo {
    <#
    .SYNOPSIS
        Reconstruct a sample video from an SRS file and source video.

    .DESCRIPTION
        High-level function that orchestrates the reconstruction of a video sample from
        an SRS file. Supports both MKV (EBML) and AVI (RIFF) formats:

        For MKV samples:
        1. Parses SRS metadata to get track information
        2. Extracts track data from the source MKV file
        3. Rebuilds the sample MKV by combining SRS structure with extracted track data

        For AVI samples:
        1. Parses SRSF/SRST metadata for track offsets
        2. Copies AVI structure from SRS
        3. Injects frame data from source AVI at match offsets

    .PARAMETER SrsFilePath
        Path to the extracted .srs file (EBML or RIFF format).

    .PARAMETER SourcePath
        Path to the source video file (main movie MKV or AVI).

    .PARAMETER OutputPath
        Path for the reconstructed sample video.

    .PARAMETER SourceMkvPath
        Alias for SourcePath for backward compatibility.

    .PARAMETER OutputMkvPath
        Alias for OutputPath for backward compatibility.

    .EXAMPLE
        Restore-SrsVideo -SrsFilePath "sample.srs" -SourcePath "movie.mkv" -OutputPath "sample.mkv"

        Reconstructs the sample MKV video from the SRS metadata and source movie file.

    .EXAMPLE
        Restore-SrsVideo -SrsFilePath "sample.srs" -SourcePath "movie.avi" -OutputPath "sample.avi"

        Reconstructs the sample AVI video from the SRS metadata and source movie file.

    .NOTES
        Uses match_offset from SRS metadata to extract ONLY the sample portion
        from the main file, not the entire file.

    .OUTPUTS
        System.Boolean
        Returns $true if reconstruction was successful, $false otherwise.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Srs is an acronym (Sample ReScene), not a plural')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$SrsFilePath,

        [Parameter(Mandatory)]
        [Alias('SourceMkvPath')]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [Alias('OutputMkvPath')]
        [string]$OutputPath
    )

    if (-not (Test-Path $SrsFilePath)) {
        throw "SRS file not found: $SrsFilePath"
    }

    if (-not (Test-Path $SourcePath)) {
        throw "Source video not found: $SourcePath"
    }

    # Detect SRS type
    $srsInfo = Get-SrsInfo -FilePath $SrsFilePath
    $srsType = $srsInfo.Type

    # Handle AVI/RIFF format
    if ($srsType -match 'RIFF') {
        Write-Verbose "Detected AVI SRS format"
        return Restore-SrsVideoAvi -SrsFilePath $SrsFilePath -SourcePath $SourcePath -OutputPath $OutputPath
    }

    # Handle EBML/MKV format
    if ($srsType -notmatch 'EBML') {
        Write-Warning "SRS type '$srsType' is not supported; skipping video reconstruction"
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
