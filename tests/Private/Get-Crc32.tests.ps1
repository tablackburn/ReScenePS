#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Get-Crc32 function.

.DESCRIPTION
    Tests CRC32 hash calculation for files and file portions.
    Requires the CRC module from PowerShell Gallery.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'Crc32Test'

}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Get-Crc32' {

    BeforeAll {
        # Create test file with known content
        $script:testFile = Join-Path $script:tempDir 'test.bin'

        # Write bytes 0x00 through 0xFF (256 bytes)
        $testData = [byte[]](0..255)
        [System.IO.File]::WriteAllBytes($script:testFile, $testData)
    }

    Context 'Full file CRC calculation' {
        It 'Calculates CRC32 for entire file' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:testFile } {
                $result = Get-Crc32 -FilePath $file
                $result | Should -BeOfType [uint32]
                # Known CRC32 of bytes 0x00-0xFF
                $result | Should -Be 0x29058C73
            }
        }
    }

    Context 'Partial file CRC calculation' {
        It 'Calculates CRC32 with offset' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:testFile } {
                # CRC of bytes starting at offset 128
                $result = Get-Crc32 -FilePath $file -Offset 128
                $result | Should -BeOfType [uint32]
            }
        }

        It 'Calculates CRC32 with length limit' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:testFile } {
                # CRC of first 10 bytes only
                $result = Get-Crc32 -FilePath $file -Length 10
                $result | Should -BeOfType [uint32]
            }
        }

        It 'Calculates CRC32 with offset and length' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:testFile } {
                # CRC of 10 bytes starting at offset 50
                $result = Get-Crc32 -FilePath $file -Offset 50 -Length 10
                $result | Should -BeOfType [uint32]
            }
        }
    }

    Context 'Known values' {
        BeforeAll {
            # Create file with known CRC32 value
            $script:knownFile = Join-Path $script:tempDir 'known.bin'
            # "test" = 0xD87F7E0C
            [System.IO.File]::WriteAllBytes($script:knownFile, [System.Text.Encoding]::ASCII.GetBytes('test'))
        }

        It 'Returns correct CRC32 for known content' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:knownFile } {
                $result = Get-Crc32 -FilePath $file
                # "test" has CRC32 of 0xD87F7E0C = 3632233996 (unsigned)
                $result | Should -Be 3632233996
            }
        }
    }

    Context 'Empty file handling' {
        BeforeAll {
            $script:emptyFile = Join-Path $script:tempDir 'empty.bin'
            [System.IO.File]::WriteAllBytes($script:emptyFile, [byte[]]@())
        }

        It 'Returns CRC32 for empty file' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:emptyFile } {
                $result = Get-Crc32 -FilePath $file
                # CRC32 of empty data is 0x00000000
                $result | Should -Be 0x00000000
            }
        }
    }
}
