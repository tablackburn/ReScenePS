#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Compare-ByteArray function.

.DESCRIPTION
    Tests byte array comparison for equality checking.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'Compare-ByteArray' {

    Context 'Equal arrays' {
        It 'Returns true for identical single-byte arrays' {
            InModuleScope 'ReScenePS' {
                Compare-ByteArray -Array1 @(0x42) -Array2 @(0x42) | Should -BeTrue
            }
        }

        It 'Returns true for identical multi-byte arrays' {
            InModuleScope 'ReScenePS' {
                $a = [byte[]]@(0x52, 0x61, 0x72, 0x21)
                $b = [byte[]]@(0x52, 0x61, 0x72, 0x21)
                Compare-ByteArray -Array1 $a -Array2 $b | Should -BeTrue
            }
        }

        It 'Returns true for empty arrays' {
            InModuleScope 'ReScenePS' {
                Compare-ByteArray -Array1 @() -Array2 @() | Should -BeTrue
            }
        }

        It 'Returns true for large identical arrays' {
            InModuleScope 'ReScenePS' {
                $a = [byte[]](0..255)
                $b = [byte[]](0..255)
                Compare-ByteArray -Array1 $a -Array2 $b | Should -BeTrue
            }
        }
    }

    Context 'Different arrays' {
        It 'Returns false for arrays with different lengths' {
            InModuleScope 'ReScenePS' {
                Compare-ByteArray -Array1 @(0x01, 0x02) -Array2 @(0x01) | Should -BeFalse
            }
        }

        It 'Returns false for arrays with different content' {
            InModuleScope 'ReScenePS' {
                Compare-ByteArray -Array1 @(0x01, 0x02) -Array2 @(0x01, 0x03) | Should -BeFalse
            }
        }

        It 'Returns false when first byte differs' {
            InModuleScope 'ReScenePS' {
                Compare-ByteArray -Array1 @(0xFF, 0x02, 0x03) -Array2 @(0x00, 0x02, 0x03) | Should -BeFalse
            }
        }

        It 'Returns false when last byte differs' {
            InModuleScope 'ReScenePS' {
                Compare-ByteArray -Array1 @(0x01, 0x02, 0x03) -Array2 @(0x01, 0x02, 0xFF) | Should -BeFalse
            }
        }

        It 'Returns false for empty vs non-empty array' {
            InModuleScope 'ReScenePS' {
                Compare-ByteArray -Array1 @() -Array2 @(0x00) | Should -BeFalse
            }
        }
    }

    Context 'Edge cases' {
        It 'Handles all zeros' {
            InModuleScope 'ReScenePS' {
                $a = [byte[]]@(0x00, 0x00, 0x00)
                $b = [byte[]]@(0x00, 0x00, 0x00)
                Compare-ByteArray -Array1 $a -Array2 $b | Should -BeTrue
            }
        }

        It 'Handles all 0xFF bytes' {
            InModuleScope 'ReScenePS' {
                $a = [byte[]]@(0xFF, 0xFF, 0xFF)
                $b = [byte[]]@(0xFF, 0xFF, 0xFF)
                Compare-ByteArray -Array1 $a -Array2 $b | Should -BeTrue
            }
        }
    }
}
