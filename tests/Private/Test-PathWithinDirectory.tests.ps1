#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Test-PathWithinDirectory function.

.DESCRIPTION
    Tests the private function that validates a path is within a base directory
    to prevent path traversal attacks.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    # Create cross-platform test paths using TestDrive
    $script:testBase = Join-Path $TestDrive 'Output'
    New-Item -Path $script:testBase -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $script:testBase 'subdir') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $script:testBase 'a/b/c/d/e') -ItemType Directory -Force | Out-Null

    # Create sibling directory for prefix tests
    $script:siblingDir = Join-Path $TestDrive 'OutputMalicious'
    New-Item -Path $script:siblingDir -ItemType Directory -Force | Out-Null

    # Create "Other" directory outside base for traversal tests
    $script:otherDir = Join-Path $TestDrive 'Other'
    New-Item -Path $script:otherDir -ItemType Directory -Force | Out-Null
}

Describe 'Test-PathWithinDirectory' {

    Context 'Valid paths within directory' {
        It 'Returns true for path directly in base directory' {
            InModuleScope ReScenePS -Parameters @{ base = $script:testBase } {
                param($base)
                $path = Join-Path $base 'file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $true
            }
        }

        It 'Returns true for path in subdirectory of base' {
            InModuleScope ReScenePS -Parameters @{ base = $script:testBase } {
                param($base)
                $path = Join-Path $base 'subdir/file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $true
            }
        }

        It 'Returns true for deeply nested path' {
            InModuleScope ReScenePS -Parameters @{ base = $script:testBase } {
                param($base)
                $path = Join-Path $base 'a/b/c/d/e/file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $true
            }
        }

        It 'Returns true when path equals base directory' {
            InModuleScope ReScenePS -Parameters @{ base = $script:testBase } {
                param($base)
                Test-PathWithinDirectory -Path $base -BaseDirectory $base | Should -Be $true
            }
        }
    }

    Context 'Path traversal attempts' {
        It 'Returns false for path traversal with ..' {
            InModuleScope ReScenePS -Parameters @{ base = $script:testBase; other = $script:otherDir } {
                param($base, $other)
                # Construct a path that uses .. to escape the base directory
                $path = Join-Path $base '../Other/file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $false
            }
        }

        It 'Returns false for path completely outside base' {
            InModuleScope ReScenePS -Parameters @{ base = $script:testBase; other = $script:otherDir } {
                param($base, $other)
                $path = Join-Path $other 'file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $false
            }
        }

        It 'Returns false for sibling directory with similar prefix' {
            InModuleScope ReScenePS -Parameters @{ base = $script:testBase; sibling = $script:siblingDir } {
                param($base, $sibling)
                # This tests the separator suffix check - sibling directory should not
                # match base even though it starts with the same characters
                $path = Join-Path $sibling 'file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $false
            }
        }

        It 'Returns false for complex traversal attempt' {
            InModuleScope ReScenePS -Parameters @{ base = $script:testBase } {
                param($base)
                $path = Join-Path $base 'subdir/../../../../etc/passwd'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $false
            }
        }
    }

    Context 'Path normalization' {
        It 'Normalizes paths with . components' {
            InModuleScope ReScenePS -Parameters @{ base = $script:testBase } {
                param($base)
                $path = Join-Path $base './subdir/./file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $true
            }
        }

        It 'Handles trailing separators in base directory' {
            InModuleScope ReScenePS -Parameters @{ base = $script:testBase } {
                param($base)
                $baseWithSep = $base + [System.IO.Path]::DirectorySeparatorChar
                $path = Join-Path $base 'file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $baseWithSep | Should -Be $true
            }
        }
    }
}
