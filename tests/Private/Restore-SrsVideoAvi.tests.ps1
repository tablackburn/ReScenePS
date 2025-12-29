#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Restore-SrsVideoAvi function.

.DESCRIPTION
    Tests AVI sample reconstruction workflow.
    Uses mocking to isolate the function from its dependencies.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'RestoreAviTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Restore-SrsVideoAvi' {

    Context 'Parameter validation' {

        It 'Requires SrsFilePath parameter' {
            InModuleScope 'ReScenePS' {
                { Restore-SrsVideoAvi -SourcePath 'source.avi' -OutputPath 'output.avi' } |
                    Should -Throw "*SrsFilePath*"
            }
        }

        It 'Requires SourcePath parameter' {
            InModuleScope 'ReScenePS' {
                { Restore-SrsVideoAvi -SrsFilePath 'test.srs' -OutputPath 'output.avi' } |
                    Should -Throw "*SourcePath*"
            }
        }

        It 'Requires OutputPath parameter' {
            InModuleScope 'ReScenePS' {
                { Restore-SrsVideoAvi -SrsFilePath 'test.srs' -SourcePath 'source.avi' } |
                    Should -Throw "*OutputPath*"
            }
        }
    }

    Context 'Successful reconstruction' {

        BeforeAll {
            # Create a minimal valid AVI SRS file
            $script:testSrs = Join-Path $script:tempDir 'test.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # RIFF header
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
            $bw.Write([uint32]100)
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('AVI '))

            # LIST movi
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('LIST'))
            $bw.Write([uint32]80)
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('movi'))

            # Padding
            $bw.Write([byte[]]::new(68))

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:testSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            # Create source AVI file
            $script:sourceAvi = Join-Path $script:tempDir 'source.avi'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
            $bw.Write([uint32]1000)
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('AVI '))
            $bw.Write([byte[]]::new(988))
            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:sourceAvi, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Reads SRS file successfully' {
            InModuleScope 'ReScenePS' -Parameters @{
                srs = $script:testSrs
                source = $script:sourceAvi
                dir = $script:tempDir
            } {
                # Mock Build-SampleAviFromSrs to isolate this function
                Mock Build-SampleAviFromSrs { return $true }

                $outputPath = Join-Path $dir 'output.avi'

                # Should not throw when reading SRS
                { Restore-SrsVideoAvi -SrsFilePath $srs -SourcePath $source -OutputPath $outputPath } |
                    Should -Not -Throw
            }
        }

        It 'Calls Build-SampleAviFromSrs with correct parameters' {
            InModuleScope 'ReScenePS' -Parameters @{
                srs = $script:testSrs
                source = $script:sourceAvi
                dir = $script:tempDir
            } {
                Mock Build-SampleAviFromSrs { return $true } -Verifiable

                $outputPath = Join-Path $dir 'output2.avi'

                Restore-SrsVideoAvi -SrsFilePath $srs -SourcePath $source -OutputPath $outputPath

                Should -InvokeVerifiable
            }
        }

        It 'Returns true on successful reconstruction' {
            InModuleScope 'ReScenePS' -Parameters @{
                srs = $script:testSrs
                source = $script:sourceAvi
                dir = $script:tempDir
            } {
                Mock Build-SampleAviFromSrs { return $true }

                $outputPath = Join-Path $dir 'output3.avi'

                $result = Restore-SrsVideoAvi -SrsFilePath $srs -SourcePath $source -OutputPath $outputPath

                $result | Should -BeTrue
            }
        }
    }

    Context 'Failed reconstruction' {

        It 'Returns false when Build-SampleAviFromSrs returns false' {
            InModuleScope 'ReScenePS' -Parameters @{
                srs = $script:testSrs
                source = $script:sourceAvi
                dir = $script:tempDir
            } {
                Mock Build-SampleAviFromSrs { return $false }

                $outputPath = Join-Path $dir 'failed.avi'

                $result = Restore-SrsVideoAvi -SrsFilePath $srs -SourcePath $source -OutputPath $outputPath

                $result | Should -BeFalse
            }
        }

        It 'Returns false when Build-SampleAviFromSrs throws' {
            InModuleScope 'ReScenePS' -Parameters @{
                srs = $script:testSrs
                source = $script:sourceAvi
                dir = $script:tempDir
            } {
                Mock Build-SampleAviFromSrs { throw "Test error" }

                $outputPath = Join-Path $dir 'error.avi'

                $result = Restore-SrsVideoAvi -SrsFilePath $srs -SourcePath $source -OutputPath $outputPath

                $result | Should -BeFalse
            }
        }
    }

    Context 'Output file verification' {

        It 'Verifies output file exists after successful reconstruction' {
            InModuleScope 'ReScenePS' -Parameters @{
                srs = $script:testSrs
                source = $script:sourceAvi
                dir = $script:tempDir
            } {
                $outputPath = Join-Path $dir 'verify.avi'

                # Create the output file in the mock
                Mock Build-SampleAviFromSrs {
                    [System.IO.File]::WriteAllBytes($outputPath, [byte[]]@(0x52, 0x49, 0x46, 0x46))
                    return $true
                }

                $result = Restore-SrsVideoAvi -SrsFilePath $srs -SourcePath $source -OutputPath $outputPath

                $result | Should -BeTrue
                Test-Path $outputPath | Should -BeTrue
            }
        }
    }
}
