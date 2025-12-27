#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Get-EbmlUInt function.

.DESCRIPTION
    Tests the EBML variable-length unsigned integer decoding.
    The first byte contains length descriptor bits that must be masked out
    before interpreting the value. ByteCount must be provided (from Get-EbmlUIntLength).
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'Get-EbmlUInt' {

    Context 'Single-byte decoding' {
        It 'Decodes 0x81 as value 1' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUInt -Buffer @(0x81) -Offset 0 -ByteCount 1 | Should -Be 1
            }
        }

        It 'Decodes 0x82 as value 2' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUInt -Buffer @(0x82) -Offset 0 -ByteCount 1 | Should -Be 2
            }
        }

        It 'Decodes 0xFF as value 127' {
            InModuleScope 'ReScenePS' {
                # 0xFF = 1|1111111, mask off leading 1 = 0x7F = 127
                Get-EbmlUInt -Buffer @(0xFF) -Offset 0 -ByteCount 1 | Should -Be 127
            }
        }

        It 'Decodes 0x80 as value 0' {
            InModuleScope 'ReScenePS' {
                # 0x80 = 1|0000000, mask off leading 1 = 0x00 = 0
                Get-EbmlUInt -Buffer @(0x80) -Offset 0 -ByteCount 1 | Should -Be 0
            }
        }
    }

    Context 'Two-byte decoding' {
        It 'Decodes 0x40 0x01 as value 1' {
            InModuleScope 'ReScenePS' {
                # 01|000000 00000001 -> mask = 0x3FFF, value = 0x0001 = 1
                Get-EbmlUInt -Buffer @(0x40, 0x01) -Offset 0 -ByteCount 2 | Should -Be 1
            }
        }

        It 'Decodes 0x41 0x00 as value 256' {
            InModuleScope 'ReScenePS' {
                # 01|000001 00000000 -> 0x0100 = 256
                Get-EbmlUInt -Buffer @(0x41, 0x00) -Offset 0 -ByteCount 2 | Should -Be 256
            }
        }

        It 'Decodes 0x7F 0xFF as value 16383' {
            InModuleScope 'ReScenePS' {
                # 01|111111 11111111 -> 0x3FFF = 16383
                Get-EbmlUInt -Buffer @(0x7F, 0xFF) -Offset 0 -ByteCount 2 | Should -Be 16383
            }
        }
    }

    Context 'Three-byte decoding' {
        It 'Decodes 0x20 0x00 0x01 as value 1' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUInt -Buffer @(0x20, 0x00, 0x01) -Offset 0 -ByteCount 3 | Should -Be 1
            }
        }

        It 'Decodes 0x21 0x00 0x00 as value 65536' {
            InModuleScope 'ReScenePS' {
                # 001|00001 00000000 00000000 -> 0x010000 = 65536
                Get-EbmlUInt -Buffer @(0x21, 0x00, 0x00) -Offset 0 -ByteCount 3 | Should -Be 65536
            }
        }
    }

    Context 'Four-byte decoding' {
        It 'Decodes 0x10 0x00 0x00 0x01 as value 1' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUInt -Buffer @(0x10, 0x00, 0x00, 0x01) -Offset 0 -ByteCount 4 | Should -Be 1
            }
        }

        It 'Decodes 0x10 0x20 0x00 0x00 as value 2097152' {
            InModuleScope 'ReScenePS' {
                # 0001|0000 00100000 00000000 00000000 -> 0x00200000 = 2097152
                Get-EbmlUInt -Buffer @(0x10, 0x20, 0x00, 0x00) -Offset 0 -ByteCount 4 | Should -Be 2097152
            }
        }
    }

    Context 'Reading from offset' {
        It 'Reads correctly from non-zero offset' {
            InModuleScope 'ReScenePS' {
                # Padding bytes, then 0x82 at offset 3
                Get-EbmlUInt -Buffer @(0x00, 0x00, 0x00, 0x82) -Offset 3 -ByteCount 1 | Should -Be 2
            }
        }

        It 'Reads two bytes from middle of buffer' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUInt -Buffer @(0xFF, 0x41, 0x00, 0xFF) -Offset 1 -ByteCount 2 | Should -Be 256
            }
        }
    }
}
