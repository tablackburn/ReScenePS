function Restore-Release {
    <#
    .SYNOPSIS
        Scans directories for releases, downloads required files from srrDB, and rebuilds with original names.

    .DESCRIPTION
        This is the main automation command for ReScenePS. It performs:
        - Detection of release names from directory names
        - Querying srrDB for release metadata
        - Downloading SRR files and any additional files (proofs, etc.) not stored in the SRR
        - Calling Invoke-SrrRestore to rebuild the release with original names and structure

        Requires the SrrDBAutomationToolkit module for srrDB API access.

    .PARAMETER Path
        Directory to scan for releases. Defaults to current directory.
        In single mode (default), treats this directory as the release.
        With -Recurse, treats each subdirectory as a separate release.

    .PARAMETER Recurse
        Process each subdirectory as a separate release instead of the root directory.

    .PARAMETER SourcePath
        Directory containing source files for reconstruction. Defaults to the release directory.
        Can be set to a different location if source files are stored separately.

    .PARAMETER KeepSrr
        Keep the SRR file after successful restoration.

    .PARAMETER KeepSources
        Keep source files (e.g., .mkv) after successful restoration.

    .PARAMETER SkipValidation
        Skip CRC validation against embedded SFV.

    .EXAMPLE
        Restore-Release

        Scans current directory, downloads SRR from srrDB, and rebuilds the release.

    .EXAMPLE
        Restore-Release -Path "D:\Downloads\Movie.2024.1080p.BluRay-GROUP"

        Processes a specific release directory.

    .EXAMPLE
        Restore-Release -Path "D:\Downloads" -Recurse

        Processes all subdirectories as separate releases.

    .EXAMPLE
        Restore-Release -KeepSrr -KeepSources -WhatIf

        Preview what would happen without making changes.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0)]
        [ValidateScript({
            if (-not (Test-Path -Path $_ -PathType Container)) {
                throw "Directory does not exist: $_"
            }
            $true
        })]
        [string]$Path = ".",

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [string]$SourcePath,

        [Parameter()]
        [switch]$KeepSrr,

        [Parameter()]
        [switch]$KeepSources,

        [Parameter()]
        [switch]$SkipValidation
    )

    begin {
        # Resolve path
        $Path = (Resolve-Path -Path $Path).Path

        # Track results for summary
        $script:results = @{
            Processed = 0
            Succeeded = 0
            Failed    = 0
            Skipped   = 0
            Details   = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
    }

    process {
        Write-Host ""
        Write-Host "===========================================================" -ForegroundColor Cyan
        Write-Host "              Restore-Release Automation" -ForegroundColor Cyan
        Write-Host "===========================================================" -ForegroundColor Cyan
        Write-Host ""

        # Determine directories to process
        $releaseDirs = @()

        if ($Recurse) {
            $releaseDirs = Get-ChildItem -Path $Path -Directory | Select-Object -ExpandProperty FullName
            Write-Host "Scanning for releases in: $Path" -ForegroundColor Yellow
            Write-Host "Found $($releaseDirs.Count) subdirectories to process" -ForegroundColor Gray
        }
        else {
            $releaseDirs = @($Path)
        }

        if ($releaseDirs.Count -eq 0) {
            Write-Warning "No directories found to process"
            return
        }

        Write-Host ""

        foreach ($releaseDir in $releaseDirs) {
            $script:results.Processed++
            $releaseName = Split-Path -Path $releaseDir -Leaf

            Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray
            Write-Host "Processing: $releaseName" -ForegroundColor Cyan
            Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray

            try {
                # Step 1: Check if SRR already exists locally
                $existingSrr = Get-ChildItem -Path $releaseDir -Filter "*.srr" -File -ErrorAction SilentlyContinue | Select-Object -First 1

                if ($existingSrr) {
                    Write-Host "  [INFO] SRR already exists: $($existingSrr.Name)" -ForegroundColor Yellow
                    $srrPath = $existingSrr.FullName
                }
                else {
                    # Step 2: Use Get-SatReleaseFile to download SRR and additional files
                    Write-Host "  [1] Downloading release files from srrDB..." -ForegroundColor Yellow

                    if ($PSCmdlet.ShouldProcess($releaseName, "Download release files from srrDB")) {
                        $downloadResult = Get-SatReleaseFile -ReleaseName $releaseName -OutPath $releaseDir -PassThru -ErrorAction Stop
                        $srrPath = $downloadResult.SrrFile.FullName
                        Write-Host "  [OK] Downloaded: $($downloadResult.SrrFile.Name)" -ForegroundColor Green

                        if ($downloadResult.AdditionalFiles.Count -gt 0) {
                            foreach ($file in $downloadResult.AdditionalFiles) {
                                Write-Host "  [OK] Downloaded: $($file.Name)" -ForegroundColor Green
                            }
                        }
                    }
                    else {
                        Write-Host "  [SKIP] Download (WhatIf)" -ForegroundColor Gray
                        $script:results.Skipped++
                        $script:results.Details.Add([PSCustomObject]@{
                            Release = $releaseName
                            Status  = 'Skipped'
                            Reason  = 'WhatIf mode'
                        })
                        continue
                    }
                }

                # Step 3: Run the restoration
                Write-Host "  [2] Running SRR restoration..." -ForegroundColor Yellow

                $restoreParams = @{
                    SrrFile    = $srrPath
                    SourcePath = if ($SourcePath) { $SourcePath } else { $releaseDir }
                    OutputPath = $releaseDir
                }

                if ($KeepSrr) { $restoreParams['KeepSrr'] = $true }
                if ($KeepSources) { $restoreParams['KeepSources'] = $true }
                if ($SkipValidation) { $restoreParams['SkipValidation'] = $true }

                Invoke-SrrRestore @restoreParams

                $script:results.Succeeded++
                $script:results.Details.Add([PSCustomObject]@{
                    Release = $releaseName
                    Status  = 'Succeeded'
                    Reason  = $null
                })
            }
            catch {
                Write-Host "  [X] Failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:results.Failed++
                $script:results.Details.Add([PSCustomObject]@{
                    Release = $releaseName
                    Status  = 'Failed'
                    Reason  = $_.Exception.Message
                })

                if (-not $Recurse) {
                    throw
                }
            }

            Write-Host ""
        }
    }

    end {
        # Summary
        Write-Host "===========================================================" -ForegroundColor Cyan
        Write-Host "                      Summary" -ForegroundColor Cyan
        Write-Host "===========================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Processed: $($script:results.Processed)" -ForegroundColor Gray
        Write-Host "  Succeeded: $($script:results.Succeeded)" -ForegroundColor Green
        Write-Host "  Failed:    $($script:results.Failed)" -ForegroundColor $(if ($script:results.Failed -gt 0) { 'Red' } else { 'Gray' })
        Write-Host "  Skipped:   $($script:results.Skipped)" -ForegroundColor $(if ($script:results.Skipped -gt 0) { 'Yellow' } else { 'Gray' })
        Write-Host ""

        if ($script:results.Failed -gt 0 -or $script:results.Skipped -gt 0) {
            Write-Host "Details:" -ForegroundColor Gray
            foreach ($detail in $script:results.Details | Where-Object { $_.Status -ne 'Succeeded' }) {
                $color = if ($detail.Status -eq 'Failed') { 'Red' } else { 'Yellow' }
                Write-Host "  - $($detail.Release): $($detail.Status) - $($detail.Reason)" -ForegroundColor $color
            }
            Write-Host ""
        }

        # Return results object for pipeline usage
        [PSCustomObject]@{
            Processed = $script:results.Processed
            Succeeded = $script:results.Succeeded
            Failed    = $script:results.Failed
            Skipped   = $script:results.Skipped
            Details   = $script:results.Details
        }
    }
}
