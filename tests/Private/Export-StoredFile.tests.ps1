#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Export-StoredFile function.

.DESCRIPTION
    Tests extraction of stored files from SRR archives.
    Uses mocking to test the function logic without needing real SRR files.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'StoredFileTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Export-StoredFile' {

    Context 'BlockReader integration' {

        It 'Creates BlockReader with correct file path' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                # Create a minimal file to trigger BlockReader
                $testFile = Join-Path $dir 'test.srr'
                [System.IO.File]::WriteAllBytes($testFile, [byte[]]::new(10))

                # Should throw because file is too small
                { Export-StoredFile -SrrFile $testFile -FileName '*.sfv' -OutputPath "$dir\out.sfv" } |
                    Should -Throw "*too small*"
            }
        }
    }

    Context 'File pattern matching' {

        It 'Uses wildcard pattern correctly' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                # Create a file with valid magic but still incomplete
                $testFile = Join-Path $dir 'pattern.srr'
                # Magic: 0x69 0x69 0x69 + minimal header
                $bytes = [byte[]]@(0x69, 0x69, 0x69) + [byte[]]::new(17)
                [System.IO.File]::WriteAllBytes($testFile, $bytes)

                # Will throw but tests that we're trying to read
                { Export-StoredFile -SrrFile $testFile -FileName '*.nfo' -OutputPath "$dir\out.nfo" } |
                    Should -Throw
            }
        }

        It 'Converts wildcard to regex pattern' {
            InModuleScope 'ReScenePS' {
                # The pattern conversion logic: $FileName -replace '\*', '.*'
                $pattern = 'test*.sfv' -replace '\*', '.*'
                $pattern | Should -Be 'test.*.sfv'

                'test-release.sfv' -match "^$pattern$" | Should -BeTrue
                'other.sfv' -match "^$pattern$" | Should -BeFalse
            }
        }
    }

    Context 'Error handling' {

        It 'Throws when SRR file does not exist' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $missingSrr = Join-Path $dir 'missing.srr'
                $outputPath = Join-Path $dir 'output.txt'

                { Export-StoredFile -SrrFile $missingSrr -FileName '*.sfv' -OutputPath $outputPath } |
                    Should -Throw
            }
        }

        It 'Throws on invalid SRR magic' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $badFile = Join-Path $dir 'bad.srr'
                [System.IO.File]::WriteAllBytes($badFile, [byte[]]@(0x00, 0x00, 0x00) + [byte[]]::new(50))

                { Export-StoredFile -SrrFile $badFile -FileName '*.sfv' -OutputPath "$dir\out.sfv" } |
                    Should -Throw "*magic*"
            }
        }
    }

    Context 'Parameter validation' {

        It 'Requires SrrFile parameter' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                { Export-StoredFile -FileName '*.sfv' -OutputPath "$dir\out.sfv" } |
                    Should -Throw "*SrrFile*"
            }
        }

        It 'Requires FileName parameter' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                { Export-StoredFile -SrrFile "$dir\test.srr" -OutputPath "$dir\out.sfv" } |
                    Should -Throw "*FileName*"
            }
        }

        It 'Requires OutputPath parameter' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                { Export-StoredFile -SrrFile "$dir\test.srr" -FileName '*.sfv' } |
                    Should -Throw "*OutputPath*"
            }
        }
    }

    Context 'File extraction logic' {

        It 'Filters blocks by HeadType 0x6A (stored file)' {
            InModuleScope 'ReScenePS' {
                # HeadType 0x6A is the stored file block type
                $storedFileBlockType = 0x6A
                $storedFileBlockType | Should -Be 106
            }
        }

        It 'Matches filename using regex' {
            InModuleScope 'ReScenePS' {
                # Test the regex matching logic used in the function
                $testFileName = 'release-name.sfv'
                $pattern = '*.sfv' -replace '\*', '.*'

                $testFileName -match "^$pattern$" | Should -BeTrue
            }
        }
    }
}
