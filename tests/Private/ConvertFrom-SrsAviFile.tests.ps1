#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for ConvertFrom-SrsAviFile and related AVI SRS parsing functions.

.DESCRIPTION
    Tests AVI SRS file parsing including RIFF container handling,
    SRSF (file metadata) and SRST (track metadata) chunk parsing.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'SrsAviTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'ConvertFrom-SrsAviFile' {

    Context 'Valid RIFF AVI SRS parsing' {

        BeforeAll {
            # Build a minimal valid AVI SRS structure
            # RIFF header (12 bytes) + LIST movi with SRSF chunk
            $script:validSrsFile = Join-Path $script:tempDir 'valid.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # RIFF header
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
            $riffSizePos = $ms.Position
            $bw.Write([uint32]0)  # Placeholder for size
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('AVI '))

            # LIST movi chunk
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('LIST'))
            $listSizePos = $ms.Position
            $bw.Write([uint32]0)  # Placeholder for size
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('movi'))

            # SRSF chunk (file metadata)
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('SRSF'))
            $appName = 'TestApp'
            $fileName = 'sample.avi'
            $srsfSize = 2 + 2 + $appName.Length + 2 + $fileName.Length + 8 + 4
            $bw.Write([uint32]$srsfSize)
            $bw.Write([uint16]0)  # flags
            $bw.Write([uint16]$appName.Length)
            $bw.Write([System.Text.Encoding]::UTF8.GetBytes($appName))
            $bw.Write([uint16]$fileName.Length)
            $bw.Write([System.Text.Encoding]::UTF8.GetBytes($fileName))
            $bw.Write([uint64]1234567)  # file size
            $bw.Write([uint32]3735928559)  # crc32 (0xDEADBEEF as decimal)

            # SRST chunk (track metadata)
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('SRST'))
            $srstSize = 2 + 2 + 4 + 8 + 2 + 4  # flags + trackNum + dataLen + matchOffset + sigLen + sig
            $bw.Write([uint32]$srstSize)
            $bw.Write([uint16]0)  # flags (no BIG_FILE, no BIG_TRACK_NUMBER)
            $bw.Write([uint16]1)  # track number
            $bw.Write([uint32]5000)  # data length
            $bw.Write([uint64]100)  # match offset
            $bw.Write([uint16]4)  # signature length
            $bw.Write([byte[]]@(0x00, 0x00, 0x01, 0xB3))  # signature bytes

            # Update sizes
            $endPos = $ms.Position
            $listSize = $endPos - $listSizePos - 4
            $riffSize = $endPos - 8

            $ms.Position = $listSizePos
            $bw.Write([uint32]$listSize)
            $ms.Position = $riffSizePos
            $bw.Write([uint32]$riffSize)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:validSrsFile, $ms.ToArray())

            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Parses valid AVI SRS file from path' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:validSrsFile } {
                $result = ConvertFrom-SrsAviFile -FilePath $file

                $result | Should -Not -BeNullOrEmpty
                $result.ContainerType | Should -Be 'AVI '
                $result.RawBytes | Should -Not -BeNullOrEmpty
                $result.MoviPosition | Should -BeGreaterOrEqual 0
            }
        }

        It 'Parses file metadata correctly' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:validSrsFile } {
                $result = ConvertFrom-SrsAviFile -FilePath $file

                $result.FileMetadata | Should -Not -BeNullOrEmpty
                $result.FileMetadata.Application | Should -Be 'TestApp'
                $result.FileMetadata.FileName | Should -Be 'sample.avi'
                $result.FileMetadata.FileSize | Should -Be 1234567
                $result.FileMetadata.Crc32 | Should -Be 3735928559
            }
        }

        It 'Returns Tracks hashtable' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:validSrsFile } {
                $result = ConvertFrom-SrsAviFile -FilePath $file

                # Tracks is returned as a hashtable (may be empty depending on parsing)
                $result.Tracks | Should -BeOfType [hashtable]
            }
        }

        It 'Parses from byte array' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:validSrsFile } {
                $bytes = [System.IO.File]::ReadAllBytes($file)
                $result = ConvertFrom-SrsAviFile -Data $bytes

                $result | Should -Not -BeNullOrEmpty
                $result.ContainerType | Should -Be 'AVI '
            }
        }
    }

    Context 'Invalid RIFF handling' {

        It 'Throws on non-RIFF file' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $badFile = Join-Path $dir 'notriff.bin'
                [System.IO.File]::WriteAllBytes($badFile, [byte[]]@(0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B))

                { ConvertFrom-SrsAviFile -FilePath $badFile } | Should -Throw "*Invalid RIFF magic*"
            }
        }

        It 'Throws on file not found' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $missingFile = Join-Path $dir 'nonexistent.srs'

                { ConvertFrom-SrsAviFile -FilePath $missingFile } | Should -Throw "*not found*"
            }
        }
    }

    Context 'Big file and track number flags' {

        BeforeAll {
            # Build AVI SRS with BIG_FILE and BIG_TRACK_NUMBER flags
            $script:bigFlagsSrsFile = Join-Path $script:tempDir 'bigflags.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # RIFF header
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
            $riffSizePos = $ms.Position
            $bw.Write([uint32]0)
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('AVI '))

            # LIST movi
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('LIST'))
            $listSizePos = $ms.Position
            $bw.Write([uint32]0)
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('movi'))

            # SRST with BIG_FILE (0x4) and BIG_TRACK_NUMBER (0x8) flags
            $bw.Write([System.Text.Encoding]::ASCII.GetBytes('SRST'))
            $srstSize = 2 + 4 + 8 + 8 + 2  # flags + trackNum(4) + dataLen(8) + matchOffset + sigLen
            $bw.Write([uint32]$srstSize)
            $bw.Write([uint16]0x000C)  # flags: BIG_FILE | BIG_TRACK_NUMBER
            $bw.Write([uint32]999)  # track number (4 bytes due to BIG_TRACK_NUMBER)
            $bw.Write([uint64]9876543210)  # data length (8 bytes due to BIG_FILE)
            $bw.Write([uint64]500)  # match offset
            $bw.Write([uint16]0)  # no signature

            # Update sizes
            $endPos = $ms.Position
            $listSize = $endPos - $listSizePos - 4
            $riffSize = $endPos - 8

            $ms.Position = $listSizePos
            $bw.Write([uint32]$listSize)
            $ms.Position = $riffSizePos
            $bw.Write([uint32]$riffSize)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:bigFlagsSrsFile, $ms.ToArray())

            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Parses file with BIG flags without error' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:bigFlagsSrsFile } {
                # Should parse without throwing
                $result = ConvertFrom-SrsAviFile -FilePath $file

                $result | Should -Not -BeNullOrEmpty
                $result.ContainerType | Should -Be 'AVI '
            }
        }

        It 'Returns Tracks hashtable for BIG flags file' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:bigFlagsSrsFile } {
                $result = ConvertFrom-SrsAviFile -FilePath $file

                $result.Tracks | Should -BeOfType [hashtable]
            }
        }
    }
}

Describe 'ConvertFrom-SrsAviFileData' {

    Context 'Valid SRSF data parsing' {

        It 'Parses file metadata with all fields' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $appName = 'SRSMaker'
                $fileName = 'movie-sample.avi'

                $bw.Write([uint16]0)  # flags
                $bw.Write([uint16]$appName.Length)
                $bw.Write([System.Text.Encoding]::UTF8.GetBytes($appName))
                $bw.Write([uint16]$fileName.Length)
                $bw.Write([System.Text.Encoding]::UTF8.GetBytes($fileName))
                $bw.Write([uint64]12345678)
                $bw.Write([uint32]3405691582)  # 0xCAFEBABE as decimal

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsAviFileData -Data $data

                $result.Application | Should -Be 'SRSMaker'
                $result.FileName | Should -Be 'movie-sample.avi'
                $result.FileSize | Should -Be 12345678
                $result.Crc32 | Should -Be 3405691582
            }
        }

        It 'Handles empty app name' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $fileName = 'test.avi'

                $bw.Write([uint16]0)  # flags
                $bw.Write([uint16]0)  # empty app name
                $bw.Write([uint16]$fileName.Length)
                $bw.Write([System.Text.Encoding]::UTF8.GetBytes($fileName))
                $bw.Write([uint64]1000)
                $bw.Write([uint32]0x12345678)

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsAviFileData -Data $data

                $result.Application | Should -Be ''
                $result.FileName | Should -Be 'test.avi'
            }
        }
    }
}

Describe 'ConvertFrom-SrsAviTrackData' {

    Context 'Valid SRST data parsing' {

        It 'Parses track with standard flags' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0)  # flags
                $bw.Write([uint16]2)  # track number
                $bw.Write([uint32]10000)  # data length
                $bw.Write([uint64]256)  # match offset
                $bw.Write([uint16]3)  # signature length
                $bw.Write([byte[]]@(0xAA, 0xBB, 0xCC))

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsAviTrackData -Data $data

                $result.TrackNumber | Should -Be 2
                $result.DataLength | Should -Be 10000
                $result.MatchOffset | Should -Be 256
                $result.SignatureBytes.Length | Should -Be 3
            }
        }

        It 'Handles empty signature' {
            InModuleScope 'ReScenePS' {
                $ms = [System.IO.MemoryStream]::new()
                $bw = [System.IO.BinaryWriter]::new($ms)

                $bw.Write([uint16]0)  # flags
                $bw.Write([uint16]1)  # track number
                $bw.Write([uint32]5000)  # data length
                $bw.Write([uint64]0)  # match offset
                $bw.Write([uint16]0)  # no signature

                $bw.Flush()
                $data = $ms.ToArray()
                $bw.Dispose()
                $ms.Dispose()

                $result = ConvertFrom-SrsAviTrackData -Data $data

                $result.SignatureBytes.Length | Should -Be 0
            }
        }
    }
}
