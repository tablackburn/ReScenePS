#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Get-Crc32 function.

.DESCRIPTION
    Tests CRC32 hash calculation for files.
    Uses compiled C# implementation via Add-Type.
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

    Context 'CRC calculation' {

        BeforeAll {
            # Create test file with known content (bytes 0x00-0xFF)
            $script:testFile = Join-Path $script:tempDir 'test.bin'
            $testData = [byte[]](0..255)
            [System.IO.File]::WriteAllBytes($script:testFile, $testData)

            # Create file with known CRC32 value ("test" = 0xD87F7E0C)
            $script:knownFile = Join-Path $script:tempDir 'known.bin'
            [System.IO.File]::WriteAllBytes($script:knownFile, [System.Text.Encoding]::ASCII.GetBytes('test'))

            # Create empty file
            $script:emptyFile = Join-Path $script:tempDir 'empty.bin'
            [System.IO.File]::WriteAllBytes($script:emptyFile, [byte[]]@())
        }

        It 'Calculates CRC32 for bytes 0x00-0xFF' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:testFile } {
                $result = Get-Crc32 -FilePath $file
                $result | Should -BeOfType [uint32]
                $result | Should -Be 0x29058C73
            }
        }

        It 'Returns correct CRC32 for known content' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:knownFile } {
                $result = Get-Crc32 -FilePath $file
                # "test" has CRC32 of 0xD87F7E0C = 3632233996
                $result | Should -Be 3632233996
            }
        }

        It 'Returns zero for empty file' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:emptyFile } {
                $result = Get-Crc32 -FilePath $file
                $result | Should -Be 0x00000000
            }
        }
    }

    Context 'Parameter handling' {

        BeforeAll {
            $script:paramTestFile = Join-Path $script:tempDir 'param-test.bin'
            [System.IO.File]::WriteAllBytes($script:paramTestFile, [System.Text.Encoding]::ASCII.GetBytes('test'))
        }

        It 'Accepts -FilePath parameter' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:paramTestFile } {
                $result = Get-Crc32 -FilePath $file
                $result | Should -Be 3632233996
            }
        }

        It 'Accepts -Path alias' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:paramTestFile } {
                $result = Get-Crc32 -Path $file
                $result | Should -Be 3632233996
            }
        }

        It 'Accepts pipeline input' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:paramTestFile } {
                $result = $file | Get-Crc32
                $result | Should -Be 3632233996
            }
        }

        It 'Accepts pipeline input by FullName property' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:paramTestFile } {
                $fileInfo = Get-Item $file
                $result = $fileInfo | Get-Crc32
                $result | Should -Be 3632233996
            }
        }

        It 'Processes multiple files via pipeline' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                # Create two test files
                $file1 = Join-Path $dir 'multi1.bin'
                $file2 = Join-Path $dir 'multi2.bin'
                [System.IO.File]::WriteAllBytes($file1, [System.Text.Encoding]::ASCII.GetBytes('test'))
                [System.IO.File]::WriteAllBytes($file2, [byte[]]@())

                $results = @($file1, $file2) | Get-Crc32
                $results.Count | Should -Be 2
                $results[0] | Should -Be 3632233996  # "test"
                $results[1] | Should -Be 0           # empty
            }
        }
    }

    Context 'Error handling' {

        It 'Throws on non-existent file' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $nonExistent = Join-Path $dir 'does-not-exist.bin'
                { Get-Crc32 -FilePath $nonExistent } | Should -Throw
            }
        }

        It 'Throws on null path' {
            InModuleScope 'ReScenePS' {
                { Get-Crc32 -FilePath $null } | Should -Throw
            }
        }

        It 'Throws on empty string path' {
            InModuleScope 'ReScenePS' {
                { Get-Crc32 -FilePath '' } | Should -Throw
            }
        }
    }

    Context 'Large files' {

        BeforeAll {
            # Create file larger than buffer size (80KB = 81920 bytes)
            # Use 100KB to ensure multiple buffer reads
            $script:largeFile = Join-Path $script:tempDir 'large.bin'
            $size = 100 * 1024
            $data = [byte[]]::new($size)
            [System.Random]::new(12345).NextBytes($data)
            [System.IO.File]::WriteAllBytes($script:largeFile, $data)
        }

        It 'Handles files larger than buffer size' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:largeFile } {
                $result = Get-Crc32 -FilePath $file
                $result | Should -BeOfType [uint32]
                # Verify it returns a non-zero value (actual CRC depends on random seed)
                $result | Should -Not -Be 0
            }
        }

        It 'Returns consistent results for same file' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:largeFile } {
                $result1 = Get-Crc32 -FilePath $file
                $result2 = Get-Crc32 -FilePath $file
                $result1 | Should -Be $result2
            }
        }
    }
}
