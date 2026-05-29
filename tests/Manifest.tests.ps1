# spell-checker:ignore BHPS oneline
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'changelogVersion',
    Justification = 'false positive'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'gitTagVersion',
    Justification = 'false positive'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'manifestData',
    Justification = 'false positive'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'requirements',
    Justification = 'false positive'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'dependencies',
    Justification = 'false positive'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'dependencyName',
    Justification = 'false positive'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'dependencyRawData',
    Justification = 'false positive'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'manifestRawData',
    Justification = 'false positive'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'requirementsVersionSkipReason',
    Justification = 'false positive'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'requirementsVersion',
    Justification = 'false positive'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'candidateVersion',
    Justification = 'false positive'
)]
param()

BeforeDiscovery {
    <# Check if the BHBuildOutput environment variable exists to determine if this test is running in a psake
    build or not. If it does not exist, it is not running in a psake build, so build the module.
    If the BHBuildOutput environment variable exists, it is running in a psake build, so do not
    build the module. #>
    if ($null -eq $Env:BHBuildOutput) {
        # Populate BuildHelpers env vars so build.psake.ps1's properties block has
        # the values it needs (BHPSModuleManifest, BHProjectName) — when running
        # via ./build.ps1 this happens before psake; running tests in isolation
        # bypasses that, so we do it here.
        Set-BuildEnvironment -Path (Split-Path -Path $PSScriptRoot -Parent) -Force
        $buildFilePath = Join-Path -Path $PSScriptRoot -ChildPath '..\build.psake.ps1'
        $invokePsakeParameters = @{
            TaskList  = 'Build'
            BuildFile = $buildFilePath
        }
        Invoke-psake @invokePsakeParameters
    }

    # PowerShellBuild outputs to Output/<ModuleName>/<Version>/, override BHBuildOutput
    $projectRoot = Split-Path -Path $PSScriptRoot -Parent
    $sourceManifest = Join-Path -Path $projectRoot -ChildPath "$Env:BHProjectName/$Env:BHProjectName.psd1"
    $moduleVersion = (Import-PowerShellDataFile $sourceManifest).ModuleVersion
    $Env:BHBuildOutput = Join-Path -Path $projectRoot -ChildPath "Output/$Env:BHProjectName/$moduleVersion"

    # Define the path to the module manifest
    $moduleManifestFilename = $Env:BHProjectName + '.psd1'
    $moduleManifestPath = Join-Path -Path $Env:BHBuildOutput -ChildPath $moduleManifestFilename

    # Get the data from the module manifest
    $testModuleManifestParameters = @{
        Path          = $moduleManifestPath
        ErrorAction   = 'Stop'
        WarningAction = 'SilentlyContinue'
    }
    $manifestData = Test-ModuleManifest @testModuleManifestParameters
    $dependencies = $manifestData.RequiredModules

    # When running on the un-initialized template, CHANGELOG.md tracks the template's
    # CalVer version (YYYY.MM.DD), which deliberately decouples from the manifest's
    # ModuleVersion. Skip the equality assertion in that case; downstream modules (post-init)
    # keep the assertion. Marker: CHANGELOG.template.md exists only pre-init —
    # Initialize-Template.ps1 moves it onto CHANGELOG.md during init. The marker survives
    # the init substitution loop because no token in the path matches a {{Placeholder}}.
    $isTemplate = Test-Path -LiteralPath (Join-Path -Path $Env:BHProjectPath -ChildPath 'CHANGELOG.template.md')
}
BeforeAll {
    <# Check if the BHBuildOutput environment variable exists to determine if this test is running in a psake
    build or not. If it does not exist, it is not running in a psake build, so build the module.
    If the BHBuildOutput environment variable exists, it is running in a psake build, so do not
    build the module. #>
    if ($null -eq $Env:BHBuildOutput) {
        # Populate BuildHelpers env vars so build.psake.ps1's properties block has
        # the values it needs (BHPSModuleManifest, BHProjectName) — when running
        # via ./build.ps1 this happens before psake; running tests in isolation
        # bypasses that, so we do it here.
        Set-BuildEnvironment -Path (Split-Path -Path $PSScriptRoot -Parent) -Force
        $buildFilePath = Join-Path -Path $PSScriptRoot -ChildPath '..\build.psake.ps1'
        $invokePsakeParameters = @{
            TaskList  = 'Build'
            BuildFile = $buildFilePath
        }
        Invoke-psake @invokePsakeParameters
    }

    # PowerShellBuild outputs to Output/<ModuleName>/<Version>/, override BHBuildOutput
    $projectRoot = Split-Path -Path $PSScriptRoot -Parent
    $sourceManifest = Join-Path -Path $projectRoot -ChildPath "$Env:BHProjectName/$Env:BHProjectName.psd1"
    $moduleVersion = (Import-PowerShellDataFile $sourceManifest).ModuleVersion
    $Env:BHBuildOutput = Join-Path -Path $projectRoot -ChildPath "Output/$Env:BHProjectName/$moduleVersion"

    # Define the path to the module manifest
    $moduleManifestFilename = $Env:BHProjectName + '.psd1'
    $moduleManifestPath = Join-Path -Path $Env:BHBuildOutput -ChildPath $moduleManifestFilename

    # Get the data from the module manifest
    $testModuleManifestParameters = @{
        Path          = $moduleManifestPath
        ErrorAction   = 'Stop'
        WarningAction = 'SilentlyContinue'
    }
    $importDataFileParameters = @{
        Path          = $moduleManifestPath
        ErrorAction   = 'Stop'
        WarningAction = 'SilentlyContinue'
    }
    $manifestData = Test-ModuleManifest @testModuleManifestParameters
    $manifestRawData = Import-PowerShellDataFile @importDataFileParameters

    # Import ManifestHelpers.psm1 for SemVer helper functions
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'ManifestHelpers.psm1') -Verbose:$false -Force

    # ReScenePS tracks runtime dependencies in runtime.depend.psd1 (a PSDepend requirements
    # file) where the template uses requirements.psd1; the dependency-sync checks read from it.
    $requirementsPath = Join-Path -Path $Env:BHProjectPath -ChildPath 'runtime.depend.psd1'
    $requirements = Import-PowerShellDataFile $requirementsPath -ErrorAction 'Stop'

    # Parse the version from the changelog
    $changelogPath = Join-Path -Path $Env:BHProjectPath -ChildPath 'CHANGELOG.md'
    $changelogVersionPattern = '^##\s\\?\[(?<Version>(\d+\.){1,3}\d+)\\?\]' # Matches on a line that starts with '## [Version]' or '## \[Version\]'
    # Select-String returns the first matching line's named capture directly — no loop and no
    # 'break' (which is unreliable inside ForEach-Object, since a pipeline is not a loop).
    $changelogVersion = (Select-String -Path $changelogPath -Pattern $changelogVersionPattern |
        Select-Object -First 1).Matches[0].Groups['Version'].Value
}
Describe 'Module manifest' {

    Context 'Validation' {

        It 'Has a valid manifest' {
            $manifestData | Should -Not -BeNullOrEmpty
        }

        It 'Has a valid name in the manifest' {
            $manifestData.Name | Should -Be $Env:BHProjectName
        }

        It 'Has a valid root module' {
            $manifestData.RootModule | Should -Be "$($Env:BHProjectName).psm1"
        }

        It 'Has a valid version in the manifest' {
            $manifestData.Version -as [Version] | Should -Not -BeNullOrEmpty
        }

        It 'Has a valid description' {
            $manifestData.Description | Should -Not -BeNullOrEmpty
        }

        It 'Has a valid author' {
            $manifestData.Author | Should -Not -BeNullOrEmpty
        }

        It 'Has a valid guid' {
            { [guid]::Parse($manifestData.Guid) } | Should -Not -Throw
        }

        It 'Has a valid copyright' {
            $manifestData.CopyRight | Should -Not -BeNullOrEmpty
        }

        It 'Has a valid version in the changelog' {
            $changelogVersion | Should -Not -BeNullOrEmpty
            $changelogVersion -as [Version] | Should -Not -BeNullOrEmpty
        }

        It 'Changelog and manifest versions are the same' -Skip:$isTemplate {
            $changelogVersion -as [Version] | Should -Be ( $manifestData.Version -as [Version] )
        }

        Context 'Module Dependency' -ForEach $dependencies {
            # This ensures we keep our dependent modules in sync between the manifest file and the
            # runtime.depend.psd1 requirements script used to bootstrap and test.
            BeforeAll {
                $dependencyName = $_.Name
                $dependencyRawData = $manifestRawData.RequiredModules | Where-Object {
                    $_ -eq $dependencyName -or $_.ModuleName -eq $dependencyName
                }
                # Ensure exactly one match - duplicates should fail, not silently skip
                if (@($dependencyRawData).Count -gt 1) {
                    throw "Duplicate RequiredModules entry found for '$dependencyName'"
                }
                # Handle plain-string module references (not hashtables with version info)
                if ($dependencyRawData -isnot [hashtable]) {
                    $dependencyRawData = $null
                }

                # Extract version from runtime.depend.psd1 (shared logic for all version constraint tests)
                $requirementsVersionSkipReason = $null
                $requirementsVersion = $null

                if (-not $requirements.ContainsKey($dependencyName)) {
                    $requirementsVersionSkipReason = 'dependency not found in runtime.depend.psd1'
                } elseif ($requirements.Item($dependencyName) -is [string]) {
                    # Plain string format: 'ModuleName' = '1.2.3'
                    $candidateVersion = $requirements.Item($dependencyName)
                    if ([string]::IsNullOrWhiteSpace($candidateVersion)) {
                        $requirementsVersionSkipReason = "runtime.depend.psd1 entry for '$dependencyName' has an empty Version"
                    } else {
                        $requirementsVersion = $candidateVersion
                    }
                } elseif ($requirements.Item($dependencyName) -is [hashtable] -and $requirements.Item($dependencyName).ContainsKey('Version')) {
                    # Hashtable format: 'ModuleName' = @{ Version = '1.2.3' }
                    $candidateVersion = $requirements.Item($dependencyName).Version
                    if ([string]::IsNullOrWhiteSpace($candidateVersion)) {
                        $requirementsVersionSkipReason = "runtime.depend.psd1 entry for '$dependencyName' has an empty Version"
                    } else {
                        $requirementsVersion = $candidateVersion
                    }
                } else {
                    # Invalid format
                    $requirementsVersionSkipReason = "runtime.depend.psd1 entry for '$dependencyName' must be a string or hashtable with a Version key"
                }
            }

            It '<_.Name> exists in runtime.depend.psd1' {
                $requirements.ContainsKey($dependencyName) | Should -BeTrue
            }

            It '<_.Name> uses at least one version key' {
                if ($null -eq $dependencyRawData) {
                    Set-ItResult -Skipped -Because 'Plain-string module reference without version constraints'
                }

                # Valid dependency version keys
                $validDependencyKeys = @(
                    'ModuleVersion'    # Specifies a minimum acceptable version of the module
                    'RequiredVersion'  # Specifies an exact, required version of the module
                    'MaximumVersion'   # Specifies a maximum acceptable version of the module
                )
                $dependencyKeysUsed = $dependencyRawData.Keys | Where-Object { $_ -in $validDependencyKeys }
                $dependencyKeysUsed.Count | Should -BeGreaterThan 0
            }

            It '<_.Name> has a matching required version in runtime.depend.psd1' {
                if ($null -eq $dependencyRawData -or -not $dependencyRawData.ContainsKey('RequiredVersion')) {
                    Set-ItResult -Skipped -Because 'No RequiredVersion specified in the manifest'
                }

                if ($requirementsVersionSkipReason) {
                    Set-ItResult -Skipped -Because $requirementsVersionSkipReason
                }

                $constraintParameters = @{
                    ManifestVersion     = $dependencyRawData.RequiredVersion
                    RequirementsVersion = $requirementsVersion
                    Constraint          = 'Equal'
                }
                Test-VersionConstraint @constraintParameters | Should -BeTrue
            }

            It '<_.Name> has a maximum version greater than or equal to runtime.depend.psd1' {
                if ($null -eq $dependencyRawData -or -not $dependencyRawData.ContainsKey('MaximumVersion')) {
                    Set-ItResult -Skipped -Because 'No MaximumVersion specified in the manifest'
                }

                if ($requirementsVersionSkipReason) {
                    Set-ItResult -Skipped -Because $requirementsVersionSkipReason
                }

                $constraintParameters = @{
                    ManifestVersion     = $dependencyRawData.MaximumVersion
                    RequirementsVersion = $requirementsVersion
                    Constraint          = 'GreaterOrEqual'
                }
                Test-VersionConstraint @constraintParameters | Should -BeTrue
            }

            It '<_.Name> has a minimum version at or below runtime.depend.psd1' {
                if ($null -eq $dependencyRawData -or -not $dependencyRawData.ContainsKey('ModuleVersion')) {
                    Set-ItResult -Skipped -Because 'No ModuleVersion specified in the manifest'
                }

                if ($requirementsVersionSkipReason) {
                    Set-ItResult -Skipped -Because $requirementsVersionSkipReason
                }

                $constraintParameters = @{
                    ManifestVersion     = $dependencyRawData.ModuleVersion
                    RequirementsVersion = $requirementsVersion
                    Constraint          = 'LessOrEqual'
                }
                Test-VersionConstraint @constraintParameters | Should -BeTrue
            }
        }
    }
}

Describe 'Git tagging' -Skip {
    BeforeAll {
        $gitTagVersion = $null

        if ($git = Get-Command -Name 'git' -CommandType 'Application' -ErrorAction 'SilentlyContinue') {
            $thisCommit = & $git log --decorate --oneline HEAD~1..HEAD
            if ($thisCommit -match 'tag:\s*(\d+(?:\.\d+)*)') { $gitTagVersion = $matches[1] }
        }
    }

    It 'Is tagged with a valid version' {
        $gitTagVersion | Should -Not -BeNullOrEmpty
        $gitTagVersion -as [Version] | Should -Not -BeNullOrEmpty
    }

    It 'Matches manifest version' {
        $manifestData.Version -as [Version] | Should -Be ( $gitTagVersion -as [Version])
    }
}
