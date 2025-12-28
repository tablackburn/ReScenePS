#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Read-EbmlUIntStream function.

.DESCRIPTION
    Tests reading EBML variable-length unsigned integers from a stream.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'Read-EbmlUIntStream' {

    Context 'Single-byte values' {
        It 'Reads 0x81 as value 1' {
            InModuleScope 'ReScenePS' {
                $stream = [System.IO.MemoryStream]::new([byte[]]@(0x81))
                $result = Read-EbmlUIntStream -Stream $stream
                $result.Value | Should -Be 1
                $result.BytesConsumed | Should -Be 1
            }
        }

        It 'Reads 0xFF as value 127' {
            InModuleScope 'ReScenePS' {
                $stream = [System.IO.MemoryStream]::new([byte[]]@(0xFF))
                $result = Read-EbmlUIntStream -Stream $stream
                $result.Value | Should -Be 127
                $result.BytesConsumed | Should -Be 1
            }
        }

        It 'Reads 0x80 as value 0' {
            InModuleScope 'ReScenePS' {
                $stream = [System.IO.MemoryStream]::new([byte[]]@(0x80))
                $result = Read-EbmlUIntStream -Stream $stream
                $result.Value | Should -Be 0
                $result.BytesConsumed | Should -Be 1
            }
        }
    }

    Context 'Two-byte values' {
        It 'Reads 0x40 0x01 as value 1' {
            InModuleScope 'ReScenePS' {
                $stream = [System.IO.MemoryStream]::new([byte[]]@(0x40, 0x01))
                $result = Read-EbmlUIntStream -Stream $stream
                $result.Value | Should -Be 1
                $result.BytesConsumed | Should -Be 2
            }
        }

        It 'Reads 0x41 0x00 as value 256' {
            InModuleScope 'ReScenePS' {
                $stream = [System.IO.MemoryStream]::new([byte[]]@(0x41, 0x00))
                $result = Read-EbmlUIntStream -Stream $stream
                $result.Value | Should -Be 256
                $result.BytesConsumed | Should -Be 2
            }
        }

        It 'Reads 0x7F 0xFF as value 16383' {
            InModuleScope 'ReScenePS' {
                $stream = [System.IO.MemoryStream]::new([byte[]]@(0x7F, 0xFF))
                $result = Read-EbmlUIntStream -Stream $stream
                $result.Value | Should -Be 16383
                $result.BytesConsumed | Should -Be 2
            }
        }
    }

    Context 'Three-byte values' {
        It 'Reads 0x20 0x00 0x01 as value 1' {
            InModuleScope 'ReScenePS' {
                $stream = [System.IO.MemoryStream]::new([byte[]]@(0x20, 0x00, 0x01))
                $result = Read-EbmlUIntStream -Stream $stream
                $result.Value | Should -Be 1
                $result.BytesConsumed | Should -Be 3
            }
        }

        It 'Reads 0x21 0x00 0x00 as value 65536' {
            InModuleScope 'ReScenePS' {
                $stream = [System.IO.MemoryStream]::new([byte[]]@(0x21, 0x00, 0x00))
                $result = Read-EbmlUIntStream -Stream $stream
                $result.Value | Should -Be 65536
                $result.BytesConsumed | Should -Be 3
            }
        }
    }

    Context 'Four-byte values' {
        It 'Reads 0x10 0x00 0x00 0x01 as value 1' {
            InModuleScope 'ReScenePS' {
                $stream = [System.IO.MemoryStream]::new([byte[]]@(0x10, 0x00, 0x00, 0x01))
                $result = Read-EbmlUIntStream -Stream $stream
                $result.Value | Should -Be 1
                $result.BytesConsumed | Should -Be 4
            }
        }

        It 'Reads 0x10 0x20 0x00 0x00 as value 2097152' {
            InModuleScope 'ReScenePS' {
                $stream = [System.IO.MemoryStream]::new([byte[]]@(0x10, 0x20, 0x00, 0x00))
                $result = Read-EbmlUIntStream -Stream $stream
                $result.Value | Should -Be 2097152
                $result.BytesConsumed | Should -Be 4
            }
        }
    }

    Context 'Stream position advancement' {
        It 'Advances stream position correctly for multi-byte reads' {
            InModuleScope 'ReScenePS' {
                $data = [byte[]]@(0x41, 0x00, 0x82, 0x83)  # Two values: 256 (2 bytes), then 2 (1 byte)
                $stream = [System.IO.MemoryStream]::new($data)

                $result1 = Read-EbmlUIntStream -Stream $stream
                $result1.Value | Should -Be 256
                $stream.Position | Should -Be 2

                $result2 = Read-EbmlUIntStream -Stream $stream
                $result2.Value | Should -Be 2
                $stream.Position | Should -Be 3
            }
        }
    }
}
