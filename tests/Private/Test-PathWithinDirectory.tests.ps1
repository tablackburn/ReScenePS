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
}

Describe 'Test-PathWithinDirectory' {

    Context 'Valid paths within directory' {
        It 'Returns true for path directly in base directory' {
            InModuleScope ReScenePS {
                $base = 'C:\Output'
                $path = 'C:\Output\file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $true
            }
        }

        It 'Returns true for path in subdirectory of base' {
            InModuleScope ReScenePS {
                $base = 'C:\Output'
                $path = 'C:\Output\subdir\file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $true
            }
        }

        It 'Returns true for deeply nested path' {
            InModuleScope ReScenePS {
                $base = 'C:\Output'
                $path = 'C:\Output\a\b\c\d\e\file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $true
            }
        }

        It 'Returns true when path equals base directory' {
            InModuleScope ReScenePS {
                $base = 'C:\Output'
                $path = 'C:\Output'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $true
            }
        }
    }

    Context 'Path traversal attempts' {
        It 'Returns false for path traversal with ..' {
            InModuleScope ReScenePS {
                $base = 'C:\Output'
                $path = 'C:\Output\..\Other\file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $false
            }
        }

        It 'Returns false for path completely outside base' {
            InModuleScope ReScenePS {
                $base = 'C:\Output'
                $path = 'C:\Other\file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $false
            }
        }

        It 'Returns false for sibling directory with similar prefix' {
            InModuleScope ReScenePS {
                # This tests the separator suffix check - "C:\OutputMalicious" should not
                # match base "C:\Output" even though it starts with the same characters
                $base = 'C:\Output'
                $path = 'C:\OutputMalicious\file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $false
            }
        }

        It 'Returns false for complex traversal attempt' {
            InModuleScope ReScenePS {
                $base = 'C:\Output'
                $path = 'C:\Output\subdir\..\..\..\..\Windows\System32\file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $false
            }
        }
    }

    Context 'Case sensitivity' {
        It 'Handles case-insensitive comparison on Windows' {
            InModuleScope ReScenePS {
                $base = 'C:\Output'
                $path = 'C:\OUTPUT\SubDir\file.txt'
                # On Windows, paths are case-insensitive
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $true
            }
        }
    }

    Context 'Path normalization' {
        It 'Normalizes paths with . components' {
            InModuleScope ReScenePS {
                $base = 'C:\Output'
                $path = 'C:\Output\.\subdir\.\file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $true
            }
        }

        It 'Handles trailing separators in base directory' {
            InModuleScope ReScenePS {
                $base = 'C:\Output\'
                $path = 'C:\Output\file.txt'
                Test-PathWithinDirectory -Path $path -BaseDirectory $base | Should -Be $true
            }
        }
    }
}
