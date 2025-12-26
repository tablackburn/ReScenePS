function Restore-SrsVideo {
    <#
    .SYNOPSIS
        Reconstruct a sample video from an EBML SRS file and source MKV.

    .DESCRIPTION
        High-level function that orchestrates the reconstruction of a video sample from
        an SRS file. It performs the following steps:
        1. Verifies the SRS file is EBML format (MKV)
        2. Parses SRS metadata to get track information
        3. Extracts track data from the source MKV file
        4. Rebuilds the sample MKV by combining SRS structure with extracted track data

    .PARAMETER SrsFilePath
        Path to the extracted .srs file (EBML format).

    .PARAMETER SourceMkvPath
        Path to the source MKV file (main movie).

    .PARAMETER OutputMkvPath
        Path for the reconstructed sample MKV.

    .EXAMPLE
        Restore-SrsVideo -SrsFilePath "sample.srs" -SourceMkvPath "movie.mkv" -OutputMkvPath "sample.mkv"

    .NOTES
        Uses match_offset from SRS metadata to extract ONLY the sample portion
        from the main file, not the entire file.

    .OUTPUTS
        System.Boolean
        Returns $true if reconstruction was successful, $false otherwise.
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
