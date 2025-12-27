#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for RarEndArchiveBlock parsing.

.DESCRIPTION
    Tests RAR end archive block (type 0x7B) parsing including optional
    fields controlled by flags: HasNextVolume, HasArchiveCrc, HasVolumeNumber.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'RarEndTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'RarEndArchiveBlock Flags' {

    Context 'End block with CRC and volume number' {
        BeforeAll {
            $script:endBlockSrrPath = Join-Path $script:tempDir 'endblock.srr'
            $ms = [System.IO.MemoryStream]::new()
            $writer = [System.IO.BinaryWriter]::new($ms)

            # SRR Header Block
            $writer.Write([uint16]0x6969)
            $writer.Write([byte]0x69)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint16]7)

            # SRR RAR File Block
            $rarFileName = [System.Text.Encoding]::UTF8.GetBytes('test.rar')
            $writer.Write([uint16]0x7171)
            $writer.Write([byte]0x71)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint16](7 + 2 + $rarFileName.Length))
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

            # RAR End Archive Block with flags
            # Flags: 0x000B = HasNextVolume(0x0001) + HasArchiveCrc(0x0002) + HasVolumeNumber(0x0008)
            $endBlockSize = 7 + 4 + 2  # base + CRC + volume number
            $writer.Write([uint16]0x3DC4)   # CRC (fake)
            $writer.Write([byte]0x7B)        # Type: RarArchiveEnd
            $writer.Write([uint16]0x000B)    # Flags: all optional fields present
            $writer.Write([uint16]$endBlockSize)
            $writer.Write([byte[]]@(0xBE, 0xBA, 0xFE, 0xCA))  # ArchiveCrc: 0xCAFEBABE (little-endian)
            $writer.Write([uint16]5)           # VolumeNumber

            $writer.Flush()
            [System.IO.File]::WriteAllBytes($script:endBlockSrrPath, $ms.ToArray())
            $writer.Dispose()
            $ms.Dispose()
        }

        It 'Parses HasNextVolume flag' {
            $blocks = Get-SrrBlock -SrrFile $script:endBlockSrrPath
            $endBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarEndArchiveBlock' }
            $endBlock.HasNextVolume | Should -Be $true
        }

        It 'Parses HasArchiveCrc flag' {
            $blocks = Get-SrrBlock -SrrFile $script:endBlockSrrPath
            $endBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarEndArchiveBlock' }
            $endBlock.HasArchiveCrc | Should -Be $true
        }

        It 'Parses archive CRC value' {
            $blocks = Get-SrrBlock -SrrFile $script:endBlockSrrPath
            $endBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarEndArchiveBlock' }
            $endBlock.ArchiveCrc | Should -Be 3405691582  # 0xCAFEBABE as uint32
        }

        It 'Parses HasVolumeNumber flag' {
            $blocks = Get-SrrBlock -SrrFile $script:endBlockSrrPath
            $endBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarEndArchiveBlock' }
            $endBlock.HasVolumeNumber | Should -Be $true
        }

        It 'Parses volume number' {
            $blocks = Get-SrrBlock -SrrFile $script:endBlockSrrPath
            $endBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarEndArchiveBlock' }
            $endBlock.VolumeNumber | Should -Be 5
        }
    }
}
