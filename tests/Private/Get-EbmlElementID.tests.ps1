#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Get-EbmlElementID function.

.DESCRIPTION
    Tests EBML Element ID parsing. Element IDs use the same variable-length
    encoding as size fields, where the leading bit position indicates byte count.
    Returns a hashtable with ElementID (byte array) and Length properties.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'Get-EbmlElementID' {

    Context 'Single-byte Element IDs' {
        It 'Reads single-byte ID correctly' {
            InModuleScope 'ReScenePS' {
                # Class A ID (1xxx xxxx)
                $result = Get-EbmlElementID -Buffer @(0xBF) -Offset 0
                $result.Length | Should -Be 1
                $result.ElementID[0] | Should -Be 0xBF
            }
        }

        It 'Reads EBML header ID (0x1A45DFA3)' {
            InModuleScope 'ReScenePS' {
                # Four-byte EBML header ID
                $result = Get-EbmlElementID -Buffer @(0x1A, 0x45, 0xDF, 0xA3) -Offset 0
                $result.Length | Should -Be 4
                $result.ElementID[0] | Should -Be 0x1A
                $result.ElementID[1] | Should -Be 0x45
                $result.ElementID[2] | Should -Be 0xDF
                $result.ElementID[3] | Should -Be 0xA3
            }
        }
    }

    Context 'Two-byte Element IDs' {
        It 'Reads two-byte ID correctly' {
            InModuleScope 'ReScenePS' {
                # Class B ID (01xx xxxx xxxx xxxx)
                $result = Get-EbmlElementID -Buffer @(0x42, 0x86) -Offset 0
                $result.Length | Should -Be 2
                $result.ElementID[0] | Should -Be 0x42
                $result.ElementID[1] | Should -Be 0x86
            }
        }
    }

    Context 'Reading from offset' {
        It 'Reads ID from non-zero offset' {
            InModuleScope 'ReScenePS' {
                $result = Get-EbmlElementID -Buffer @(0x00, 0x00, 0xBF) -Offset 2
                $result.Length | Should -Be 1
                $result.ElementID[0] | Should -Be 0xBF
            }
        }
    }
}
