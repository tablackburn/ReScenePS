#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for RarNewSubBlock class.

.DESCRIPTION
    Tests the 0x7A new-style subblock parsing for recovery records,
    comments, and authenticity verification blocks.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'RarNewSubBlock' {

    Context 'Block instantiation' {
        It 'Can be instantiated with valid data' {
            InModuleScope 'ReScenePS' {
                # Create a minimal valid RarNewSub block in memory
                # HEAD_CRC(2) + HEAD_TYPE(1) + HEAD_FLAGS(2) + HEAD_SIZE(2) + data
                $blockData = [byte[]]@(
                    0x00, 0x00,           # CRC (placeholder)
                    0x7A,                 # HEAD_TYPE = RarNewSub
                    0x00, 0x80,           # HEAD_FLAGS with ADD_SIZE
                    0x24, 0x00,           # HEAD_SIZE = 36 bytes
                    # RawData (29 bytes after header)
                    0x00, 0x00, 0x00, 0x00,  # DataSize
                    0x00, 0x00, 0x00, 0x00,  # UnpackedSize
                    0x00,                     # HostOs
                    0x00, 0x00, 0x00, 0x00,  # DataCrc
                    0x00, 0x00, 0x00, 0x00,  # FileDateTime
                    0x00,                     # UnpackVersion
                    0x00,                     # Method
                    0x02, 0x00,              # NameSize = 2
                    0x00, 0x00, 0x00, 0x00,  # Attributes
                    0x52, 0x52                # SubType = "RR" (Recovery Record)
                )

                $stream = [System.IO.MemoryStream]::new($blockData)
                $reader = [System.IO.BinaryReader]::new($stream)

                $block = [RarNewSubBlock]::new($reader, 0)

                $block.HeadType | Should -Be 0x7A
                $block.SubType | Should -Be 'RR'
            }
        }
    }

    Context 'SubType identification' {
        It 'Identifies Recovery Record subtype' {
            InModuleScope 'ReScenePS' {
                $blockData = [byte[]]@(
                    0x00, 0x00, 0x7A, 0x00, 0x80, 0x24, 0x00,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0x52, 0x52  # "RR"
                )

                $stream = [System.IO.MemoryStream]::new($blockData)
                $reader = [System.IO.BinaryReader]::new($stream)
                $block = [RarNewSubBlock]::new($reader, 0)

                $block.SubType | Should -Be 'RR'
            }
        }

        It 'Identifies Comment subtype' {
            InModuleScope 'ReScenePS' {
                $blockData = [byte[]]@(
                    0x00, 0x00, 0x7A, 0x00, 0x80, 0x25, 0x00,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0x43, 0x4D, 0x54  # "CMT"
                )

                $stream = [System.IO.MemoryStream]::new($blockData)
                $reader = [System.IO.BinaryReader]::new($stream)
                $block = [RarNewSubBlock]::new($reader, 0)

                $block.SubType | Should -Be 'CMT'
            }
        }
    }

    Context 'GetBlockBytes' {
        It 'Returns correct block bytes' {
            InModuleScope 'ReScenePS' {
                $blockData = [byte[]]@(
                    0xAB, 0xCD, 0x7A, 0x00, 0x80, 0x09, 0x00,
                    0x01, 0x02  # 2 bytes of raw data
                )

                $stream = [System.IO.MemoryStream]::new($blockData)
                $reader = [System.IO.BinaryReader]::new($stream)
                $block = [RarNewSubBlock]::new($reader, 0)

                $result = $block.GetBlockBytes()
                $result.Length | Should -Be $block.HeadSize
                $result[2] | Should -Be 0x7A  # HEAD_TYPE preserved
            }
        }
    }
}
