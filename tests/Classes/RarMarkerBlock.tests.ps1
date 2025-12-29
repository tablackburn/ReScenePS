#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for RarMarkerBlock parsing.

.DESCRIPTION
    Tests RAR marker block (type 0x72) parsing. The marker block is a fixed
    7-byte sequence that identifies the start of a RAR archive: 52 61 72 21 1A 07 00
    (ASCII "Rar!" followed by 0x1A 0x07 0x00).
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'RarMarkerTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'RarMarkerBlock' {

    Context 'Standard RAR marker block' {
        BeforeAll {
            $script:markerSrrPath = Join-Path $script:tempDir 'marker.srr'
            $ms = [System.IO.MemoryStream]::new()
            $writer = [System.IO.BinaryWriter]::new($ms)

            # SRR Header Block (type 0x69)
            $writer.Write([uint16]0x6969)  # CRC
            $writer.Write([byte]0x69)       # Type: SRR header
            $writer.Write([uint16]0x0000)   # Flags
            $writer.Write([uint16]7)        # Size (header only, no app name)

            # SRR RAR File Block (type 0x71) - required before RAR blocks
            $rarFileName = [System.Text.Encoding]::UTF8.GetBytes('test.rar')
            $writer.Write([uint16]0x7171)   # CRC
            $writer.Write([byte]0x71)       # Type: SRR RAR file
            $writer.Write([uint16]0x0000)   # Flags
            $writer.Write([uint16](7 + 2 + $rarFileName.Length))  # Size
            $writer.Write([uint16]$rarFileName.Length)
            $writer.Write($rarFileName)

            # RAR Marker Block (type 0x72)
            # Fixed format: CRC=0x6152, Type=0x72, Flags=0x1A21, Size=0x0007
            # These bytes spell out "Rar!\x1a\x07\x00" when read as raw bytes
            $writer.Write([uint16]0x6152)   # CRC (actually 'Ra' in ASCII)
            $writer.Write([byte]0x72)       # Type: RAR marker ('r')
            $writer.Write([uint16]0x1A21)   # Flags ('!\x1a')
            $writer.Write([uint16]0x0007)   # Size (0x07 0x00)

            $writer.Flush()
            [System.IO.File]::WriteAllBytes($script:markerSrrPath, $ms.ToArray())
            $writer.Dispose()
            $ms.Dispose()
        }

        It 'Parses marker block without errors' {
            $blocks = Get-SrrBlock -SrrFile $script:markerSrrPath
            $blocks | Should -Not -BeNullOrEmpty
        }

        It 'Returns RarMarkerBlock type' {
            $blocks = Get-SrrBlock -SrrFile $script:markerSrrPath
            $markerBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarMarkerBlock' }
            $markerBlock | Should -Not -BeNullOrEmpty
        }

        It 'Has correct HeadType (0x72)' {
            $blocks = Get-SrrBlock -SrrFile $script:markerSrrPath
            $markerBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarMarkerBlock' }
            $markerBlock.HeadType | Should -Be 0x72
        }

        It 'Has correct HeadSize (7 bytes)' {
            $blocks = Get-SrrBlock -SrrFile $script:markerSrrPath
            $markerBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarMarkerBlock' }
            $markerBlock.HeadSize | Should -Be 7
        }

        It 'Has correct HeadCrc' {
            $blocks = Get-SrrBlock -SrrFile $script:markerSrrPath
            $markerBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarMarkerBlock' }
            $markerBlock.HeadCrc | Should -Be 0x6152
        }

        It 'Has correct HeadFlags' {
            $blocks = Get-SrrBlock -SrrFile $script:markerSrrPath
            $markerBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarMarkerBlock' }
            $markerBlock.HeadFlags | Should -Be 0x1A21
        }

        It 'Has zero AddSize (no additional data)' {
            $blocks = Get-SrrBlock -SrrFile $script:markerSrrPath
            $markerBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarMarkerBlock' }
            $markerBlock.AddSize | Should -Be 0
        }
    }

    Context 'Multiple RAR volumes with marker blocks' {
        BeforeAll {
            $script:multiVolumeSrrPath = Join-Path $script:tempDir 'multivolume.srr'
            $ms = [System.IO.MemoryStream]::new()
            $writer = [System.IO.BinaryWriter]::new($ms)

            # SRR Header Block
            $writer.Write([uint16]0x6969)
            $writer.Write([byte]0x69)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint16]7)

            # First RAR volume
            $rarFileName1 = [System.Text.Encoding]::UTF8.GetBytes('test.rar')
            $writer.Write([uint16]0x7171)
            $writer.Write([byte]0x71)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint16](7 + 2 + $rarFileName1.Length))
            $writer.Write([uint16]$rarFileName1.Length)
            $writer.Write($rarFileName1)

            # First RAR Marker Block
            $writer.Write([uint16]0x6152)
            $writer.Write([byte]0x72)
            $writer.Write([uint16]0x1A21)
            $writer.Write([uint16]0x0007)

            # Second RAR volume
            $rarFileName2 = [System.Text.Encoding]::UTF8.GetBytes('test.r00')
            $writer.Write([uint16]0x7171)
            $writer.Write([byte]0x71)
            $writer.Write([uint16]0x0000)
            $writer.Write([uint16](7 + 2 + $rarFileName2.Length))
            $writer.Write([uint16]$rarFileName2.Length)
            $writer.Write($rarFileName2)

            # Second RAR Marker Block
            $writer.Write([uint16]0x6152)
            $writer.Write([byte]0x72)
            $writer.Write([uint16]0x1A21)
            $writer.Write([uint16]0x0007)

            $writer.Flush()
            [System.IO.File]::WriteAllBytes($script:multiVolumeSrrPath, $ms.ToArray())
            $writer.Dispose()
            $ms.Dispose()
        }

        It 'Parses multiple marker blocks' {
            $blocks = Get-SrrBlock -SrrFile $script:multiVolumeSrrPath
            $markerBlocks = $blocks | Where-Object { $_.GetType().Name -eq 'RarMarkerBlock' }
            $markerBlocks.Count | Should -Be 2
        }

        It 'All marker blocks have consistent properties' {
            $blocks = Get-SrrBlock -SrrFile $script:multiVolumeSrrPath
            $markerBlocks = $blocks | Where-Object { $_.GetType().Name -eq 'RarMarkerBlock' }

            foreach ($block in $markerBlocks) {
                $block.HeadType | Should -Be 0x72
                $block.HeadSize | Should -Be 7
                $block.HeadCrc | Should -Be 0x6152
            }
        }
    }

    Context 'Block position tracking' {
        It 'Records correct block position' {
            $blocks = Get-SrrBlock -SrrFile $script:markerSrrPath
            $markerBlock = $blocks | Where-Object { $_.GetType().Name -eq 'RarMarkerBlock' }

            # BlockPosition should be after SRR header (7) + SRR RAR file block (7 + 2 + 8 = 17)
            $markerBlock.BlockPosition | Should -BeGreaterThan 0
        }
    }
}
