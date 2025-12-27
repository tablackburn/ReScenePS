#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for BlockType enum.

.DESCRIPTION
    Verifies that BlockType enum values match the SRR/RAR specification.
    These hex values are defined by the file format and must not change.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'BlockType Enum' {

    Context 'SRR block types' {
        It 'Defines SRR Header as 0x69' {
            InModuleScope 'ReScenePS' {
                [BlockType]::SrrHeader.value__ | Should -Be 0x69
            }
        }

        It 'Defines SRR Stored File as 0x6A' {
            InModuleScope 'ReScenePS' {
                [BlockType]::SrrStoredFile.value__ | Should -Be 0x6A
            }
        }

        It 'Defines SRR RAR File as 0x71' {
            InModuleScope 'ReScenePS' {
                [BlockType]::SrrRarFile.value__ | Should -Be 0x71
            }
        }
    }

    Context 'RAR block types' {
        It 'Defines RAR Marker as 0x72' {
            InModuleScope 'ReScenePS' {
                [BlockType]::RarMarker.value__ | Should -Be 0x72
            }
        }

        It 'Defines RAR Volume Header as 0x73' {
            InModuleScope 'ReScenePS' {
                [BlockType]::RarVolumeHeader.value__ | Should -Be 0x73
            }
        }

        It 'Defines RAR Packed File as 0x74' {
            InModuleScope 'ReScenePS' {
                [BlockType]::RarPackedFile.value__ | Should -Be 0x74
            }
        }

        It 'Defines RAR Archive End as 0x7B' {
            InModuleScope 'ReScenePS' {
                [BlockType]::RarArchiveEnd.value__ | Should -Be 0x7B
            }
        }
    }
}
