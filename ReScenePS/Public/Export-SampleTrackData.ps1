function Export-SampleTrackData {
    <#
    .SYNOPSIS
        Extract sample track data from main file using match_offset and data_length.

    .DESCRIPTION
        Reads data from a source file starting at the specified offset and
        writes the specified number of bytes to an output file. This is used
        for extracting track data when reconstructing video samples.

        NOTE: This is a legacy function - use Export-MkvTrackData for MKV files.

    .PARAMETER MainFilePath
        Path to the main file to extract data from.

    .PARAMETER MatchOffset
        Byte offset in the source file to start reading from.

    .PARAMETER DataLength
        Number of bytes to extract.

    .PARAMETER OutputPath
        Path where the extracted data will be written.

    .PARAMETER SignatureBytes
        Optional signature bytes for validation.

    .EXAMPLE
        Export-SampleTrackData -MainFilePath "movie.mkv" -MatchOffset 12345678 -DataLength 5000000 -OutputPath "track1.dat"

        Extracts 5MB of track data starting at the specified offset from the source MKV file.

    .OUTPUTS
        System.Boolean
        Returns $true if extraction was successful.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
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
    # SignatureBytes reserved for future validation (suppress PSReviewUnusedParameter)
    $null = $SignatureBytes

    if (-not (Test-Path $MainFilePath)) {
        throw "Main file not found: $MainFilePath"
    }

    try {
        $fs = [System.IO.File]::OpenRead($MainFilePath)
        $br = [System.IO.BinaryReader]::new($fs)

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
