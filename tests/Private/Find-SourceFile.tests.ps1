#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Find-SourceFile function.

.DESCRIPTION
    Tests source file discovery by name and optional size matching.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'FindSourceTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Find-SourceFile' {

    BeforeAll {
        # Create test directory structure
        $script:subDir = Join-Path $script:tempDir 'subdir'
        New-Item -Path $script:subDir -ItemType Directory -Force | Out-Null

        # Create test files with known sizes
        $script:file1Path = Join-Path $script:tempDir 'video.mkv'
        $script:file2Path = Join-Path $script:subDir 'video.mkv'
        $script:file3Path = Join-Path $script:tempDir 'sample.avi'

        # Create files with specific sizes
        [System.IO.File]::WriteAllBytes($script:file1Path, [byte[]](1..100))  # 100 bytes
        [System.IO.File]::WriteAllBytes($script:file2Path, [byte[]](1..200))  # 200 bytes
        [System.IO.File]::WriteAllBytes($script:file3Path, [byte[]](1..150))  # 150 bytes
    }

    Context 'Direct path matching' {
        It 'Finds file in root directory by name' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $result = Find-SourceFile -FileName 'video.mkv' -SearchPath $dir
                $result | Should -Not -BeNullOrEmpty
                $result | Should -BeLike '*video.mkv'
            }
        }

        It 'Finds file with different name' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $result = Find-SourceFile -FileName 'sample.avi' -SearchPath $dir
                $result | Should -Not -BeNullOrEmpty
                $result | Should -BeLike '*sample.avi'
            }
        }
    }

    Context 'Size matching' {
        It 'Returns file when size matches exactly' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $result = Find-SourceFile -FileName 'video.mkv' -SearchPath $dir -ExpectedSize 100
                $result | Should -Not -BeNullOrEmpty
            }
        }

        It 'Returns file when ExpectedSize is 0 (no size check)' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $result = Find-SourceFile -FileName 'video.mkv' -SearchPath $dir -ExpectedSize 0
                $result | Should -Not -BeNullOrEmpty
            }
        }

        It 'Returns null when size does not match direct file' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                # File exists but with wrong size, and recursive search finds one with different size
                $result = Find-SourceFile -FileName 'sample.avi' -SearchPath $dir -ExpectedSize 9999
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Recursive search' {
        It 'Finds file in subdirectory' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir; subDir = $script:subDir } {
                # Search for file that's only in subdir with correct size
                $result = Find-SourceFile -FileName 'video.mkv' -SearchPath $dir -ExpectedSize 200
                $result | Should -Not -BeNullOrEmpty
                $result | Should -BeLike '*subdir*video.mkv'
            }
        }
    }

    Context 'File not found' {
        It 'Returns null when file does not exist' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $result = Find-SourceFile -FileName 'nonexistent.xyz' -SearchPath $dir
                $result | Should -BeNullOrEmpty
            }
        }

        It 'Returns null when directory does not exist' {
            InModuleScope 'ReScenePS' {
                $result = Find-SourceFile -FileName 'test.mkv' -SearchPath 'C:\NonExistent\Path\12345'
                $result | Should -BeNullOrEmpty
            }
        }
    }
}
