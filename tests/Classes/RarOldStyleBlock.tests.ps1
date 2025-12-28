#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for RarOldStyleBlock class.

.DESCRIPTION
    Tests the 0x75-0x79 old-style RAR block parsing for legacy archives.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'RarOldStyleBlock' {

    Context 'Block type identification' {
        It 'Identifies OldComment block (0x75)' {
            InModuleScope 'ReScenePS' {
                $blockData = [byte[]]@(
                    0x00, 0x00,  # CRC
                    0x75,        # HEAD_TYPE = OldComment
                    0x00, 0x00,  # HEAD_FLAGS
                    0x07, 0x00   # HEAD_SIZE = 7
                )

                $stream = [System.IO.MemoryStream]::new($blockData)
                $reader = [System.IO.BinaryReader]::new($stream)
                $block = [RarOldStyleBlock]::new($reader, 0)

                $block.HeadType | Should -Be 0x75
                $block.BlockTypeName | Should -Be 'OldComment'
            }
        }

        It 'Identifies OldAuthenticity block (0x76)' {
            InModuleScope 'ReScenePS' {
                $blockData = [byte[]]@(
                    0x00, 0x00, 0x76, 0x00, 0x00, 0x07, 0x00
                )

                $stream = [System.IO.MemoryStream]::new($blockData)
                $reader = [System.IO.BinaryReader]::new($stream)
                $block = [RarOldStyleBlock]::new($reader, 0)

                $block.BlockTypeName | Should -Be 'OldAuthenticity'
            }
        }

        It 'Identifies OldSubblock block (0x77)' {
            InModuleScope 'ReScenePS' {
                $blockData = [byte[]]@(
                    0x00, 0x00, 0x77, 0x00, 0x00, 0x07, 0x00
                )

                $stream = [System.IO.MemoryStream]::new($blockData)
                $reader = [System.IO.BinaryReader]::new($stream)
                $block = [RarOldStyleBlock]::new($reader, 0)

                $block.BlockTypeName | Should -Be 'OldSubblock'
            }
        }

        It 'Identifies OldRecovery block (0x78)' {
            InModuleScope 'ReScenePS' {
                $blockData = [byte[]]@(
                    0x00, 0x00, 0x78, 0x00, 0x00, 0x07, 0x00
                )

                $stream = [System.IO.MemoryStream]::new($blockData)
                $reader = [System.IO.BinaryReader]::new($stream)
                $block = [RarOldStyleBlock]::new($reader, 0)

                $block.BlockTypeName | Should -Be 'OldRecovery'
            }
        }

        It 'Identifies OldAuthenticity2 block (0x79)' {
            InModuleScope 'ReScenePS' {
                $blockData = [byte[]]@(
                    0x00, 0x00, 0x79, 0x00, 0x00, 0x07, 0x00
                )

                $stream = [System.IO.MemoryStream]::new($blockData)
                $reader = [System.IO.BinaryReader]::new($stream)
                $block = [RarOldStyleBlock]::new($reader, 0)

                $block.BlockTypeName | Should -Be 'OldAuthenticity2'
            }
        }
    }

    Context 'GetBlockBytes' {
        It 'Returns complete block bytes' {
            InModuleScope 'ReScenePS' {
                $blockData = [byte[]]@(
                    0xAB, 0xCD,  # CRC
                    0x78,        # HEAD_TYPE
                    0x12, 0x34,  # HEAD_FLAGS
                    0x0A, 0x00,  # HEAD_SIZE = 10
                    0x01, 0x02, 0x03  # Raw data
                )

                $stream = [System.IO.MemoryStream]::new($blockData)
                $reader = [System.IO.BinaryReader]::new($stream)
                $block = [RarOldStyleBlock]::new($reader, 0)

                $result = $block.GetBlockBytes()
                $result.Length | Should -Be 10
                $result[0] | Should -Be 0xAB  # CRC preserved
                $result[1] | Should -Be 0xCD
                $result[2] | Should -Be 0x78  # HEAD_TYPE preserved
            }
        }
    }

    Context 'Block with raw data' {
        It 'Handles blocks with additional raw data' {
            InModuleScope 'ReScenePS' {
                $blockData = [byte[]]@(
                    0x00, 0x00, 0x75, 0x00, 0x00, 0x10, 0x00,
                    # 9 bytes of raw data
                    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09
                )

                $stream = [System.IO.MemoryStream]::new($blockData)
                $reader = [System.IO.BinaryReader]::new($stream)
                $block = [RarOldStyleBlock]::new($reader, 0)

                $block.RawData.Length | Should -Be 9
                $block.HeadSize | Should -Be 16
            }
        }
    }
}
