#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Get-EbmlElementFromBuffer function.

.DESCRIPTION
    Tests reading complete EBML elements (ID + size + data) from a buffer.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'Get-EbmlElementFromBuffer' {

    Context 'Simple single-byte elements' {
        It 'Reads element with 1-byte ID, 1-byte size, and data' {
            InModuleScope 'ReScenePS' {
                # Element: ID=0xEC (void), Size=0x82 (2 bytes), Data=0xAB 0xCD
                $buffer = [byte[]]@(0xEC, 0x82, 0xAB, 0xCD)
                $result = Get-EbmlElementFromBuffer -Buffer $buffer -Offset 0

                $result.ElementID | Should -Be @(0xEC)
                $result.DataSize | Should -Be 2
                $result.ElementData | Should -Be @(0xAB, 0xCD)
                $result.TotalLength | Should -Be 4
            }
        }

        It 'Reads element with zero data size' {
            InModuleScope 'ReScenePS' {
                # Element: ID=0xEC (void), Size=0x80 (0 bytes)
                $buffer = [byte[]]@(0xEC, 0x80)
                $result = Get-EbmlElementFromBuffer -Buffer $buffer -Offset 0

                $result.ElementID | Should -Be @(0xEC)
                $result.DataSize | Should -Be 0
                $result.ElementData.Length | Should -Be 0
                $result.TotalLength | Should -Be 2
            }
        }
    }

    Context 'Multi-byte element IDs' {
        It 'Reads element with 2-byte ID' {
            InModuleScope 'ReScenePS' {
                # Element: ID=0x42 0x86 (EBMLVersion), Size=0x81 (1 byte), Data=0x01
                $buffer = [byte[]]@(0x42, 0x86, 0x81, 0x01)
                $result = Get-EbmlElementFromBuffer -Buffer $buffer -Offset 0

                $result.ElementID | Should -Be @(0x42, 0x86)
                $result.DataSize | Should -Be 1
                $result.ElementData | Should -Be @(0x01)
                $result.TotalLength | Should -Be 4
            }
        }

        It 'Reads element with 4-byte ID' {
            InModuleScope 'ReScenePS' {
                # Element: ID=0x1A 0x45 0xDF 0xA3 (EBML header), Size=0x82 (2), Data=0xFF 0x00
                $buffer = [byte[]]@(0x1A, 0x45, 0xDF, 0xA3, 0x82, 0xFF, 0x00)
                $result = Get-EbmlElementFromBuffer -Buffer $buffer -Offset 0

                $result.ElementID | Should -Be @(0x1A, 0x45, 0xDF, 0xA3)
                $result.DataSize | Should -Be 2
                $result.ElementData | Should -Be @(0xFF, 0x00)
                $result.TotalLength | Should -Be 7
            }
        }
    }

    Context 'Reading from offset' {
        It 'Reads element correctly from non-zero offset' {
            InModuleScope 'ReScenePS' {
                # Padding (3 bytes) + Element: ID=0xEC, Size=0x81 (1), Data=0x42
                $buffer = [byte[]]@(0x00, 0x00, 0x00, 0xEC, 0x81, 0x42)
                $result = Get-EbmlElementFromBuffer -Buffer $buffer -Offset 3

                $result.ElementID | Should -Be @(0xEC)
                $result.DataSize | Should -Be 1
                $result.ElementData | Should -Be @(0x42)
                $result.TotalLength | Should -Be 3
            }
        }
    }

    Context 'Two-byte size values' {
        It 'Reads element with 2-byte size encoding' {
            InModuleScope 'ReScenePS' {
                # Element: ID=0xEC, Size=0x40 0x80 (128 bytes), Data=128 bytes of 0xFF
                $data = [byte[]]::new(128)
                for ($i = 0; $i -lt 128; $i++) { $data[$i] = 0xFF }
                $header = [byte[]]@(0xEC, 0x40, 0x80)
                $buffer = $header + $data

                $result = Get-EbmlElementFromBuffer -Buffer $buffer -Offset 0

                $result.ElementID | Should -Be @(0xEC)
                $result.DataSize | Should -Be 128
                $result.ElementData.Length | Should -Be 128
                $result.TotalLength | Should -Be 131  # 1 (ID) + 2 (size) + 128 (data)
            }
        }
    }

    Context 'Buffer boundary handling' {
        It 'Truncates data when buffer is shorter than declared size' {
            InModuleScope 'ReScenePS' {
                # Declare size of 10 but only provide 3 bytes of data
                $buffer = [byte[]]@(0xEC, 0x8A, 0x01, 0x02, 0x03)  # Size=10, but only 3 data bytes
                $result = Get-EbmlElementFromBuffer -Buffer $buffer -Offset 0

                $result.DataSize | Should -Be 3  # Truncated to available data
                $result.ElementData.Length | Should -Be 3
            }
        }
    }
}
