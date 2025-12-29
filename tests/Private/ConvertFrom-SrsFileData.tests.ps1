#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for ConvertFrom-SrsFileData function.

.DESCRIPTION
    Tests parsing of FileData element (0xC1) from MKV SRS files.
    Handles both regular and big file size formats.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment
}

Describe 'ConvertFrom-SrsFileData' {

    Context 'Valid FileData parsing' {

        It 'Parses standard file data correctly' {
            InModuleScope 'ReScenePS' {
                $appName = 'ReSample'
                $fileName = 'test-movie.mkv'

                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0)  # flags (no BIG_FILE)
                $bw.Write([uint16]$appName.Length)
                $bw.Write([System.Text.Encoding]::ASCII.GetBytes($appName))
                $bw.Write([uint16]$fileName.Length)
                $bw.Write([System.Text.Encoding]::ASCII.GetBytes($fileName))
                $bw.Write([uint32]104857600)  # 100 MB
                $bw.Write([uint32]0x12345678)  # CRC32

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsFileData -Data $data

                $result.Flags | Should -Be 0
                $result.AppName | Should -Be 'ReSample'
                $result.FileName | Should -Be 'test-movie.mkv'
                $result.OriginalSize | Should -Be 104857600
                $result.CRC32 | Should -Be 0x12345678
            }
        }

        It 'Handles BIG_FILE flag for large files' {
            InModuleScope 'ReScenePS' {
                $appName = 'ReSample'
                $fileName = 'large-movie.mkv'

                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]1)  # flags: BIG_FILE = 0x0001
                $bw.Write([uint16]$appName.Length)
                $bw.Write([System.Text.Encoding]::ASCII.GetBytes($appName))
                $bw.Write([uint16]$fileName.Length)
                $bw.Write([System.Text.Encoding]::ASCII.GetBytes($fileName))
                $bw.Write([uint64]5368709120)  # 5 GB (larger than uint32 max)
                $bw.Write([uint32]3735928559)  # CRC32 (0xDEADBEEF as decimal)

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsFileData -Data $data

                $result.Flags | Should -Be 1
                $result.OriginalSize | Should -Be 5368709120
            }
        }

        It 'Handles empty app name' {
            InModuleScope 'ReScenePS' {
                $fileName = 'sample.mkv'

                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0)  # flags
                $bw.Write([uint16]0)  # empty app name
                $bw.Write([uint16]$fileName.Length)
                $bw.Write([System.Text.Encoding]::ASCII.GetBytes($fileName))
                $bw.Write([uint32]1000000)
                $bw.Write([uint32]2864434397)  # 0xAABBCCDD as decimal

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsFileData -Data $data

                $result.AppName | Should -Be ''
                $result.FileName | Should -Be 'sample.mkv'
            }
        }

        It 'Handles long file names' {
            InModuleScope 'ReScenePS' {
                $appName = 'App'
                $fileName = 'This.Is.A.Very.Long.Movie.Name.With.Many.Words.2024.1080p.BluRay.x264-GROUP.mkv'

                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0)
                $bw.Write([uint16]$appName.Length)
                $bw.Write([System.Text.Encoding]::ASCII.GetBytes($appName))
                $bw.Write([uint16]$fileName.Length)
                $bw.Write([System.Text.Encoding]::ASCII.GetBytes($fileName))
                $bw.Write([uint32]2000000000)
                $bw.Write([uint32]0x11223344)

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsFileData -Data $data

                $result.FileName | Should -Be $fileName
            }
        }
    }

    Context 'Error handling' {

        It 'Throws on data too short' {
            InModuleScope 'ReScenePS' {
                $shortData = [byte[]]@(0x00, 0x00, 0x00)  # Only 3 bytes

                { ConvertFrom-SrsFileData -Data $shortData } | Should -Throw "*too short*"
            }
        }

        It 'Throws on minimum length violation' {
            InModuleScope 'ReScenePS' {
                # 14 bytes is the minimum required
                $almostEnough = [byte[]]::new(13)

                { ConvertFrom-SrsFileData -Data $almostEnough } | Should -Throw "*too short*"
            }
        }
    }

    Context 'Edge cases' {

        It 'Handles zero file size' {
            InModuleScope 'ReScenePS' {
                $appName = 'Test'
                $fileName = 'empty.mkv'

                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0)
                $bw.Write([uint16]$appName.Length)
                $bw.Write([System.Text.Encoding]::ASCII.GetBytes($appName))
                $bw.Write([uint16]$fileName.Length)
                $bw.Write([System.Text.Encoding]::ASCII.GetBytes($fileName))
                $bw.Write([uint32]0)  # zero size
                $bw.Write([uint32]0)  # zero CRC

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsFileData -Data $data

                $result.OriginalSize | Should -Be 0
                $result.CRC32 | Should -Be 0
            }
        }
    }
}
