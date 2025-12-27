#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Get-EbmlUIntLength function.

.DESCRIPTION
    Tests the EBML variable-length integer length detection.
    EBML uses a leading-bit encoding where the position of the first 1-bit
    indicates how many bytes the value spans.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'Get-EbmlUIntLength' {

    Context 'Single-byte values (leading bit at position 7)' {
        It 'Returns 1 for byte 0x80 (10000000)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x80 | Should -Be 1
            }
        }

        It 'Returns 1 for byte 0xFF (11111111)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0xFF | Should -Be 1
            }
        }

        It 'Returns 1 for byte 0x81 (10000001)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x81 | Should -Be 1
            }
        }
    }

    Context 'Two-byte values (leading bit at position 6)' {
        It 'Returns 2 for byte 0x40 (01000000)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x40 | Should -Be 2
            }
        }

        It 'Returns 2 for byte 0x7F (01111111)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x7F | Should -Be 2
            }
        }

        It 'Returns 2 for byte 0x4A (01001010)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x4A | Should -Be 2
            }
        }
    }

    Context 'Three-byte values (leading bit at position 5)' {
        It 'Returns 3 for byte 0x20 (00100000)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x20 | Should -Be 3
            }
        }

        It 'Returns 3 for byte 0x3F (00111111)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x3F | Should -Be 3
            }
        }
    }

    Context 'Four-byte values (leading bit at position 4)' {
        It 'Returns 4 for byte 0x10 (00010000)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x10 | Should -Be 4
            }
        }

        It 'Returns 4 for byte 0x1F (00011111)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x1F | Should -Be 4
            }
        }
    }

    Context 'Five-byte values (leading bit at position 3)' {
        It 'Returns 5 for byte 0x08 (00001000)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x08 | Should -Be 5
            }
        }

        It 'Returns 5 for byte 0x0F (00001111)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x0F | Should -Be 5
            }
        }
    }

    Context 'Six-byte values (leading bit at position 2)' {
        It 'Returns 6 for byte 0x04 (00000100)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x04 | Should -Be 6
            }
        }

        It 'Returns 6 for byte 0x07 (00000111)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x07 | Should -Be 6
            }
        }
    }

    Context 'Seven-byte values (leading bit at position 1)' {
        It 'Returns 7 for byte 0x02 (00000010)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x02 | Should -Be 7
            }
        }

        It 'Returns 7 for byte 0x03 (00000011)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x03 | Should -Be 7
            }
        }
    }

    Context 'Eight-byte values (leading bit at position 0)' {
        It 'Returns 8 for byte 0x01 (00000001)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x01 | Should -Be 8
            }
        }
    }

    Context 'Invalid input' {
        It 'Returns 0 for byte 0x00 (no leading bit set)' {
            InModuleScope 'ReScenePS' {
                Get-EbmlUIntLength -LengthDescriptor 0x00 | Should -Be 0
            }
        }
    }
}
