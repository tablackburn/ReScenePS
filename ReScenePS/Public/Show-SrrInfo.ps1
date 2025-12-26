function Show-SrrInfo {
    <#
    .SYNOPSIS
        Display information about an SRR file.

    .DESCRIPTION
        Parses an SRR file and displays summary information including:
        - Creating application name
        - Stored files (NFO, SFV, etc.) with sizes
        - RAR volume names
        - Block type summary with counts

    .PARAMETER SrrFile
        Path to the SRR file to analyze.

    .EXAMPLE
        Show-SrrInfo -SrrFile "release.srr"

        Displays formatted information about the SRR file contents.

    .OUTPUTS
        None. Writes formatted output to the console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$SrrFile
    )

    Write-Host "Parsing SRR file: $SrrFile" -ForegroundColor Cyan
    Write-Host ""

    $blocks = Get-SrrBlock -SrrFile $SrrFile

    Write-Host "Total blocks: $($blocks.Count)" -ForegroundColor Green
    Write-Host ""

    # Show SRR header info
    $header = $blocks | Where-Object { $_.HeadType -eq 0x69 } | Select-Object -First 1
    if ($header -and $header.AppName) {
        Write-Host "Creating Application:" -ForegroundColor Yellow
        Write-Host "  $($header.AppName)"
        Write-Host ""
    }

    # Show stored files
    $storedFiles = $blocks | Where-Object { $_.HeadType -eq 0x6A }
    if ($storedFiles.Count -gt 0) {
        Write-Host "Stored files:" -ForegroundColor Yellow
        foreach ($file in $storedFiles) {
            Write-Host ("  {0,12:N0}  {1}" -f $file.FileSize, $file.FileName)
        }
        Write-Host ""
    }

    # Show RAR volumes
    $rarFiles = $blocks | Where-Object { $_.HeadType -eq 0x71 }
    if ($rarFiles.Count -gt 0) {
        Write-Host "RAR files:" -ForegroundColor Yellow
        foreach ($rar in $rarFiles) {
            Write-Host "  $($rar.FileName)"
        }
        Write-Host ""
    }

    # Block type summary
    Write-Host "Block type summary:" -ForegroundColor Yellow
    $blocks | Group-Object HeadType | Sort-Object Name | ForEach-Object {
        $typeName = if ($script:BlockTypeNames.ContainsKey([int]$_.Name)) {
            $script:BlockTypeNames[[int]$_.Name]
        } else {
            "Unknown"
        }
        Write-Host ("  0x{0:X2} {1,-30} {2,3} blocks" -f [int]$_.Name, $typeName, $_.Count)
    }
}
