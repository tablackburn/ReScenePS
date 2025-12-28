#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for ConvertTo-ByteString function.

.DESCRIPTION
    Tests byte array to hex string conversion for display purposes.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'ConvertTo-ByteString' {

    Context 'Basic conversion' {
        It 'Converts single byte to two-character hex string' {
            InModuleScope 'ReScenePS' {
                ConvertTo-ByteString -Bytes @(0x42) | Should -Be '42'
            }
        }

        It 'Converts multiple bytes to concatenated hex string' {
            InModuleScope 'ReScenePS' {
                ConvertTo-ByteString -Bytes @(0x52, 0x61, 0x72, 0x21) | Should -Be '52617221'
            }
        }

        It 'Returns empty string for empty array' {
            InModuleScope 'ReScenePS' {
                ConvertTo-ByteString -Bytes @() | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Formatting' {
        It 'Uses uppercase hex characters' {
            InModuleScope 'ReScenePS' {
                ConvertTo-ByteString -Bytes @(0xAB, 0xCD, 0xEF) | Should -Be 'ABCDEF'
            }
        }

        It 'Pads single-digit hex values with leading zero' {
            InModuleScope 'ReScenePS' {
                ConvertTo-ByteString -Bytes @(0x01, 0x0F) | Should -Be '010F'
            }
        }

        It 'Handles 0x00 correctly' {
            InModuleScope 'ReScenePS' {
                ConvertTo-ByteString -Bytes @(0x00) | Should -Be '00'
            }
        }

        It 'Handles 0xFF correctly' {
            InModuleScope 'ReScenePS' {
                ConvertTo-ByteString -Bytes @(0xFF) | Should -Be 'FF'
            }
        }
    }

    Context 'RAR marker signature' {
        It 'Converts RAR marker bytes correctly' {
            InModuleScope 'ReScenePS' {
                # RAR marker: Rar!
                $marker = [byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00)
                ConvertTo-ByteString -Bytes $marker | Should -Be '526172211A0700'
            }
        }
    }

    Context 'Typical CRC values' {
        It 'Converts typical CRC32 bytes' {
            InModuleScope 'ReScenePS' {
                # DEADBEEF as bytes
                $crc = [byte[]]@(0xDE, 0xAD, 0xBE, 0xEF)
                ConvertTo-ByteString -Bytes $crc | Should -Be 'DEADBEEF'
            }
        }
    }
}
