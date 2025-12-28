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
    $PSBPreference.Test.CodeCoverage.Enabled = $true
    $PSBPreference.Test.CodeCoverage.Threshold = 0.70  # 70% minimum coverage

    # Test tools configuration
    $script:ToolsPath = Join-Path -Path $PSScriptRoot -ChildPath 'tools'
    # UnRAR command-line SFX archive from RARLab
    $script:UnrarSfxUrl = 'https://www.rarlab.com/rar/unrarw64.exe'
    $script:UnrarPath = Join-Path -Path $script:ToolsPath -ChildPath 'UnRAR.exe'
}

Task -Name 'Default' -Depends 'Test'

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

            # Extract silently using the SFX's built-in extraction
            # RAR SFX archives support -d<path> for destination directory
            Write-Host "Extracting UnRAR silently to $script:ToolsPath..."
            $extractArgs = "-d`"$script:ToolsPath`""
            $extractProcess = Start-Process -FilePath $sfxPath -ArgumentList $extractArgs -Wait -PassThru -WindowStyle Hidden

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

Task -Name 'Test' -FromModule 'PowerShellBuild' -MinimumVersion '0.7.3' -Depends 'DownloadTestTools'
