function Test-ReconstructedRar {
    <#
    .SYNOPSIS
    Validate reconstructed RAR files against SFV CRCs.

    .PARAMETER SrrFile
    Path to the SRR file (to extract SFV).

    .PARAMETER OutputPath
    Directory containing the reconstructed RAR files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SrrFile,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    Write-Host "Validating reconstructed RAR files..." -ForegroundColor Cyan

    $tempSfv = [System.IO.Path]::GetTempFileName() + ".sfv"
    try {
        Write-Host "  Extracting SFV from SRR..." -ForegroundColor Gray
        Export-StoredFile -SrrFile $SrrFile -FileName "*.sfv" -OutputPath $tempSfv -ErrorAction SilentlyContinue

        if (-not (Test-Path $tempSfv)) {
            Write-Warning "SFV file not found in SRR, skipping CRC validation"
            return
        }

        $sfvData = ConvertFrom-SfvFile -FilePath $tempSfv
        Write-Host "  Found $($sfvData.Count) entries in SFV" -ForegroundColor Green

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
            $actualCrc = (CRC\Get-CRC32 -Path $rarPath).Hash
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
