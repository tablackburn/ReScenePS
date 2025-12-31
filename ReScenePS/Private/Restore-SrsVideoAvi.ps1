function Restore-SrsVideoAvi {
    <#
    .SYNOPSIS
        Internal function to reconstruct an AVI sample from SRS and source.

    .DESCRIPTION
        Handles the AVI-specific reconstruction workflow:
        1. Reads and parses SRS data
        2. Calls Build-SampleAviFromSrs with source file

    .PARAMETER SrsFilePath
        Path to the SRS file.

    .PARAMETER SourcePath
        Path to the source AVI file.

    .PARAMETER OutputPath
        Path for the output sample AVI.

    .OUTPUTS
        System.Boolean
        Returns $true if reconstruction was successful.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$SrsFilePath,

        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    try {
        Write-Verbose "Reading SRS file: $SrsFilePath"
        $srsData = [System.IO.File]::ReadAllBytes($SrsFilePath)

        Write-Verbose "Reconstructing AVI sample..."
        $result = Build-SampleAviFromSrs `
            -SrsData $srsData `
            -SourcePath $SourcePath `
            -OutputPath $OutputPath

        if ($result) {
            Write-Host "  [OK] Reconstructed video sample: $(Split-Path $OutputPath -Leaf)" -ForegroundColor Green

            # Verify output exists and has reasonable size
            if (Test-Path $OutputPath) {
                $outputSize = (Get-Item $OutputPath).Length
                Write-Verbose "Output file size: $outputSize bytes"
            }

            return $true
        }

        return $false
    }
    catch {
        Write-Warning "Failed to reconstruct AVI video sample: $_"
        return $false
    }
}
