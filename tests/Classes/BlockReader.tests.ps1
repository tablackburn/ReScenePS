#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for BlockReader class and SRR block parsing.

.DESCRIPTION
    Tests SRR file parsing using synthetic binary data.
    Validates block instantiation, header parsing, and error handling.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'BlockReaderTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'BlockReader' {

    Context 'Minimal valid SRR file' {
        BeforeAll {
            # Build a minimal valid SRR file:
            # - SRR Header block (0x69)
            # - SRR RAR File block (0x71)
            # - RAR Marker block (0x72)
            # - RAR Volume Header block (0x73)
            # - RAR End Archive block (0x7B)

            $script:minimalSrrPath = Join-Path $script:tempDir 'minimal.srr'
            $ms = [System.IO.MemoryStream]::new()
            $writer = [System.IO.BinaryWriter]::new($ms)

            # SRR Header Block (type 0x69)
            # CRC (2 bytes) + Type (1) + Flags (2) + Size (2) = 7 bytes minimum
            # With app name flag (0x0001): Size (2) + Name
            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp')
            $headerSize = 7 + 2 + $appName.Length  # 7 base + 2 name length + name
            $writer.Write([uint16]0x6969)  # CRC (fake)
            $writer.Write([byte]0x69)       # Type: SrrHeader
            $writer.Write([uint16]0x0001)   # Flags: has app name
            $writer.Write([uint16]$headerSize)
            $writer.Write([uint16]$appName.Length)
            $writer.Write($appName)

            # SRR RAR File Block (type 0x71)
            $rarFileName = [System.Text.Encoding]::UTF8.GetBytes('test.rar')
            $rarFileBlockSize = 7 + 2 + $rarFileName.Length
            $writer.Write([uint16]0x7171)   # CRC (fake)
            $writer.Write([byte]0x71)        # Type: SrrRarFile
            $writer.Write([uint16]0x0000)    # Flags
            $writer.Write([uint16]$rarFileBlockSize)
            $writer.Write([uint16]$rarFileName.Length)
            $writer.Write($rarFileName)

            # RAR Marker Block (type 0x72) - fixed 7 bytes
            $writer.Write([uint16]0x6152)   # CRC: 0x6152
            $writer.Write([byte]0x72)        # Type: RarMarker
            $writer.Write([uint16]0x1A21)    # Flags
            $writer.Write([uint16]0x0007)    # Size: 7 bytes

            # RAR Volume Header Block (type 0x73)
            $writer.Write([uint16]0x90CF)   # CRC (fake)
            $writer.Write([byte]0x73)        # Type: RarVolumeHeader
            $writer.Write([uint16]0x0000)    # Flags
            $writer.Write([uint16]13)        # Size: 7 + 6 (reserved fields)
            $writer.Write([uint16]0x0000)    # Reserved1
            $writer.Write([uint32]0x00000000) # Reserved2

            # RAR End Archive Block (type 0x7B)
            $writer.Write([uint16]0x3DC4)   # CRC (fake)
            $writer.Write([byte]0x7B)        # Type: RarArchiveEnd
            $writer.Write([uint16]0x0000)    # Flags: no optional fields
            $writer.Write([uint16]0x0007)    # Size: 7 bytes

            $writer.Flush()
            [System.IO.File]::WriteAllBytes($script:minimalSrrPath, $ms.ToArray())
            $writer.Dispose()
            $ms.Dispose()
        }

        It 'Parses without throwing' {
            { Get-SrrBlock -SrrFile $script:minimalSrrPath } | Should -Not -Throw
        }

        It 'Returns expected number of blocks' {
            $blocks = Get-SrrBlock -SrrFile $script:minimalSrrPath
            $blocks.Count | Should -Be 5
        }

        It 'First block is SrrHeaderBlock' {
            $blocks = Get-SrrBlock -SrrFile $script:minimalSrrPath
            $blocks[0].GetType().Name | Should -Be 'SrrHeaderBlock'
        }

        It 'SrrHeaderBlock contains app name' {
            $blocks = Get-SrrBlock -SrrFile $script:minimalSrrPath
            $blocks[0].AppName | Should -Be 'TestApp'
        }

        It 'Contains SrrRarFileBlock with correct filename' {
            $blocks = Get-SrrBlock -SrrFile $script:minimalSrrPath
            $rarFileBlock = $blocks | Where-Object { $_.GetType().Name -eq 'SrrRarFileBlock' }
            $rarFileBlock | Should -Not -BeNullOrEmpty
            $rarFileBlock.FileName | Should -Be 'test.rar'
        }

        It 'Contains RarMarkerBlock' {
            $blocks = Get-SrrBlock -SrrFile $script:minimalSrrPath
            $markerBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarMarkerBlock' }
            $markerBlock | Should -Not -BeNullOrEmpty
            $markerBlock.HeadType | Should -Be 0x72
        }

        It 'Contains RarVolumeHeaderBlock' {
            $blocks = Get-SrrBlock -SrrFile $script:minimalSrrPath
            $volumeBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarVolumeHeaderBlock' }
            $volumeBlock | Should -Not -BeNullOrEmpty
            $volumeBlock.HeadType | Should -Be 0x73
        }

        It 'Contains RarEndArchiveBlock' {
            $blocks = Get-SrrBlock -SrrFile $script:minimalSrrPath
            $endBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarEndArchiveBlock' }
            $endBlock | Should -Not -BeNullOrEmpty
            $endBlock.HeadType | Should -Be 0x7B
        }
    }

    Context 'SRR with stored file' {
        BeforeAll {
            $script:storedFileSrrPath = Join-Path $script:tempDir 'stored.srr'
            $ms = [System.IO.MemoryStream]::new()
            $writer = [System.IO.BinaryWriter]::new($ms)

            # SRR Header Block
            $writer.Write([uint16]0x6969)
            $writer.Write([byte]0x69)
            $writer.Write([uint16]0x0000)  # No app name
            $writer.Write([uint16]7)

            # SRR Stored File Block (type 0x6A)
            $storedFileName = [System.Text.Encoding]::UTF8.GetBytes('release.nfo')
            $storedFileContent = [System.Text.Encoding]::UTF8.GetBytes('NFO content here')
            $storedBlockSize = 7 + 4 + 2 + $storedFileName.Length  # base + addsize + namelen + name
            $writer.Write([uint16]0x6A6A)   # CRC (fake)
            $writer.Write([byte]0x6A)        # Type: SrrStoredFile
            $writer.Write([uint16]0x8000)    # Flags: has ADD_SIZE
            $writer.Write([uint16]$storedBlockSize)
            $writer.Write([uint32]$storedFileContent.Length)  # ADD_SIZE (file size)
            $writer.Write([uint16]$storedFileName.Length)
            $writer.Write($storedFileName)
            $writer.Write($storedFileContent)  # The actual stored file data

            $writer.Flush()
            [System.IO.File]::WriteAllBytes($script:storedFileSrrPath, $ms.ToArray())
            $writer.Dispose()
            $ms.Dispose()
        }

        It 'Parses stored file block correctly' {
            $blocks = Get-SrrBlock -SrrFile $script:storedFileSrrPath
            $storedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'SrrStoredFileBlock' }
            $storedBlock | Should -Not -BeNullOrEmpty
        }

        It 'Stored file block has correct filename' {
            $blocks = Get-SrrBlock -SrrFile $script:storedFileSrrPath
            $storedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'SrrStoredFileBlock' }
            $storedBlock.FileName | Should -Be 'release.nfo'
        }

        It 'Stored file block has correct file size' {
            $blocks = Get-SrrBlock -SrrFile $script:storedFileSrrPath
            $storedBlock = $blocks | Where-Object { $_.GetType().Name -eq 'SrrStoredFileBlock' }
            $expectedSize = [System.Text.Encoding]::UTF8.GetBytes('NFO content here').Length
            $storedBlock.FileSize | Should -Be $expectedSize
        }
    }

    Context 'Validation errors' {
        It 'Throws on file smaller than 20 bytes' {
            $tinyPath = Join-Path $script:tempDir 'tiny.srr'
            [System.IO.File]::WriteAllBytes($tinyPath, [byte[]]@(0x69, 0x69, 0x69))

            { Get-SrrBlock -SrrFile $tinyPath } | Should -Throw '*too small*'
        }

        It 'Throws on invalid magic number' {
            $invalidPath = Join-Path $script:tempDir 'invalid.srr'
            # Create 20+ byte file with wrong magic
            $invalidData = [byte[]]::new(25)
            $invalidData[0] = 0xAA
            $invalidData[1] = 0xBB
            $invalidData[2] = 0xCC
            [System.IO.File]::WriteAllBytes($invalidPath, $invalidData)

            { Get-SrrBlock -SrrFile $invalidPath } | Should -Throw '*magic*'
        }

        It 'Throws on non-existent file' {
            { Get-SrrBlock -SrrFile 'C:\nonexistent\path\fake.srr' } | Should -Throw
        }
    }
}
