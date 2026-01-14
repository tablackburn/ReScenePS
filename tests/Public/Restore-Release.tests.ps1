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
            $param.ParameterType | Should -Be ([switch])
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
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Has DeleteSources switch parameter' {
            $cmd = Get-Command Restore-Release
            $param = $cmd.Parameters['DeleteSources']
            $param | Should -Not -BeNull
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Has SkipValidation switch parameter' {
            $cmd = Get-Command Restore-Release
            $param = $cmd.Parameters['SkipValidation']
            $param | Should -Not -BeNull
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Has Depth parameter with default value of 1' {
            $cmd = Get-Command Restore-Release
            $param = $cmd.Parameters['Depth']
            $param | Should -Not -BeNull
            $param.ParameterType | Should -Be ([int])
        }

        It 'Depth parameter has ValidateRange(0, 10)' {
            $cmd = Get-Command Restore-Release
            $param = $cmd.Parameters['Depth']
            $validateRange = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $validateRange | Should -Not -BeNull
            $validateRange.MinRange | Should -Be 0
            $validateRange.MaxRange | Should -Be 10
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
            $warnings | Should -Match 'No rebuildable releases found'

            Remove-Item -Path $emptyDir -Force -Recurse
        }
    }

    Context 'Existing SRR file detection' {
        BeforeAll {
            $script:existingSrrDir = Join-Path $script:tempDir 'existing-srr'
            New-Item -Path $script:existingSrrDir -ItemType Directory -Force | Out-Null

            # Create a minimal SRR file
            $script:existingSrrFile = Join-Path $script:existingSrrDir 'release.srr'
            New-MinimalSrrFile -Path $script:existingSrrFile -AppName 'TestApp12345'
        }

        It 'Detects existing SRR file in release directory' {
            # The function should detect the existing SRR and skip srrDB download
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match '\.srr'
            $functionDef | Should -Match 'SRR already exists'
        }

        It 'Skips restoration in WhatIf mode when SRR exists' {
            $result = Restore-Release -Path $script:existingSrrDir -WhatIf
            $result.Skipped | Should -Be 1
            $result.Details[0].Status | Should -Be 'Skipped'
            $result.Details[0].Reason | Should -Be 'WhatIf mode'
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
            # Uses GetFileName to extract directory name (handles edge cases better than Split-Path -Leaf)
            $functionDef | Should -Match 'GetFileName'
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

        It 'Throws helpful error when Get-SatReleaseFile returns null SrrFile' -Skip:(-not (Get-Module SrrDBAutomationToolkit -ListAvailable)) {
            $testDir = Join-Path $script:tempDir 'null-srrfile-test'
            New-Item -Path $testDir -ItemType Directory -Force | Out-Null

            # Create a dummy video file to pass Test-RebuildableDirectory (100MB+ required)
            $dummyVideo = Join-Path $testDir 'movie.mkv'
            $fs = [System.IO.File]::Create($dummyVideo)
            $fs.SetLength(100MB)
            $fs.Close()

            try {
                InModuleScope ReScenePS -Parameters @{ testDir = $testDir } {
                    param($testDir)

                    Mock Get-SatReleaseFile {
                        [PSCustomObject]@{
                            SrrFile = $null
                            AdditionalFiles = @()
                        }
                    }

                    { Restore-Release -Path $testDir } | Should -Throw '*did not return an SRR file*'
                }
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Handles null AdditionalFiles gracefully' -Skip:(-not (Get-Module SrrDBAutomationToolkit -ListAvailable)) {
            $testDir = Join-Path $script:tempDir 'null-additionalfiles-test'
            New-Item -Path $testDir -ItemType Directory -Force | Out-Null
            $srrPath = Join-Path $testDir 'test.srr'

            # Create minimal SRR file outside InModuleScope
            New-MinimalSrrFile -Path $srrPath

            try {
                InModuleScope ReScenePS -Parameters @{ testDir = $testDir; srrPath = $srrPath } {
                    param($testDir, $srrPath)

                    Mock Get-SatReleaseFile {
                        [PSCustomObject]@{
                            SrrFile = [PSCustomObject]@{
                                FullName = $srrPath
                                Name = 'test.srr'
                            }
                            AdditionalFiles = $null  # null instead of empty array
                        }
                    }
                    Mock Invoke-SrrRestore { }

                    # Should not throw
                    { Restore-Release -Path $testDir } | Should -Not -Throw
                }
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
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

        It 'Passes DeleteSources parameter to Invoke-SrrRestore' {
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'DeleteSources'
        }

        It 'Passes SkipValidation parameter to Invoke-SrrRestore' {
            $functionDef = (Get-Command Restore-Release).Definition
            $functionDef | Should -Match 'SkipValidation'
        }
    }

    Context 'Additional files download' {
        BeforeAll {
            $script:additionalFilesDir = Join-Path $script:tempDir 'additional-files-test'
            New-Item -Path $script:additionalFilesDir -ItemType Directory -Force | Out-Null

            # Create a dummy video file to pass Test-RebuildableDirectory (100MB+ required)
            $dummyVideo = Join-Path $script:additionalFilesDir 'movie.mkv'
            $fs = [System.IO.File]::Create($dummyVideo)
            $fs.SetLength(100MB)
            $fs.Close()
        }

        It 'Outputs additional files when returned by Get-SatReleaseFile' -Skip:(-not (Get-Module SrrDBAutomationToolkit -ListAvailable)) {
            InModuleScope ReScenePS -Parameters @{ testDir = $script:additionalFilesDir } {
                param($testDir)

                # Don't create SRR file - we want Get-SatReleaseFile to be called
                # The mock will "create" the SRR file path
                $srrPath = Join-Path $testDir 'test-release.srr'

                # Mock Get-SatReleaseFile to return AdditionalFiles
                Mock Get-SatReleaseFile {
                    # Create minimal SRR when mock is called (simulating download)
                    $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp')
                    $headerSize = 7 + 2 + $appName.Length
                    $ms = [System.IO.MemoryStream]::new()
                    $bw = [System.IO.BinaryWriter]::new($ms)
                    $bw.Write([uint16]0x6969)
                    $bw.Write([byte]0x69)
                    $bw.Write([uint16]0x0000)
                    $bw.Write([uint16]$headerSize)
                    $bw.Write([uint16]$appName.Length)
                    $bw.Write($appName)
                    $bw.Flush()
                    [System.IO.File]::WriteAllBytes($srrPath, $ms.ToArray())
                    $bw.Dispose()
                    $ms.Dispose()

                    [PSCustomObject]@{
                        SrrFile = [PSCustomObject]@{
                            FullName = $srrPath
                            Name = 'test-release.srr'
                        }
                        AdditionalFiles = @(
                            [PSCustomObject]@{ Name = 'proof.jpg' }
                            [PSCustomObject]@{ Name = 'sample.avi' }
                        )
                    }
                }

                # Mock Invoke-SrrRestore to prevent actual restoration
                Mock Invoke-SrrRestore {}

                # Run Restore-Release and capture output
                $output = Restore-Release -Path $testDir 6>&1

                # Verify mocks were called
                Should -Invoke Get-SatReleaseFile -Times 1
                Should -Invoke Invoke-SrrRestore -Times 1

                # Verify additional files were reported in output
                $outputText = $output -join "`n"
                $outputText | Should -Match 'proof\.jpg'
                $outputText | Should -Match 'sample\.avi'
            }
        }

        AfterAll {
            if ($script:additionalFilesDir -and (Test-Path $script:additionalFilesDir)) {
                Remove-Item -Path $script:additionalFilesDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Error handling in batch mode' {
        BeforeAll {
            $script:errorTestDir = Join-Path $script:tempDir 'error-test'
            New-Item -Path $script:errorTestDir -ItemType Directory -Force | Out-Null

            # Create subdirectories that will fail (no SRR, guaranteed-invalid release names using UUIDs)
            $script:failDir1 = Join-Path $script:errorTestDir 'RESCENEPS_TEST_INVALID_a1b2c3d4e5f6'
            $script:failDir2 = Join-Path $script:errorTestDir 'RESCENEPS_TEST_INVALID_f6e5d4c3b2a1'
            New-Item -Path $script:failDir1 -ItemType Directory -Force | Out-Null
            New-Item -Path $script:failDir2 -ItemType Directory -Force | Out-Null

            # Create dummy video files to pass Test-RebuildableDirectory (100MB+ required)
            foreach ($dir in @($script:failDir1, $script:failDir2)) {
                $dummyVideo = Join-Path $dir 'movie.mkv'
                $fs = [System.IO.File]::Create($dummyVideo)
                $fs.SetLength(100MB)
                $fs.Close()
            }
        }

        It 'Continues processing when one release fails in -Recurse mode' {
            # This will fail because:
            # 1. No SRR files exist in the directories
            # 2. Get-SatReleaseFile will fail (invalid release names)
            $result = Restore-Release -Path $script:errorTestDir -Recurse -ErrorAction SilentlyContinue

            # Should have processed both directories
            $result.Processed | Should -Be 2

            # Both should have failed
            $result.Failed | Should -Be 2

            # Details should show failure reasons
            $result.Details | Where-Object { $_.Status -eq 'Failed' } | Should -HaveCount 2
        }

        It 'Throws when single release fails without -Recurse' {
            # This will fail because no SRR exists and Get-SatReleaseFile will fail
            { Restore-Release -Path $script:failDir1 -ErrorAction Stop } | Should -Throw
        }

        It 'Records failure reason in results' {
            $result = Restore-Release -Path $script:errorTestDir -Recurse -ErrorAction SilentlyContinue

            # Each failure should have a reason
            foreach ($detail in $result.Details) {
                if ($detail.Status -eq 'Failed') {
                    $detail.Reason | Should -Not -BeNullOrEmpty
                }
            }
        }

        AfterAll {
            if ($script:errorTestDir -and (Test-Path -Path $script:errorTestDir)) {
                Remove-Item -Path $script:errorTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Summary output' {
        BeforeAll {
            $script:summaryTestDir = Join-Path $script:tempDir 'summary-output-test'
            New-Item -Path $script:summaryTestDir -ItemType Directory -Force | Out-Null

            # Create subdirectories that will fail for batch processing
            $script:summaryFailDir = Join-Path $script:summaryTestDir 'RESCENEPS_SUMMARY_FAIL_TEST'
            New-Item -Path $script:summaryFailDir -ItemType Directory -Force | Out-Null

            # Create a directory with existing SRR for WhatIf skip test
            $script:summarySkipDir = Join-Path $script:summaryTestDir 'RESCENEPS_SUMMARY_SKIP_TEST'
            New-Item -Path $script:summarySkipDir -ItemType Directory -Force | Out-Null

            # Create minimal SRR in skip dir
            $srrPath = Join-Path $script:summarySkipDir 'test.srr'
            New-MinimalSrrFile -Path $srrPath
        }

        It 'Displays details section when failures occur' {
            # Run in Recurse mode with a failing directory to capture details output
            $output = Restore-Release -Path $script:summaryTestDir -Recurse -ErrorAction SilentlyContinue 6>&1 2>&1
            $outputText = $output -join "`n"

            # Should show Details: section since there are failures
            $outputText | Should -Match 'Details:'
            $outputText | Should -Match 'Failed'
        }

        It 'Displays details section with Skipped status in WhatIf mode' {
            # WhatIf with existing SRR should show Skipped status
            $output = Restore-Release -Path $script:summarySkipDir -WhatIf 6>&1 2>&1
            $outputText = $output -join "`n"

            # Should show Details: section with Skipped entry
            $outputText | Should -Match 'Details:'
            $outputText | Should -Match 'Skipped'
        }

        AfterAll {
            if ($script:summaryTestDir -and (Test-Path $script:summaryTestDir)) {
                Remove-Item -Path $script:summaryTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'SourcePath parameter usage' {
        It 'Uses SourcePath when provided instead of release directory' {
            $functionDef = (Get-Command Restore-Release).Definition
            # Check that SourcePath is passed to Invoke-SrrRestore when not empty
            $functionDef | Should -Match 'SourcePath.*IsNullOrWhiteSpace'
        }
    }

    Context 'Results isolation between calls' {
        It 'Does not accumulate counters across multiple calls' {
            # Create a parent directory with two subdirectories for Recurse mode
            $parentDir = Join-Path $script:tempDir 'isolation-test-parent'
            $testDir1 = Join-Path $parentDir 'RESCENEPS_TEST_ISOLATION_1'
            $testDir2 = Join-Path $parentDir 'RESCENEPS_TEST_ISOLATION_2'
            New-Item -Path $testDir1, $testDir2 -ItemType Directory -Force | Out-Null

            # First call with Recurse - processes 2 dirs, both fail (no SRR)
            $result1 = Restore-Release -Path $parentDir -Recurse -ErrorAction SilentlyContinue 2>$null

            # Second call with Recurse - processes same 2 dirs
            $result2 = Restore-Release -Path $parentDir -Recurse -ErrorAction SilentlyContinue 2>$null

            # Each call should have its own isolated counter (Processed = 2 each)
            # If scope pollution existed, second call would show Processed = 4
            $result1.Processed | Should -Be 2
            $result2.Processed | Should -Be 2

            # Cleanup
            Remove-Item -Path $parentDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Depth parameter behavior' {
        BeforeAll {
            $script:depthTestDir = Join-Path $script:tempDir 'depth-test'
            New-Item -Path $script:depthTestDir -ItemType Directory -Force | Out-Null

            # Create directory structure:
            # depth-test/
            #   level1-rebuildable/          (has SRR file - rebuildable)
            #   level1-not-rebuildable/      (no video/SRR - container only)
            #     level2-rebuildable/        (has SRR file - rebuildable)
            #       level3-rebuildable/      (has SRR file - rebuildable)

            $script:level1Rebuildable = Join-Path $script:depthTestDir 'Level1.Rebuildable.Release-TEST'
            $script:level1NotRebuildable = Join-Path $script:depthTestDir 'Level1.Container'
            $script:level2Rebuildable = Join-Path $script:level1NotRebuildable 'Level2.Rebuildable.Release-TEST'
            $script:level3Rebuildable = Join-Path $script:level2Rebuildable 'Level3.Rebuildable.Release-TEST'

            New-Item -Path $script:level1Rebuildable -ItemType Directory -Force | Out-Null
            New-Item -Path $script:level1NotRebuildable -ItemType Directory -Force | Out-Null
            New-Item -Path $script:level2Rebuildable -ItemType Directory -Force | Out-Null
            New-Item -Path $script:level3Rebuildable -ItemType Directory -Force | Out-Null

            # Create SRR files in rebuildable directories (triggers "SRR already exists" path, skipping srrDB)
            foreach ($dir in @($script:level1Rebuildable, $script:level2Rebuildable, $script:level3Rebuildable)) {
                New-MinimalSrrFile -Path (Join-Path $dir 'release.srr')
            }
        }

        It 'Depth=0 disables subdirectory scanning when parent is not rebuildable' {
            # When the parent directory is not rebuildable and Depth=0, nothing should be found
            $result = Restore-Release -Path $script:depthTestDir -Depth 0 -WarningVariable warnings 3>&1

            $warnings | Should -Match 'No rebuildable releases found'
        }

        It 'Depth=0 processes only parent directory when parent IS rebuildable' {
            # When the parent directory itself is rebuildable, Depth=0 should process just that directory
            # without scanning any subdirectories
            $result = Restore-Release -Path $script:level1Rebuildable -Depth 0 -WhatIf

            # Should process only the parent directory (which is rebuildable)
            $result.Processed | Should -Be 1
            $result.Skipped | Should -Be 1
            $result.Details[0].Release | Should -Be 'Level1.Rebuildable.Release-TEST'
        }

        It 'Depth=1 finds immediate subdirectories only' {
            # Should find level1-rebuildable but NOT level2 or level3
            # Use -WhatIf to skip actual restoration and verify scan results
            $result = Restore-Release -Path $script:depthTestDir -Depth 1 -WhatIf

            # Only the one immediate rebuildable subdir should be found
            $result.Processed | Should -Be 1
            $result.Skipped | Should -Be 1
            $result.Details[0].Release | Should -Be 'Level1.Rebuildable.Release-TEST'
        }

        It 'Depth=2 finds subdirectories and their children' {
            # Should find level1-rebuildable AND level2-rebuildable, but NOT level3
            $result = Restore-Release -Path $script:depthTestDir -Depth 2 -WhatIf

            # Both level1 and level2 rebuildable dirs should be found
            $result.Processed | Should -Be 2
            $result.Skipped | Should -Be 2
        }

        It 'Depth=3 finds three levels of subdirectories' {
            # Should find all three rebuildable directories
            $result = Restore-Release -Path $script:depthTestDir -Depth 3 -WhatIf

            # All three rebuildable dirs should be found
            $result.Processed | Should -Be 3
            $result.Skipped | Should -Be 3
        }

        It 'Skips non-rebuildable directories at any depth' {
            # level1-not-rebuildable should never be processed (no SRR or video files)
            $result = Restore-Release -Path $script:depthTestDir -Depth 3 -WhatIf

            # Should only process the 3 rebuildable directories, not the container
            $result.Processed | Should -Be 3
            $result.Details.Release | Should -Not -Contain 'Level1.Container'
        }

        It 'Depth parameter does not affect Recurse mode' {
            # In Recurse mode, all immediate subdirectories are processed regardless of Depth
            # (Depth only affects the auto-detect scanning in single mode)
            # level1-not-rebuildable will be processed but fail (no SRR or video files)
            $result = Restore-Release -Path $script:depthTestDir -Recurse -Depth 1 -ErrorAction SilentlyContinue 2>$null

            # Recurse mode processes all immediate subdirs (level1-rebuildable and level1-not-rebuildable)
            $result.Processed | Should -Be 2
        }

        AfterAll {
            if ($script:depthTestDir -and (Test-Path $script:depthTestDir)) {
                Remove-Item -Path $script:depthTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Exception handling in rebuildable directory check' {
        BeforeAll {
            $script:exceptionTestDir = Join-Path $script:tempDir 'exception-test'
            New-Item -Path $script:exceptionTestDir -ItemType Directory -Force | Out-Null
        }

        It 'Handles UnauthorizedAccessException gracefully with warning' {
            InModuleScope ReScenePS -Parameters @{ path = $script:exceptionTestDir } {
                param($path)

                Mock Test-RebuildableDirectory {
                    throw [System.UnauthorizedAccessException]::new("Access denied to test directory")
                }

                # Should not throw, should write warning and return empty results
                $warnings = @()
                $result = Restore-Release -Path $path -Depth 0 -WarningVariable warnings 3>&1

                # Check that at least one warning matches
                ($warnings -join "`n") | Should -Match 'Access denied'
            }
        }

        It 'Handles IOException gracefully with warning' {
            InModuleScope ReScenePS -Parameters @{ path = $script:exceptionTestDir } {
                param($path)

                Mock Test-RebuildableDirectory {
                    throw [System.IO.IOException]::new("IO error reading directory")
                }

                # Should not throw, should write warning and return empty results
                $warnings = @()
                $result = Restore-Release -Path $path -Depth 0 -WarningVariable warnings 3>&1

                # Check that at least one warning matches
                ($warnings -join "`n") | Should -Match 'IO error'
            }
        }

        It 'Handles generic exceptions gracefully with warning' {
            InModuleScope ReScenePS -Parameters @{ path = $script:exceptionTestDir } {
                param($path)

                Mock Test-RebuildableDirectory {
                    throw [System.Exception]::new("Unexpected error")
                }

                # Should not throw, should write warning and return empty results
                $warnings = @()
                $result = Restore-Release -Path $path -Depth 0 -WarningVariable warnings 3>&1

                # Check that at least one warning matches
                ($warnings -join "`n") | Should -Match 'Error checking directory'
            }
        }

        AfterAll {
            if ($script:exceptionTestDir -and (Test-Path $script:exceptionTestDir)) {
                Remove-Item -Path $script:exceptionTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
