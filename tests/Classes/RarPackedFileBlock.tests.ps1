#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for RarPackedFileBlock parsing.

.DESCRIPTION
    Tests RAR file header (type 0x74) parsing including packed/unpacked sizes,
    CRC, host OS, compression method, and filename extraction.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'RarPackedTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'RarPackedFileBlock Parsing' {

    Context 'Basic packed file block' {
        BeforeAll {
            $script:packedSrrPath = Join-Path $script:tempDir 'packed.srr'
            $ms = [System.IO.MemoryStream]::new()
            $writer = [System.IO.BinaryWriter]::new($ms)

            # SRR Header Block
            $writer.Write([uint16]0x6969)
            $writer.Write([byte]0x69)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint16]7)

            # SRR RAR File Block
            $rarFileName = [System.Text.Encoding]::UTF8.GetBytes('test.rar')
            $rarFileBlockSize = 7 + 2 + $rarFileName.Length
            $writer.Write([uint16]0x7171)
            $writer.Write([byte]0x71)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint16]$rarFileBlockSize)
            $writer.Write([uint16]$rarFileName.Length)
            $writer.Write($rarFileName)

            # RAR Marker Block
            $writer.Write([uint16]0x6152)
            $writer.Write([byte]0x72)
            $writer.Write([uint16]0x1A21)
            $writer.Write([uint16]0x0007)

            # RAR Volume Header Block
            $writer.Write([uint16]0x90CF)
            $writer.Write([byte]0x73)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint16]13)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint32]0x00000000)

            # RAR Packed File Block (type 0x74)
            $packedFileName = [System.Text.Encoding]::UTF8.GetBytes('movie.avi')
            $packedBlockSize = 7 + 25 + $packedFileName.Length  # base + fixed fields + name
            $writer.Write([uint16]0x7474)   # CRC (fake)
            $writer.Write([byte]0x74)        # Type: RarPackedFile
            $writer.Write([uint16]0x8000)    # Flags: has ADD_SIZE
            $writer.Write([uint16]$packedBlockSize)
            # 25-byte core structure:
            $writer.Write([uint32]0x00100000)  # PackedSize (1MB)
            $writer.Write([uint32]0x00200000)  # UnpackedSize (2MB)
            $writer.Write([byte]0x02)          # HostOs: Win32
            $writer.Write([byte[]]@(0xEF, 0xBE, 0xAD, 0xDE))  # FileCrc: 0xDEADBEEF (little-endian)
            $writer.Write([uint32]0x12345678)  # FileDateTime
            $writer.Write([byte]0x1D)          # RarVersion
            $writer.Write([byte]0x30)          # CompressionMethod (store)
            $writer.Write([uint16]$packedFileName.Length)  # NameSize
            $writer.Write([uint32]0x00000020)  # FileAttributes
            $writer.Write($packedFileName)

            # RAR End Archive Block
            $writer.Write([uint16]0x3DC4)
            $writer.Write([byte]0x7B)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint16]0x0007)

            $writer.Flush()
            [System.IO.File]::WriteAllBytes($script:packedSrrPath, $ms.ToArray())
            $writer.Dispose()
            $ms.Dispose()
        }

        It 'Parses RarPackedFileBlock' {
            $blocks = Get-SrrBlock -SrrFile $script:packedSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock | Should -Not -BeNullOrEmpty
        }

        It 'Has correct filename' {
            $blocks = Get-SrrBlock -SrrFile $script:packedSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock.FileName | Should -Be 'movie.avi'
        }

        It 'Has correct packed size' {
            $blocks = Get-SrrBlock -SrrFile $script:packedSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock.PackedSize | Should -Be 0x00100000
        }

        It 'Has correct unpacked size' {
            $blocks = Get-SrrBlock -SrrFile $script:packedSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock.UnpackedSize | Should -Be 0x00200000
        }

        It 'Has correct file CRC' {
            $blocks = Get-SrrBlock -SrrFile $script:packedSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock.FileCrc | Should -Be 3735928559  # 0xDEADBEEF as uint32
        }

        It 'Has correct host OS' {
            $blocks = Get-SrrBlock -SrrFile $script:packedSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock.HostOs | Should -Be 0x02
        }

        It 'Has correct compression method' {
            $blocks = Get-SrrBlock -SrrFile $script:packedSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock.CompressionMethod | Should -Be 0x30
        }
    }
}
