#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Get-SrrBlock function.

.DESCRIPTION
    Tests the SRR file parsing function with synthetic test data
    and validates error handling.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'GetSrrBlockTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Get-SrrBlock' {

    Context 'Parameter validation' {
        It 'Throws when SrrFile parameter is missing' {
            { Get-SrrBlock } | Should -Throw
        }

        It 'Throws when file does not exist' {
            { Get-SrrBlock -SrrFile 'C:\NonExistent\File.srr' } | Should -Throw
        }

        It 'Throws for empty file' {
            $emptyFile = Join-Path $script:tempDir 'empty.srr'
            [System.IO.File]::WriteAllBytes($emptyFile, [byte[]]@())
            { Get-SrrBlock -SrrFile $emptyFile } | Should -Throw
        }

        It 'Throws for file smaller than minimum size' {
            $tinyFile = Join-Path $script:tempDir 'tiny.srr'
            [System.IO.File]::WriteAllBytes($tinyFile, [byte[]](1..10))
            { Get-SrrBlock -SrrFile $tinyFile } | Should -Throw '*too small*'
        }
    }

    Context 'Magic number validation' {
        It 'Throws for invalid magic number' {
            $badMagic = Join-Path $script:tempDir 'badmagic.srr'
            # Create file with wrong magic (should be 69 69 69)
            $data = [byte[]]@(0x52, 0x61, 0x72) + [byte[]](0..50)
            [System.IO.File]::WriteAllBytes($badMagic, $data)
            { Get-SrrBlock -SrrFile $badMagic } | Should -Throw '*magic*'
        }
    }

    Context 'Valid minimal SRR file' {
        BeforeAll {
            # Create minimal valid SRR file with just a header block
            # SRR Header: CRC(2) + Type(1=0x69) + Flags(2) + Size(2) + AppNameLen(2) + AppName
            # File must be at least 20 bytes
            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp12345')  # 12 chars to ensure >= 20 bytes
            $headerSize = 7 + 2 + $appName.Length  # 7 (base) + 2 (appNameLen) + appName = 21 bytes

            $script:minimalSrr = Join-Path $script:tempDir 'minimal.srr'
            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # Write SRR header block
            $bw.Write([uint16]0x6969)  # CRC placeholder
            $bw.Write([byte]0x69)      # HEAD_TYPE = SRR Header
            $bw.Write([uint16]0x0000)  # HEAD_FLAGS
            $bw.Write([uint16]$headerSize)  # HEAD_SIZE
            $bw.Write([uint16]$appName.Length)  # AppName length
            $bw.Write($appName)        # AppName

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:minimalSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Parses minimal SRR without errors' {
            { Get-SrrBlock -SrrFile $script:minimalSrr } | Should -Not -Throw
        }

        It 'Returns at least one block' {
            $blocks = Get-SrrBlock -SrrFile $script:minimalSrr
            $blocks.Count | Should -BeGreaterOrEqual 1
        }

        It 'First block is SRR header type' {
            $blocks = Get-SrrBlock -SrrFile $script:minimalSrr
            $blocks[0].HeadType | Should -Be 0x69
        }
    }

    Context 'Return type validation' {
        BeforeAll {
            # Use the minimal SRR from previous context if available
            if (-not (Test-Path $script:minimalSrr)) {
                $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp12345')  # 12 chars
                $headerSize = 7 + 2 + $appName.Length  # 21 bytes

                $script:minimalSrr = Join-Path $script:tempDir 'minimal2.srr'
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0x6969)
                $bw.Write([byte]0x69)
                $bw.Write([uint16]0x0000)
                $bw.Write([uint16]$headerSize)
                $bw.Write([uint16]$appName.Length)
                $bw.Write($appName)

                $bw.Flush()
                [System.IO.File]::WriteAllBytes($script:minimalSrr, $ms.ToArray())
                $bw.Dispose()
                $ms.Dispose()
            }
        }

        It 'Returns one or more blocks' {
            $blocks = @(Get-SrrBlock -SrrFile $script:minimalSrr)
            $blocks.Count | Should -BeGreaterOrEqual 1
        }

        It 'Each block has HeadType property' {
            $blocks = Get-SrrBlock -SrrFile $script:minimalSrr
            $blocks[0].HeadType | Should -Not -BeNullOrEmpty
        }

        It 'Each block has HeadSize property' {
            $blocks = Get-SrrBlock -SrrFile $script:minimalSrr
            $blocks[0].HeadSize | Should -BeGreaterThan 0
        }
    }
}
