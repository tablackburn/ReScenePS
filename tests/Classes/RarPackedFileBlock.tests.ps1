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

    Context 'Packed file block with Salt' {
        BeforeAll {
            $script:saltSrrPath = Join-Path $script:tempDir 'salt.srr'
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

            # RAR Packed File Block with SALT flag (0x8000 | 0x0400 = 0x8400)
            $packedFileName = [System.Text.Encoding]::UTF8.GetBytes('encrypted.dat')
            # Size = 7 base + 25 core + name + 8 salt bytes
            $packedBlockSize = 7 + 25 + $packedFileName.Length + 8
            $writer.Write([uint16]0x7474)   # CRC
            $writer.Write([byte]0x74)        # Type
            $writer.Write([uint16]0x8400)    # Flags: ADD_SIZE | SALT
            $writer.Write([uint16]$packedBlockSize)
            # 25-byte core structure
            $writer.Write([uint32]1024)       # PackedSize
            $writer.Write([uint32]2048)       # UnpackedSize
            $writer.Write([byte]0x02)         # HostOs: Win32
            $writer.Write([uint32]0x12345678) # FileCrc
            $writer.Write([uint32]0x00000000) # FileDateTime
            $writer.Write([byte]0x1D)         # RarVersion
            $writer.Write([byte]0x30)         # CompressionMethod
            $writer.Write([uint16]$packedFileName.Length)
            $writer.Write([uint32]0x00000020) # FileAttributes
            $writer.Write($packedFileName)
            # Salt bytes (8 bytes)
            $writer.Write([byte[]]@(0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08))

            # RAR End Archive Block
            $writer.Write([uint16]0x3DC4)
            $writer.Write([byte]0x7B)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint16]0x0007)

            $writer.Flush()
            [System.IO.File]::WriteAllBytes($script:saltSrrPath, $ms.ToArray())
            $writer.Dispose()
            $ms.Dispose()
        }

        It 'Parses block with Salt flag' {
            $blocks = Get-SrrBlock -SrrFile $script:saltSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock | Should -Not -BeNullOrEmpty
        }

        It 'Has HasSalt flag set' {
            $blocks = Get-SrrBlock -SrrFile $script:saltSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock.HasSalt | Should -Be $true
        }

        It 'Has correct Salt bytes' {
            $blocks = Get-SrrBlock -SrrFile $script:saltSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock.Salt.Length | Should -Be 8
            $packedBlock.Salt[0] | Should -Be 0x01
            $packedBlock.Salt[7] | Should -Be 0x08
        }

        It 'Has correct filename despite salt' {
            $blocks = Get-SrrBlock -SrrFile $script:saltSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock.FileName | Should -Be 'encrypted.dat'
        }
    }

    Context 'Packed file block with Large File flag' {
        BeforeAll {
            $script:largeSrrPath = Join-Path $script:tempDir 'large.srr'
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

            # RAR Packed File Block with LARGE_FILE flag (0x8000 | 0x0100 = 0x8100)
            $packedFileName = [System.Text.Encoding]::UTF8.GetBytes('big.bin')
            # Size = 7 base + 25 core + 8 (high 32-bits) + name
            $packedBlockSize = 7 + 25 + 8 + $packedFileName.Length
            $writer.Write([uint16]0x7474)
            $writer.Write([byte]0x74)
            $writer.Write([uint16]0x8100)    # Flags: ADD_SIZE | LARGE_FILE
            $writer.Write([uint16]$packedBlockSize)
            # 25-byte core structure
            $writer.Write([uint32]0x10000000) # PackedSize low 32 bits (268435456)
            $writer.Write([uint32]0x20000000) # UnpackedSize low 32 bits (536870912)
            $writer.Write([byte]0x02)
            $writer.Write([uint32]0x12345678) # FileCrc
            $writer.Write([uint32]0x00000000)
            $writer.Write([byte]0x1D)
            $writer.Write([byte]0x30)
            $writer.Write([uint16]$packedFileName.Length)
            $writer.Write([uint32]0x00000020)
            # High 32 bits of packed/unpacked (4+4 bytes) - comes BEFORE filename per RAR format
            $writer.Write([uint32]0x00000001)  # High packed (adds 4GB)
            $writer.Write([uint32]0x00000002)  # High unpacked (adds 8GB)
            $writer.Write($packedFileName)

            # RAR End Archive Block
            $writer.Write([uint16]0x3DC4)
            $writer.Write([byte]0x7B)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint16]0x0007)

            $writer.Flush()
            [System.IO.File]::WriteAllBytes($script:largeSrrPath, $ms.ToArray())
            $writer.Dispose()
            $ms.Dispose()
        }

        It 'Parses large file block' {
            $blocks = Get-SrrBlock -SrrFile $script:largeSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock | Should -Not -BeNullOrEmpty
        }

        It 'Has HasLargeFile flag set' {
            $blocks = Get-SrrBlock -SrrFile $script:largeSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock.HasLargeFile | Should -Be $true
        }

        It 'Has correct full packed size (64-bit)' {
            $blocks = Get-SrrBlock -SrrFile $script:largeSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            # Low: 0x10000000 (268435456) + High: 0x00000001 << 32 (4294967296) = 4563402752
            $packedBlock.FullPackedSize | Should -Be 4563402752
        }

        It 'Has correct full unpacked size (64-bit)' {
            $blocks = Get-SrrBlock -SrrFile $script:largeSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            # Low: 0x20000000 (536870912) + High: 0x00000002 << 32 (8589934592) = 9126805504
            $packedBlock.FullUnpackedSize | Should -Be 9126805504
        }
    }

    Context 'Packed file block with ExtTime' {
        BeforeAll {
            $script:extTimeSrrPath = Join-Path $script:tempDir 'exttime.srr'
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

            # RAR Packed File Block with EXT_TIME flag (0x8000 | 0x1000 = 0x9000)
            $packedFileName = [System.Text.Encoding]::UTF8.GetBytes('time.dat')
            # Size = 7 base + 25 core + name + 2 (exttime flags)
            $packedBlockSize = 7 + 25 + $packedFileName.Length + 2
            $writer.Write([uint16]0x7474)
            $writer.Write([byte]0x74)
            $writer.Write([uint16]0x9000)    # Flags: ADD_SIZE | EXT_TIME
            $writer.Write([uint16]$packedBlockSize)
            # 25-byte core structure
            $writer.Write([uint32]512)        # PackedSize
            $writer.Write([uint32]1024)       # UnpackedSize
            $writer.Write([byte]0x02)
            $writer.Write([uint32]0x11111111) # FileCrc
            $writer.Write([uint32]0x00000000) # FileDateTime
            $writer.Write([byte]0x1D)
            $writer.Write([byte]0x30)
            $writer.Write([uint16]$packedFileName.Length)
            $writer.Write([uint32]0x00000020)
            $writer.Write($packedFileName)
            # ExtTime flags (minimal - just flag byte indicating no extra data)
            $writer.Write([uint16]0x0000)

            # RAR End Archive Block
            $writer.Write([uint16]0x3DC4)
            $writer.Write([byte]0x7B)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint16]0x0007)

            $writer.Flush()
            [System.IO.File]::WriteAllBytes($script:extTimeSrrPath, $ms.ToArray())
            $writer.Dispose()
            $ms.Dispose()
        }

        It 'Parses ExtTime block' {
            $blocks = Get-SrrBlock -SrrFile $script:extTimeSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock | Should -Not -BeNullOrEmpty
        }

        It 'Has HasExtTime flag set' {
            $blocks = Get-SrrBlock -SrrFile $script:extTimeSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock.HasExtTime | Should -Be $true
        }

        It 'Has ExtTime property initialized' {
            $blocks = Get-SrrBlock -SrrFile $script:extTimeSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            # ExtTime is a hashtable (may be empty if no time data in flags)
            $packedBlock.ExtTime | Should -BeOfType [hashtable]
        }

        It 'Parses file name correctly with ExtTime' {
            $blocks = Get-SrrBlock -SrrFile $script:extTimeSrrPath
            $packedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlock.FileName | Should -Be 'time.dat'
        }
    }
}
