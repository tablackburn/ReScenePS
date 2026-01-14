#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Test-RebuildableDirectory function.

.DESCRIPTION
    Tests the private function that checks if a directory contains rebuildable source files
    (video files >= 100MB or .srr files).
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'TestRebuildableDirectoryTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Test-RebuildableDirectory' {

    Context 'Directory validation' {
        It 'Returns false for non-existent directory' {
            $nonExistent = Join-Path $script:tempDir 'NonExistent_12345'

            InModuleScope ReScenePS -Parameters @{ path = $nonExistent } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $false
            }
        }

        It 'Returns false for empty directory' {
            $emptyDir = Join-Path $script:tempDir 'empty-dir'
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            InModuleScope ReScenePS -Parameters @{ path = $emptyDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $false
            }
        }
    }

    Context 'SRR file detection' {
        It 'Returns true when directory contains .srr file' {
            $srrDir = Join-Path $script:tempDir 'srr-test'
            New-Item -Path $srrDir -ItemType Directory -Force | Out-Null
            New-MinimalSrrFile -Path (Join-Path $srrDir 'test.srr')

            InModuleScope ReScenePS -Parameters @{ path = $srrDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $true
            }
        }

        It 'Detects SRR file regardless of video files present' {
            $srrWithVideoDir = Join-Path $script:tempDir 'srr-with-video'
            New-Item -Path $srrWithVideoDir -ItemType Directory -Force | Out-Null
            New-MinimalSrrFile -Path (Join-Path $srrWithVideoDir 'test.srr')
            # Create a small video file (should not affect SRR detection)
            [System.IO.File]::WriteAllBytes((Join-Path $srrWithVideoDir 'small.mkv'), [byte[]]::new(1024))

            InModuleScope ReScenePS -Parameters @{ path = $srrWithVideoDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $true
            }
        }
    }

    Context 'Video file detection' {
        BeforeAll {
            $script:videoDir = Join-Path $script:tempDir 'video-test'
            New-Item -Path $script:videoDir -ItemType Directory -Force | Out-Null
        }

        It 'Returns true for directory with large .mkv file (>= 100MB)' {
            $largeVideoDir = Join-Path $script:tempDir 'large-mkv'
            New-Item -Path $largeVideoDir -ItemType Directory -Force | Out-Null

            # Create a 100MB sparse file
            $videoPath = Join-Path $largeVideoDir 'movie.mkv'
            $fs = [System.IO.File]::Create($videoPath)
            $fs.SetLength(100MB)
            $fs.Close()

            InModuleScope ReScenePS -Parameters @{ path = $largeVideoDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $true
            }
        }

        It 'Returns true for directory with large .avi file' {
            $aviDir = Join-Path $script:tempDir 'large-avi'
            New-Item -Path $aviDir -ItemType Directory -Force | Out-Null

            $videoPath = Join-Path $aviDir 'movie.avi'
            $fs = [System.IO.File]::Create($videoPath)
            $fs.SetLength(100MB)
            $fs.Close()

            InModuleScope ReScenePS -Parameters @{ path = $aviDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $true
            }
        }

        It 'Returns true for directory with large .mp4 file' {
            $mp4Dir = Join-Path $script:tempDir 'large-mp4'
            New-Item -Path $mp4Dir -ItemType Directory -Force | Out-Null

            $videoPath = Join-Path $mp4Dir 'movie.mp4'
            $fs = [System.IO.File]::Create($videoPath)
            $fs.SetLength(100MB)
            $fs.Close()

            InModuleScope ReScenePS -Parameters @{ path = $mp4Dir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $true
            }
        }

        It 'Returns true for directory with large .m2ts file' {
            $m2tsDir = Join-Path $script:tempDir 'large-m2ts'
            New-Item -Path $m2tsDir -ItemType Directory -Force | Out-Null

            $videoPath = Join-Path $m2tsDir 'movie.m2ts'
            $fs = [System.IO.File]::Create($videoPath)
            $fs.SetLength(100MB)
            $fs.Close()

            InModuleScope ReScenePS -Parameters @{ path = $m2tsDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $true
            }
        }

        It 'Returns false for directory with small video file (< 100MB)' {
            $smallVideoDir = Join-Path $script:tempDir 'small-video'
            New-Item -Path $smallVideoDir -ItemType Directory -Force | Out-Null

            # Create a 50MB file (below threshold)
            $videoPath = Join-Path $smallVideoDir 'small.mkv'
            $fs = [System.IO.File]::Create($videoPath)
            $fs.SetLength(50MB)
            $fs.Close()

            InModuleScope ReScenePS -Parameters @{ path = $smallVideoDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $false
            }
        }

        It 'Returns false for directory with non-video files only' {
            $nonVideoDir = Join-Path $script:tempDir 'non-video'
            New-Item -Path $nonVideoDir -ItemType Directory -Force | Out-Null

            # Create large files with non-video extensions
            $txtPath = Join-Path $nonVideoDir 'large.txt'
            $fs = [System.IO.File]::Create($txtPath)
            $fs.SetLength(200MB)
            $fs.Close()

            InModuleScope ReScenePS -Parameters @{ path = $nonVideoDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $false
            }
        }
    }

    Context 'File size filtering' {
        It 'Returns false for sample-sized files (< 100MB) regardless of name' {
            $sampleDir = Join-Path $script:tempDir 'sample-size'
            New-Item -Path $sampleDir -ItemType Directory -Force | Out-Null

            # 50MB is typical scene sample size - should be excluded
            $samplePath = Join-Path $sampleDir 'movie.mkv'
            $fs = [System.IO.File]::Create($samplePath)
            $fs.SetLength(50MB)
            $fs.Close()

            InModuleScope ReScenePS -Parameters @{ path = $sampleDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $false
            }
        }

        It 'Returns true for files at exactly 100MB threshold' {
            $thresholdDir = Join-Path $script:tempDir 'threshold-test'
            New-Item -Path $thresholdDir -ItemType Directory -Force | Out-Null

            $videoPath = Join-Path $thresholdDir 'movie.mkv'
            $fs = [System.IO.File]::Create($videoPath)
            $fs.SetLength(100MB)
            $fs.Close()

            InModuleScope ReScenePS -Parameters @{ path = $thresholdDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $true
            }
        }
    }

    Context 'Mixed content' {
        It 'Returns true when directory has both sample and main video file' {
            $mixedDir = Join-Path $script:tempDir 'mixed-content'
            New-Item -Path $mixedDir -ItemType Directory -Force | Out-Null

            # Create sample file
            $samplePath = Join-Path $mixedDir 'movie-sample.mkv'
            $fs = [System.IO.File]::Create($samplePath)
            $fs.SetLength(50MB)
            $fs.Close()

            # Create main video file
            $mainPath = Join-Path $mixedDir 'movie.mkv'
            $fs = [System.IO.File]::Create($mainPath)
            $fs.SetLength(500MB)
            $fs.Close()

            InModuleScope ReScenePS -Parameters @{ path = $mixedDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $true
            }
        }

        It 'Returns true when directory has small sample and SRR file' {
            $srrAndSampleDir = Join-Path $script:tempDir 'srr-and-sample'
            New-Item -Path $srrAndSampleDir -ItemType Directory -Force | Out-Null

            # Create sample file
            $samplePath = Join-Path $srrAndSampleDir 'sample.mkv'
            $fs = [System.IO.File]::Create($samplePath)
            $fs.SetLength(50MB)
            $fs.Close()

            # Create SRR file
            New-MinimalSrrFile -Path (Join-Path $srrAndSampleDir 'release.srr')

            InModuleScope ReScenePS -Parameters @{ path = $srrAndSampleDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $true
            }
        }
    }

    Context 'Non-recursive behavior' {
        It 'Does not find video files in subdirectories' {
            $parentDir = Join-Path $script:tempDir 'parent-dir'
            $childDir = Join-Path $parentDir 'child-dir'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            # Create large video in child directory only
            $videoPath = Join-Path $childDir 'movie.mkv'
            $fs = [System.IO.File]::Create($videoPath)
            $fs.SetLength(100MB)
            $fs.Close()

            # Parent should return false (no files directly in it)
            InModuleScope ReScenePS -Parameters @{ path = $parentDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $false
            }

            # Child should return true
            InModuleScope ReScenePS -Parameters @{ path = $childDir } {
                param($path)
                Test-RebuildableDirectory -Path $path | Should -Be $true
            }
        }
    }
}
