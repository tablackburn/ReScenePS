#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Get-RebuildableSubdirectory function.

.DESCRIPTION
    Tests the private function that scans subdirectories for rebuildable content
    (video files >= 100MB or .srr files).
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'GetRebuildableSubdirectoryTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Get-RebuildableSubdirectory' {

    Context 'Basic functionality' {
        BeforeAll {
            $script:basicDir = Join-Path $script:tempDir 'basic-test'
            New-Item -Path $script:basicDir -ItemType Directory -Force | Out-Null

            # Create a rebuildable subdirectory with SRR
            $script:rebuildableDir = Join-Path $script:basicDir 'Rebuildable.Release-TEST'
            New-Item -Path $script:rebuildableDir -ItemType Directory -Force | Out-Null
            New-MinimalSrrFile -Path (Join-Path $script:rebuildableDir 'release.srr')

            # Create a non-rebuildable subdirectory (empty)
            $script:emptyDir = Join-Path $script:basicDir 'Empty.Directory'
            New-Item -Path $script:emptyDir -ItemType Directory -Force | Out-Null
        }

        It 'Returns rebuildable directories only' {
            InModuleScope ReScenePS -Parameters @{ path = $script:basicDir } {
                param($path)
                $result = @(Get-RebuildableSubdirectory -Path $path -Depth 1)
                $result | Should -HaveCount 1
                $result[0] | Should -Match 'Rebuildable\.Release-TEST$'
            }
        }

        It 'Returns empty array when no rebuildable directories found' {
            InModuleScope ReScenePS -Parameters @{ path = $script:emptyDir } {
                param($path)
                $result = Get-RebuildableSubdirectory -Path $path -Depth 1
                $result | Should -HaveCount 0
            }
        }
    }

    Context 'Depth parameter behavior' {
        BeforeAll {
            $script:depthDir = Join-Path $script:tempDir 'depth-test'
            New-Item -Path $script:depthDir -ItemType Directory -Force | Out-Null

            # Create nested structure:
            # depth-test/
            #   level1-rebuildable/        (has SRR)
            #   level1-container/          (no content)
            #     level2-rebuildable/      (has SRR)
            #       level3-rebuildable/    (has SRR)

            $script:level1Rebuildable = Join-Path $script:depthDir 'Level1.Release-TEST'
            $script:level1Container = Join-Path $script:depthDir 'Level1.Container'
            $script:level2Rebuildable = Join-Path $script:level1Container 'Level2.Release-TEST'
            $script:level3Rebuildable = Join-Path $script:level2Rebuildable 'Level3.Release-TEST'

            New-Item -Path $script:level1Rebuildable -ItemType Directory -Force | Out-Null
            New-Item -Path $script:level2Rebuildable -ItemType Directory -Force | Out-Null
            New-Item -Path $script:level3Rebuildable -ItemType Directory -Force | Out-Null

            # Create SRR files in rebuildable directories
            New-MinimalSrrFile -Path (Join-Path $script:level1Rebuildable 'release.srr')
            New-MinimalSrrFile -Path (Join-Path $script:level2Rebuildable 'release.srr')
            New-MinimalSrrFile -Path (Join-Path $script:level3Rebuildable 'release.srr')
        }

        It 'Depth=1 finds immediate subdirectories only' {
            InModuleScope ReScenePS -Parameters @{ path = $script:depthDir } {
                param($path)
                $result = @(Get-RebuildableSubdirectory -Path $path -Depth 1)
                $result | Should -HaveCount 1
                $result[0] | Should -Match 'Level1\.Release-TEST$'
            }
        }

        It 'Depth=2 finds subdirectories and their children' {
            InModuleScope ReScenePS -Parameters @{ path = $script:depthDir } {
                param($path)
                $result = Get-RebuildableSubdirectory -Path $path -Depth 2
                $result | Should -HaveCount 2
            }
        }

        It 'Depth=3 finds three levels of subdirectories' {
            InModuleScope ReScenePS -Parameters @{ path = $script:depthDir } {
                param($path)
                $result = Get-RebuildableSubdirectory -Path $path -Depth 3
                $result | Should -HaveCount 3
            }
        }

        It 'Does not include non-rebuildable directories' {
            InModuleScope ReScenePS -Parameters @{ path = $script:depthDir; container = $script:level1Container } {
                param($path, $container)
                $result = @(Get-RebuildableSubdirectory -Path $path -Depth 3)
                $result | Should -Not -Contain $container
            }
        }
    }

    Context 'Path validation' {
        It 'Returns empty array for non-existent path' {
            $nonExistentPath = Join-Path $script:tempDir 'NonExistent_Path_12345'

            InModuleScope ReScenePS -Parameters @{ path = $nonExistentPath } {
                param($path)

                $result = Get-RebuildableSubdirectory -Path $path -Depth 1 -WarningAction SilentlyContinue

                $result | Should -HaveCount 0
            }
        }

        It 'Writes warning for non-existent path' {
            $nonExistentPath = Join-Path $script:tempDir 'NonExistent_Path_67890'

            # Capture warning output using 3>&1 redirection
            $output = InModuleScope ReScenePS -Parameters @{ path = $nonExistentPath } {
                param($path)
                Get-RebuildableSubdirectory -Path $path -Depth 1 3>&1
            }

            # Check if any output contains warning about non-existent path
            $warningText = $output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message }
            $warningText | Should -Match 'does not exist'
        }
    }

    Context 'Error handling' {
        It 'Writes warning and continues when Test-RebuildableDirectory throws exception' {
            $errorTestDir = Join-Path $script:tempDir 'error-handling-test'
            New-Item -Path $errorTestDir -ItemType Directory -Force | Out-Null

            # Create subdirectories - one rebuildable, one not
            $rebuildableDir = Join-Path $errorTestDir 'Rebuildable.Release-TEST'
            $nonRebuildableDir = Join-Path $errorTestDir 'NonRebuildable.Directory'
            New-Item -Path $rebuildableDir -ItemType Directory -Force | Out-Null
            New-Item -Path $nonRebuildableDir -ItemType Directory -Force | Out-Null

            # Create SRR in rebuildable directory
            New-MinimalSrrFile -Path (Join-Path $rebuildableDir 'release.srr')

            InModuleScope ReScenePS -Parameters @{ errorTestDir = $errorTestDir; rebuildableDir = $rebuildableDir; nonRebuildableDir = $nonRebuildableDir } {
                param($errorTestDir, $rebuildableDir, $nonRebuildableDir)

                # Mock Test-RebuildableDirectory to throw only for the non-rebuildable dir.
                #
                # Pester 6 removed mock fall-through: a call that matches no -ParameterFilter
                # no longer runs the real command, it errors with "there is no default mock to
                # fall back to". Capture the real command first and delegate to it from a
                # default mock, so every other path behaves as it did under Pester 5.
                $realTestRebuildableDirectory = Get-Command -Name 'Test-RebuildableDirectory' -CommandType 'Function'
                Mock Test-RebuildableDirectory { & $realTestRebuildableDirectory -Path $Path }

                Mock Test-RebuildableDirectory {
                    throw [System.UnauthorizedAccessException]::new("Access denied to $Path")
                } -ParameterFilter { $Path -eq $nonRebuildableDir } -Verifiable

                # Should continue processing and return the rebuildable dir, writing a warning
                $warningOutput = $null
                $result = Get-RebuildableSubdirectory -Path $errorTestDir -Depth 1 -WarningVariable warningOutput 3>&1

                # Should have found the rebuildable directory
                @($result).Count | Should -BeGreaterOrEqual 1
                $result | Should -Contain $rebuildableDir
            }

            # Cleanup
            Remove-Item -Path $errorTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Video file detection' {
        BeforeAll {
            $script:videoDir = Join-Path $script:tempDir 'video-detection'
            New-Item -Path $script:videoDir -ItemType Directory -Force | Out-Null

            # Create subdirectory with large video file
            $script:largeVideoDir = Join-Path $script:videoDir 'Large.Video.Release-TEST'
            New-Item -Path $script:largeVideoDir -ItemType Directory -Force | Out-Null
            $videoPath = Join-Path $script:largeVideoDir 'movie.mkv'
            $fs = [System.IO.File]::Create($videoPath)
            $fs.SetLength(100MB)
            $fs.Close()

            # Create subdirectory with small video file
            $script:smallVideoDir = Join-Path $script:videoDir 'Small.Video.Sample'
            New-Item -Path $script:smallVideoDir -ItemType Directory -Force | Out-Null
            $smallPath = Join-Path $script:smallVideoDir 'sample.mkv'
            $fs = [System.IO.File]::Create($smallPath)
            $fs.SetLength(50MB)
            $fs.Close()
        }

        It 'Includes directories with large video files (>= 100MB)' {
            InModuleScope ReScenePS -Parameters @{ path = $script:videoDir } {
                param($path)
                $result = @(Get-RebuildableSubdirectory -Path $path -Depth 1)
                $result | Should -HaveCount 1
                $result[0] | Should -Match 'Large\.Video\.Release-TEST$'
            }
        }

        It 'Excludes directories with only small video files (< 100MB)' {
            InModuleScope ReScenePS -Parameters @{ path = $script:videoDir } {
                param($path)
                $result = Get-RebuildableSubdirectory -Path $path -Depth 1
                $result | Should -Not -Match 'Small\.Video\.Sample'
            }
        }
    }
}
