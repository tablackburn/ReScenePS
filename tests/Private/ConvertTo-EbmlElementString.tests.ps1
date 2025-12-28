#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for ConvertTo-EbmlElementString function.

.DESCRIPTION
    Tests conversion of EBML element IDs to hex string representation.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'ConvertTo-EbmlElementString' {

    Context 'Single-byte element IDs' {
        It 'Converts single-byte ID correctly' {
            InModuleScope 'ReScenePS' {
                ConvertTo-EbmlElementString -ElementID @(0x1A) | Should -Be '0x1A'
            }
        }

        It 'Pads single-digit hex values' {
            InModuleScope 'ReScenePS' {
                ConvertTo-EbmlElementString -ElementID @(0x0F) | Should -Be '0x0F'
            }
        }
    }

    Context 'Multi-byte element IDs' {
        It 'Converts two-byte ID correctly' {
            InModuleScope 'ReScenePS' {
                ConvertTo-EbmlElementString -ElementID @(0x42, 0x86) | Should -Be '0x4286'
            }
        }

        It 'Converts three-byte ID correctly' {
            InModuleScope 'ReScenePS' {
                ConvertTo-EbmlElementString -ElementID @(0x1A, 0x45, 0xDF) | Should -Be '0x1A45DF'
            }
        }

        It 'Converts four-byte ID correctly' {
            InModuleScope 'ReScenePS' {
                # EBML header ID
                ConvertTo-EbmlElementString -ElementID @(0x1A, 0x45, 0xDF, 0xA3) | Should -Be '0x1A45DFA3'
            }
        }
    }

    Context 'Known MKV element IDs' {
        It 'Converts EBML header ID (0x1A45DFA3)' {
            InModuleScope 'ReScenePS' {
                $ebmlId = [byte[]]@(0x1A, 0x45, 0xDF, 0xA3)
                ConvertTo-EbmlElementString -ElementID $ebmlId | Should -Be '0x1A45DFA3'
            }
        }

        It 'Converts Segment ID (0x18538067)' {
            InModuleScope 'ReScenePS' {
                $segmentId = [byte[]]@(0x18, 0x53, 0x80, 0x67)
                ConvertTo-EbmlElementString -ElementID $segmentId | Should -Be '0x18538067'
            }
        }

        It 'Converts Track UID ID (0x73C5)' {
            InModuleScope 'ReScenePS' {
                $trackUidId = [byte[]]@(0x73, 0xC5)
                ConvertTo-EbmlElementString -ElementID $trackUidId | Should -Be '0x73C5'
            }
        }
    }

    Context 'Edge cases' {
        It 'Handles all-zero bytes' {
            InModuleScope 'ReScenePS' {
                ConvertTo-EbmlElementString -ElementID @(0x00, 0x00) | Should -Be '0x0000'
            }
        }

        It 'Handles all-FF bytes' {
            InModuleScope 'ReScenePS' {
                ConvertTo-EbmlElementString -ElementID @(0xFF, 0xFF) | Should -Be '0xFFFF'
            }
        }
    }
}
