#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Get-SrsInfo function.

.DESCRIPTION
    Tests SRS file type identification based on magic bytes.
    Covers RIFF (AVI), EBML (MKV), FLAC, and unknown file types.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'SrsInfoTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Get-SrsInfo' {

    Context 'File existence' {

        It 'Throws when file does not exist' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $missingFile = Join-Path $dir 'nonexistent.srs'

                { Get-SrsInfo -FilePath $missingFile } | Should -Throw "*not found*"
            }
        }
    }

    Context 'RIFF container detection' {

        BeforeAll {
            $script:riffFile = Join-Path $script:tempDir 'test.avi.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
            $bw.Write([uint32]100)  # size
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('AVI '))
            $bw.Write([byte[]]::new(88))  # padding to make file larger
            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:riffFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Identifies RIFF container' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:riffFile } {
                $result = Get-SrsInfo -FilePath $file

                $result.Type | Should -BeLike '*RIFF*'
            }
        }

        It 'Returns correct file path' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:riffFile } {
                $result = Get-SrsInfo -FilePath $file

                $result.Path | Should -BeLike '*test.avi.srs'
            }
        }

        It 'Returns correct file size' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:riffFile } {
                $result = Get-SrsInfo -FilePath $file

                $result.Size | Should -Be 100
            }
        }
    }

    Context 'EBML (MKV) detection' {

        BeforeAll {
            $script:ebmlFile = Join-Path $script:tempDir 'test.mkv.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)
            # EBML magic bytes: 0x1A 0x45 0xDF 0xA3
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte[]]::new(96))  # padding
            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:ebmlFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Identifies EBML (MKV) container' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:ebmlFile } {
                $result = Get-SrsInfo -FilePath $file

                $result.Type | Should -BeLike '*EBML*MKV*'
            }
        }
    }

    Context 'FLAC detection' {

        BeforeAll {
            $script:flacFile = Join-Path $script:tempDir 'test.flac.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('fLaC'))
            $bw.Write([byte[]]::new(96))  # padding
            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:flacFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Identifies FLAC format' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:flacFile } {
                $result = Get-SrsInfo -FilePath $file

                $result.Type | Should -Be 'FLAC'
            }
        }
    }

    Context 'Stream format detection' {

        BeforeAll {
            $script:strmFile = Join-Path $script:tempDir 'test.strm.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('STRM'))
            $bw.Write([byte[]]::new(96))
            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:strmFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Identifies Stream format' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:strmFile } {
                $result = Get-SrsInfo -FilePath $file

                $result.Type | Should -BeLike '*Stream*'
            }
        }
    }

    Context 'M2TS detection' {

        BeforeAll {
            $script:m2tsFile = Join-Path $script:tempDir 'test.m2ts.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('M2TS'))
            $bw.Write([byte[]]::new(96))
            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:m2tsFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Identifies M2TS Stream format' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:m2tsFile } {
                $result = Get-SrsInfo -FilePath $file

                $result.Type | Should -BeLike '*M2TS*'
            }
        }
    }

    Context 'Unknown format detection' {

        BeforeAll {
            $script:unknownFile = Join-Path $script:tempDir 'test.unknown.srs'

            # Random bytes that don't match any known format
            [System.IO.File]::WriteAllBytes($script:unknownFile, [byte[]]@(0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77))
        }

        It 'Returns Unknown for unrecognized magic bytes' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:unknownFile } {
                $result = Get-SrsInfo -FilePath $file

                $result.Type | Should -Be 'Unknown'
            }
        }
    }

    Context 'Small files' {

        BeforeAll {
            $script:tinyFile = Join-Path $script:tempDir 'tiny.srs'
            [System.IO.File]::WriteAllBytes($script:tinyFile, [byte[]]@(0x52, 0x49))  # Just "RI"
        }

        It 'Handles files smaller than 4 bytes' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:tinyFile } {
                $result = Get-SrsInfo -FilePath $file

                $result.Type | Should -Be 'Unknown'
                $result.Size | Should -Be 2
            }
        }
    }

    Context 'Output object structure' {

        It 'Returns object with required properties' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:riffFile } {
                $result = Get-SrsInfo -FilePath $file

                $result.PSObject.Properties.Name | Should -Contain 'Path'
                $result.PSObject.Properties.Name | Should -Contain 'Size'
                $result.PSObject.Properties.Name | Should -Contain 'Type'
            }
        }

        It 'Returns resolved path' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:riffFile } {
                $result = Get-SrsInfo -FilePath $file

                # Path should be fully resolved (absolute)
                $result.Path | Should -Match '^[A-Za-z]:\\'
            }
        }
    }
}
