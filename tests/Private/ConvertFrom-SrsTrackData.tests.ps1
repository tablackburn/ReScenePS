#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for ConvertFrom-SrsTrackData function.

.DESCRIPTION
    Tests parsing of TrackData element (0xC2) from MKV SRS files.
    Handles various flag combinations for track number and data length sizes.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'ConvertFrom-SrsTrackData' {

    Context 'Standard track data parsing' {

        It 'Parses track data with no special flags' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0)  # flags
                $bw.Write([uint16]1)  # track number (2 bytes)
                $bw.Write([uint32]50000)  # data length (4 bytes)
                $bw.Write([uint64]1024)  # match offset
                $bw.Write([uint16]4)  # signature length
                $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))  # signature

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsTrackData -Data $data

                $result.Flags | Should -Be 0
                $result.TrackNumber | Should -Be 1
                $result.DataLength | Should -Be 50000
                $result.MatchOffset | Should -Be 1024
                $result.SignatureLength | Should -Be 4
                $result.SignatureBytes.Length | Should -Be 4
            }
        }

        It 'Parses video track signature correctly' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $signature = [byte[]]@(0x00, 0x00, 0x01, 0xB3)  # MPEG sequence header

                $bw.Write([uint16]0)
                $bw.Write([uint16]1)
                $bw.Write([uint32]100000)
                $bw.Write([uint64]512)
                $bw.Write([uint16]$signature.Length)
                $bw.Write($signature)

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsTrackData -Data $data

                $result.SignatureBytes[0] | Should -Be 0x00
                $result.SignatureBytes[1] | Should -Be 0x00
                $result.SignatureBytes[2] | Should -Be 0x01
                $result.SignatureBytes[3] | Should -Be 0xB3
            }
        }
    }

    Context 'BIG_FILE flag (0x0004)' {

        It 'Handles 8-byte data length with BIG_FILE flag' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0x0004)  # BIG_FILE flag
                $bw.Write([uint16]1)  # track number (2 bytes)
                $bw.Write([uint64]5000000000)  # data length (8 bytes)
                $bw.Write([uint64]2048)  # match offset
                $bw.Write([uint16]0)  # no signature

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsTrackData -Data $data

                $result.Flags | Should -Be 0x0004
                $result.DataLength | Should -Be 5000000000
            }
        }
    }

    Context 'Large track number flag (0x0008)' {

        It 'Handles 4-byte track number with large track flag' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0x0008)  # large track number flag
                $bw.Write([uint32]70000)  # track number (4 bytes)
                $bw.Write([uint32]25000)  # data length (4 bytes)
                $bw.Write([uint64]4096)  # match offset
                $bw.Write([uint16]2)  # signature length
                $bw.Write([byte[]]@(0xAA, 0xBB))

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsTrackData -Data $data

                $result.Flags | Should -Be 0x0008
                $result.TrackNumber | Should -Be 70000
            }
        }
    }

    Context 'Combined flags' {

        It 'Handles both BIG_FILE and large track number flags' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0x000C)  # BIG_FILE | large track number
                $bw.Write([uint32]100000)  # track number (4 bytes)
                $bw.Write([uint64]10000000000)  # data length (8 bytes)
                $bw.Write([uint64]8192)  # match offset
                $bw.Write([uint16]0)  # no signature

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsTrackData -Data $data

                $result.Flags | Should -Be 0x000C
                $result.TrackNumber | Should -Be 100000
                $result.DataLength | Should -Be 10000000000
            }
        }
    }

    Context 'Signature handling' {

        It 'Handles empty signature' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0)
                $bw.Write([uint16]1)
                $bw.Write([uint32]1000)
                $bw.Write([uint64]0)
                $bw.Write([uint16]0)  # zero signature length

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsTrackData -Data $data

                $result.SignatureLength | Should -Be 0
                $result.SignatureBytes.Length | Should -Be 0
            }
        }

        It 'Handles long signature' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $signature = [byte[]]::new(256)
                for ($i = 0; $i -lt 256; $i++) { $signature[$i] = [byte]$i }

                $bw.Write([uint16]0)
                $bw.Write([uint16]2)
                $bw.Write([uint32]500000)
                $bw.Write([uint64]65536)
                $bw.Write([uint16]$signature.Length)
                $bw.Write($signature)

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsTrackData -Data $data

                $result.SignatureLength | Should -Be 256
                $result.SignatureBytes.Length | Should -Be 256
                $result.SignatureBytes[0] | Should -Be 0
                $result.SignatureBytes[255] | Should -Be 255
            }
        }
    }

    Context 'Error handling' {

        It 'Throws on data too short' {
            InModuleScope 'ReScenePS' {
                $shortData = [byte[]]@(0x00, 0x00, 0x01, 0x00)  # Only 4 bytes

                { ConvertFrom-SrsTrackData -Data $shortData } | Should -Throw "*too short*"
            }
        }

        It 'Throws when minimum length not met' {
            InModuleScope 'ReScenePS' {
                # 18 bytes is the minimum required
                $almostEnough = [byte[]]::new(17)

                { ConvertFrom-SrsTrackData -Data $almostEnough } | Should -Throw "*too short*"
            }
        }
    }

    Context 'Edge cases' {

        It 'Handles zero match offset' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0)
                $bw.Write([uint16]1)
                $bw.Write([uint32]10000)
                $bw.Write([uint64]0)  # zero offset
                $bw.Write([uint16]0)

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsTrackData -Data $data

                $result.MatchOffset | Should -Be 0
            }
        }

        It 'Handles maximum track number without flag' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0)
                $bw.Write([uint16]65535)  # max uint16
                $bw.Write([uint32]10000)
                $bw.Write([uint64]100)
                $bw.Write([uint16]0)

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsTrackData -Data $data

                $result.TrackNumber | Should -Be 65535
            }
        }
    }
}
