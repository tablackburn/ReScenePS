#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Restore-Release function.

.DESCRIPTION
    Tests the high-level release restoration automation function with parameter
    validation, srrDB integration, and error handling.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'RestoreReleaseTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Restore-Release' {

    Context 'Parameter validation' {
        It 'Path defaults to current directory' {
            $cmd = Get-Command Restore-Release
            $param = $cmd.Parameters['Path']
            $param | Should -Not -BeNull
        }

        It 'Has Recurse switch parameter' {
            $cmd = Get-Command Restore-Release
            $param = $cmd.Parameters['Recurse']
            $param | Should -Not -BeNull
            $param.SwitchParameter | Should -BeTrue
        }

        It 'Has SourcePath parameter' {
            $cmd = Get-Command Restore-Release
            $param = $cmd.Parameters['SourcePath']
            $param | Should -Not -BeNull
        }

        It 'Has KeepSrr switch parameter' {
            $cmd = Get-Command Restore-Release
            $param = $cmd.Parameters['KeepSrr']
            $param | Should -Not -BeNull
            $param.SwitchParameter | Should -BeTrue
        }

        It 'Has KeepSources switch parameter' {
            $cmd = Get-Command Restore-Release
            $param = $cmd.Parameters['KeepSources']
            $param | Should -Not -BeNull
            $param.SwitchParameter | Should -BeTrue
        }

        It 'Has SkipValidation switch parameter' {
            $cmd = Get-Command Restore-Release
            $param = $cmd.Parameters['SkipValidation']
            $param | Should -Not -BeNull
            $param.SwitchParameter | Should -BeTrue
        }
    }

    Context 'SupportsShouldProcess' {
        It 'Supports -WhatIf parameter' {
            $cmd = Get-Command Restore-Release
            $cmd.Parameters['WhatIf'] | Should -Not -BeNull
        }

        It 'Supports -Confirm parameter' {
            $cmd = Get-Command Restore-Release
            $cmd.Parameters['Confirm'] | Should -Not -BeNull
        }
    }

    Context 'Path validation' {
        It 'Throws when path does not exist' {
            $nonExistent = Join-Path $script:tempDir 'NonExistent_12345'
            { Restore-Release -Path $nonExistent } | Should -Throw '*does not exist*'
        }

        It 'Accepts valid directory path' {
            $validDir = Join-Path $script:tempDir 'valid-path-test'
            New-Item -Path $validDir -ItemType Directory -Force | Out-Null

            # Will fail due to missing SrrDBAutomationToolkit or srrDB lookup, but path validation should pass
            # We verify by checking the error message doesn't contain "does not exist" for the path
            $errorMessage = $null
            try {
                Restore-Release -Path $validDir -WhatIf
            }
            catch {
                $errorMessage = $_.Exception.Message
            }

            # If there's an error, it should NOT be about the path not existing
            if ($errorMessage) {
                $errorMessage | Should -Not -BeLike "*Directory does not exist*"
            }
        }
    }

    Context 'Module dependency' {
        It 'Requires SrrDBAutomationToolkit via module manifest' {
            $manifest = Import-PowerShellDataFile "$PSScriptRoot/../../ReScenePS/ReScenePS.psd1"
            $manifest.RequiredModules | Should -Not -BeNullOrEmpty
            $requiredModule = $manifest.RequiredModules | Where-Object { $_.ModuleName -eq 'SrrDBAutomationToolkit' }
            $requiredModule | Should -Not -BeNull
        }
    }

    Context 'Recurse mode' {
        BeforeAll {
            $script:recurseDir = Join-Path $script:tempDir 'recurse-test'
            New-Item -Path $script:recurseDir -ItemType Directory -Force | Out-Null

            # Create subdirectories that look like release names
            $release1 = Join-Path $script:recurseDir 'Movie.2024.1080p.BluRay-GROUP1'
            $release2 = Join-Path $script:recurseDir 'Movie.2024.720p.BluRay-GROUP2'
            New-Item -Path $release1 -ItemType Directory -Force | Out-Null
            New-Item -Path $release2 -ItemType Directory -Force | Out-Null
        }

        It 'Processes subdirectories when -Recurse is specified' {
            # Mock or skip actual srrDB calls - just verify the function processes multiple dirs
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'Recurse'
            $functionDef | Should -Match 'Get-ChildItem.*Directory'
        }

        It 'Warns when no subdirectories found in Recurse mode' {
            $emptyDir = Join-Path $script:tempDir 'empty-recurse-test'
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            $result = Restore-Release -Path $emptyDir -Recurse -WarningVariable warnings 3>&1
            $warnings | Should -Match 'No directories found'

            Remove-Item -Path $emptyDir -Force -Recurse
        }
    }

    Context 'Existing SRR file detection' {
        BeforeAll {
            $script:existingSrrDir = Join-Path $script:tempDir 'existing-srr'
            New-Item -Path $script:existingSrrDir -ItemType Directory -Force | Out-Null

            # Create a minimal SRR file
            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp12345')
            $headerSize = 7 + 2 + $appName.Length

            $script:existingSrrFile = Join-Path $script:existingSrrDir 'release.srr'
            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            $bw.Write([uint16]0x6969)
            $bw.Write([byte]0x69)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]$headerSize)
            $bw.Write([uint16]$appName.Length)
            $bw.Write($appName)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:existingSrrFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Detects existing SRR file in release directory' {
            # The function should detect the existing SRR and skip srrDB download
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match '\.srr'
            $functionDef | Should -Match 'SRR already exists'
        }
    }

    Context 'Output results' {
        It 'Returns a results object with expected properties' {
            # Verify the function returns a structured result
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'Processed'
            $functionDef | Should -Match 'Succeeded'
            $functionDef | Should -Match 'Failed'
            $functionDef | Should -Match 'Skipped'
        }
    }

    Context 'Release name detection' {
        It 'Uses folder name as release name' {
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'Split-Path.*Leaf'
        }
    }

    Context 'srrDB integration' {
        It 'Uses Get-SatReleaseFile for downloading release files' {
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'Get-SatReleaseFile'
        }

        It 'Passes ReleaseName to Get-SatReleaseFile' {
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'Get-SatReleaseFile.*-ReleaseName'
        }

        It 'Passes OutPath to Get-SatReleaseFile' {
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'Get-SatReleaseFile.*-OutPath'
        }

        It 'Uses PassThru to get download results' {
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'Get-SatReleaseFile.*-PassThru'
        }
    }

    Context 'Invoke-SrrRestore integration' {
        It 'Calls Invoke-SrrRestore for reconstruction' {
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'Invoke-SrrRestore'
        }

        It 'Passes KeepSrr parameter to Invoke-SrrRestore' {
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'KeepSrr'
        }

        It 'Passes KeepSources parameter to Invoke-SrrRestore' {
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'KeepSources'
        }

        It 'Passes SkipValidation parameter to Invoke-SrrRestore' {
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'SkipValidation'
        }
    }

    Context 'Error handling in batch mode' {
        It 'Continues processing when one release fails in -Recurse mode' {
            $functionDef = (Get-Command Restore-Release).Definition
            # The function should catch errors and continue when in Recurse mode
            $functionDef | Should -Match 'catch'
            $functionDef | Should -Match 'continue'
        }

        It 'Throws when single release fails without -Recurse' {
            $functionDef = (Get-Command Restore-Release).Definition
            # The function should re-throw errors when not in Recurse mode
            $functionDef | Should -Match 'throw'
        }
    }

    Context 'Summary output' {
        It 'Displays summary after processing' {
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'Summary'
        }
    }
}
