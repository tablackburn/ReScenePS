param()

# Allow end users to add their own custom psake tasks
$customPsakeFile = Join-Path -Path $PSScriptRoot -ChildPath 'custom.psake.ps1'
if (Test-Path -Path $customPsakeFile) {
    Include -FileNamePathToInclude $customPsakeFile
}

properties {
    # Set this to $true to create a module with a monolithic PSM1
    $PSBPreference.Build.CompileModule = $false
    $PSBPreference.Help.DefaultLocale = 'en-US'
    $PSBPreference.Test.OutputFile = 'out/testResults.xml'
    $PSBPreference.Test.OutputFormat = 'NUnitXml'

    # Code coverage configuration
    $PSBPreference.Test.CodeCoverage.OutputFormat = 'JaCoCo'
    $PSBPreference.Test.CodeCoverage.OutputFile = 'out/coverage.xml'
    # Since CompileModule = $false, source files are copied to Output/ and tests run against them
    # We must point coverage to the built module files since that's what gets executed
    $PSBPreference.Test.CodeCoverage.Enabled = $true
    # Disable threshold - JaCoCo "instruction" coverage doesn't apply to PowerShell
    # Actual coverage enforcement is handled by Codecov
    $PSBPreference.Test.CodeCoverage.Threshold = 0

    # Compute module output path (ModuleOutDir is null until Initialize-PSBuild runs)
    $moduleName = 'ReScenePS'
    $sourceManifest = Join-Path $PSScriptRoot "$moduleName/$moduleName.psd1"
    $moduleVersion = (Import-PowerShellDataFile -Path $sourceManifest).ModuleVersion
    $moduleOutDir = Join-Path $PSScriptRoot "Output/$moduleName/$moduleVersion"

    $PSBPreference.Test.CodeCoverage.Files = @(
        (Join-Path $moduleOutDir 'Public/*.ps1'),
        (Join-Path $moduleOutDir 'Private/*.ps1'),
        (Join-Path $moduleOutDir 'Classes/*.ps1')
    )

    # Test tools configuration
    $script:ToolsPath = Join-Path -Path $PSScriptRoot -ChildPath 'tools'
    # UnRAR command-line SFX archive from RARLab
    $script:UnrarSfxUrl = 'https://www.rarlab.com/rar/unrarw64.exe'
    $script:UnrarPath = Join-Path -Path $script:ToolsPath -ChildPath 'UnRAR.exe'
}

Task -Name 'Default' -Depends 'Test'

# Override PowerShellBuild's Pester dependency to include DownloadTestTools
# This ensures UnRAR is available before running tests
$PSBPesterDependency = @('Build', 'DownloadTestTools')

Task -Name 'DownloadTestTools' -Description 'Download test dependencies (UnRAR)' {
    # First check if UnRAR is already available in common locations
    $existingUnrar = @(
        'C:\Program Files\WinRAR\UnRAR.exe',
        'C:\Program Files (x86)\WinRAR\UnRAR.exe',
        "$env:LOCALAPPDATA\Programs\WinRAR\UnRAR.exe"
    ) | Where-Object { Test-Path -Path $_ } | Select-Object -First 1

    if ($existingUnrar) {
        Write-Host "Found existing UnRAR installation: $existingUnrar"
        Write-Host "Tests will use this installation."
        return
    }

    # Check if 7-Zip is available (common on CI runners)
    $sevenZip = Get-Command '7z' -ErrorAction SilentlyContinue
    if (-not $sevenZip) {
        $sevenZipPaths = @(
            'C:\Program Files\7-Zip\7z.exe',
            'C:\Program Files (x86)\7-Zip\7z.exe'
        )
        $sevenZip = $sevenZipPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    else {
        $sevenZip = $sevenZip.Source
    }

    if (-not (Test-Path -Path $script:ToolsPath)) {
        New-Item -Path $script:ToolsPath -ItemType Directory -Force | Out-Null
        Write-Host "Created tools directory: $script:ToolsPath"
    }

    if (-not (Test-Path -Path $script:UnrarPath)) {
        Write-Host "Downloading UnRAR SFX from $script:UnrarSfxUrl..."
        try {
            $ProgressPreference = 'SilentlyContinue'  # Speeds up Invoke-WebRequest
            $sfxPath = Join-Path -Path $script:ToolsPath -ChildPath 'unrarw64.exe'
            Invoke-WebRequest -Uri $script:UnrarSfxUrl -OutFile $sfxPath -UseBasicParsing

            # Try to extract using 7-Zip first (reliable on CI)
            if ($sevenZip -and (Test-Path $sevenZip)) {
                Write-Host "Extracting UnRAR using 7-Zip..."
                $extractResult = & $sevenZip x $sfxPath "-o$($script:ToolsPath)" -y 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "7-Zip extraction returned: $extractResult"
                }
            }
            else {
                # Fallback: try running the SFX with timeout (might show GUI on Windows)
                Write-Host "Extracting UnRAR silently to $script:ToolsPath..."
                Write-Host "(Note: If this hangs, install 7-Zip or WinRAR)"
                $extractArgs = "-d`"$script:ToolsPath`""

                # Use a job with timeout to prevent hanging on GUI dialogs
                $job = Start-Job -ScriptBlock {
                    param($sfx, $args)
                    Start-Process -FilePath $sfx -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
                } -ArgumentList $sfxPath, $extractArgs

                $completed = Wait-Job -Job $job -Timeout 30
                if (-not $completed) {
                    Write-Warning "UnRAR extraction timed out (GUI installer may need manual interaction)"
                    Stop-Job -Job $job
                    Remove-Job -Job $job -Force
                }
                else {
                    $result = Receive-Job -Job $job
                    Remove-Job -Job $job
                }
            }

            # Remove the SFX after extraction
            Remove-Item -Path $sfxPath -Force -ErrorAction SilentlyContinue

            if (Test-Path -Path $script:UnrarPath) {
                Write-Host "UnRAR extracted to: $script:UnrarPath"
            }
            else {
                # The SFX might extract to a subdirectory, try to find it
                $foundUnrar = Get-ChildItem -Path $script:ToolsPath -Filter 'UnRAR.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($foundUnrar) {
                    Write-Host "UnRAR found at: $($foundUnrar.FullName)"
                }
                else {
                    Write-Warning "UnRAR extraction may have failed - UnRAR.exe not found in tools directory"
                    Write-Warning "Some functional tests will be skipped."
                }
            }
        }
        catch {
            Write-Warning "Failed to download/extract UnRAR: $_"
            Write-Warning "Some functional tests may be skipped. Install WinRAR or place UnRAR.exe in the tools directory."
        }
    }
    else {
        Write-Host "UnRAR already present: $script:UnrarPath"
    }
}

# Import the Test task from PowerShellBuild (uses $PSBTestDependency which includes Pester and Analyze)
Task -Name 'Test' -FromModule 'PowerShellBuild' -MinimumVersion '0.7.3'
