function Restore-Release {
    <#
    .SYNOPSIS
        Scans directories for releases, downloads required files from srrDB, and rebuilds with original names.

    .DESCRIPTION
        This is the main automation command for ReScenePS. It performs:
        - Detection of release names from directory names
        - Querying srrDB for release metadata
        - Downloading SRR files and any additional files from srrDB (proof images, samples, etc.
          that are stored separately on srrDB rather than embedded in the SRR file)
        - Calling Invoke-SrrRestore to rebuild the release with original names and structure

        Requires the SrrDBAutomationToolkit module for srrDB API access.

    .PARAMETER Path
        Directory to scan for releases. Defaults to current directory.

        In single mode (default), the function first checks if the specified directory
        contains rebuildable content (video files >= 100MB or .srr files). If so, it
        processes that directory as a release. If not, it automatically scans immediate
        subdirectories for rebuildable releases.

        With -Recurse, treats each subdirectory as a separate release without checking
        if the parent directory itself is rebuildable.

    .PARAMETER Recurse
        Process each subdirectory as a separate release instead of the root directory.

    .PARAMETER Depth
        Maximum depth to search for rebuildable releases when auto-detecting subdirectories.
        Only applies in single mode (without -Recurse) when the specified directory itself
        is not rebuildable. Defaults to 1 (immediate subdirectories only).
        Set to 0 to disable subdirectory scanning, or higher values to search deeper.

    .PARAMETER SourcePath
        Directory containing source files for reconstruction (e.g., .mkv files).
        Defaults to the release directory being processed.
        Use this when source files are stored in a different location than the release folder.

    .PARAMETER KeepSrr
        Keep the SRR file after successful restoration.

    .PARAMETER DeleteSources
        Delete source files (e.g., .mkv) after successful restoration.
        By default, source files are kept.

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
        Restore-Release -KeepSrr -WhatIf

        Preview what would happen without making changes.

    .EXAMPLE
        Restore-Release -DeleteSources

        Restore and delete source files after successful restoration.
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
        [ValidateRange(0, 10)]
        [int]$Depth = 1,

        [Parameter()]
        [ValidateScript({
            if ([string]::IsNullOrWhiteSpace($_)) { return $true }
            if (-not (Test-Path -Path $_ -PathType Container)) {
                throw "SourcePath directory does not exist: $_"
            }
            $true
        })]
        [string]$SourcePath,

        [Parameter()]
        [switch]$KeepSrr,

        [Parameter()]
        [switch]$DeleteSources,

        [Parameter()]
        [switch]$SkipValidation
    )

    begin {
        # Resolve path
        $Path = (Resolve-Path -Path $Path).Path

        # Track results for summary (local variable to avoid accumulation across calls)
        $results = @{
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

        # Determine directories to process (use List for O(n) performance)
        $releaseDirs = [System.Collections.Generic.List[string]]::new()

        if ($Recurse) {
            # Recurse mode: process all subdirectories
            $dirs = @(Get-ChildItem -Path $Path -Directory | Select-Object -ExpandProperty FullName)
            if ($dirs.Count -gt 0) { $releaseDirs.AddRange($dirs) }
            Write-Host "Scanning for releases in: $Path" -ForegroundColor Yellow
            Write-Host "Found $($releaseDirs.Count) subdirectories to process" -ForegroundColor Gray
        }
        else {
            # Single mode: check if current directory is rebuildable
            $isRebuildable = try { Test-RebuildableDirectory -Path $Path -ErrorAction Stop } catch [System.UnauthorizedAccessException] {
                Write-Warning "Access denied checking directory '$Path': $($_.Exception.Message)"
                $false
            } catch [System.IO.IOException] {
                Write-Warning "IO error checking directory '$Path': $($_.Exception.Message)"
                $false
            } catch {
                Write-Warning "Error checking directory '$Path': $($_.Exception.Message)"
                $false
            }

            if ($isRebuildable) {
                $releaseDirs.Add($Path)
            }
            elseif ($Depth -gt 0) {
                # Scan subdirectories for rebuildable content
                Write-Host "Scanning for rebuildable releases in: $Path (depth: $Depth)" -ForegroundColor Yellow
                $foundDirs = @(Get-RebuildableSubdirectory -Path $Path -Depth $Depth)
                if ($foundDirs.Count -gt 0) { $releaseDirs.AddRange($foundDirs) }
                if ($releaseDirs.Count -gt 0) {
                    Write-Host "Found $($releaseDirs.Count) rebuildable release(s)" -ForegroundColor Gray
                }
            }
        }

        if ($releaseDirs.Count -eq 0) {
            Write-Warning "No rebuildable releases found. Ensure the directory contains video files (.mkv, .avi, .mp4) or .srr files."
            return
        }

        Write-Host ""

        foreach ($releaseDir in $releaseDirs) {
            $results.Processed++
            # Get release name from directory, handling edge cases like root dirs or "."
            $resolvedDir = [System.IO.Path]::GetFullPath($releaseDir)
            $releaseName = [System.IO.Path]::GetFileName($resolvedDir)
            if ([string]::IsNullOrEmpty($releaseName)) {
                # Root directory - use drive letter or path
                $releaseName = $resolvedDir.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
            }

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
                        if (-not $downloadResult -or -not $downloadResult.SrrFile -or [string]::IsNullOrWhiteSpace($downloadResult.SrrFile.FullName)) {
                            throw "Get-SatReleaseFile did not return an SRR file for: $releaseName"
                        }
                        $srrPath = $downloadResult.SrrFile.FullName
                        Write-Host "  [OK] Downloaded: $($downloadResult.SrrFile.Name)" -ForegroundColor Green

                        if ($downloadResult.AdditionalFiles -and $downloadResult.AdditionalFiles.Count -gt 0) {
                            foreach ($file in $downloadResult.AdditionalFiles) {
                                Write-Host "  [OK] Downloaded: $($file.Name)" -ForegroundColor Green
                            }
                        }
                    }
                    else {
                        Write-Host "  [SKIP] Download (WhatIf)" -ForegroundColor Gray
                        $results.Skipped++
                        $results.Details.Add([PSCustomObject]@{
                            Release = $releaseName
                            Status  = 'Skipped'
                            Reason  = 'WhatIf mode'
                        })
                        continue
                    }
                }

                # Step 3: Run the restoration
                if ($PSCmdlet.ShouldProcess($releaseName, "Run SRR restoration")) {
                    Write-Host "  [2] Running SRR restoration..." -ForegroundColor Yellow

                    $restoreParams = @{
                        SrrFile    = $srrPath
                        SourcePath = if (-not [string]::IsNullOrWhiteSpace($SourcePath)) { $SourcePath } else { $releaseDir }
                        OutputPath = $releaseDir
                    }

                    if ($KeepSrr) { $restoreParams['KeepSrr'] = $true }
                    if ($DeleteSources) { $restoreParams['DeleteSources'] = $true }
                    if ($SkipValidation) { $restoreParams['SkipValidation'] = $true }

                    Invoke-SrrRestore @restoreParams

                    $results.Succeeded++
                    $results.Details.Add([PSCustomObject]@{
                        Release = $releaseName
                        Status  = 'Succeeded'
                        Reason  = $null
                    })
                }
                else {
                    Write-Host "  [SKIP] Restoration (WhatIf)" -ForegroundColor Gray
                    $results.Skipped++
                    $results.Details.Add([PSCustomObject]@{
                        Release = $releaseName
                        Status  = 'Skipped'
                        Reason  = 'WhatIf mode'
                    })
                }
            }
            catch {
                Write-Host "  [X] Failed: $($_.Exception.Message)" -ForegroundColor Red
                $results.Failed++
                $results.Details.Add([PSCustomObject]@{
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
        Write-Host "  Processed: $($results.Processed)" -ForegroundColor Gray
        Write-Host "  Succeeded: $($results.Succeeded)" -ForegroundColor Green
        Write-Host "  Failed:    $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })
        Write-Host "  Skipped:   $($results.Skipped)" -ForegroundColor $(if ($results.Skipped -gt 0) { 'Yellow' } else { 'Gray' })
        Write-Host ""

        if ($results.Failed -gt 0 -or $results.Skipped -gt 0) {
            Write-Host "Details:" -ForegroundColor Gray
            foreach ($detail in $results.Details | Where-Object { $_.Status -ne 'Succeeded' }) {
                $color = if ($detail.Status -eq 'Failed') { 'Red' } else { 'Yellow' }
                Write-Host "  - $($detail.Release): $($detail.Status) - $($detail.Reason)" -ForegroundColor $color
            }
            Write-Host ""
        }

        # Return results object for pipeline usage
        [PSCustomObject]@{
            Processed = $results.Processed
            Succeeded = $results.Succeeded
            Failed    = $results.Failed
            Skipped   = $results.Skipped
            Details   = $results.Details
        }
    }
}
