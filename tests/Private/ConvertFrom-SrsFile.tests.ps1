#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for ConvertFrom-SrsFile function.

.DESCRIPTION
    Tests MKV SRS file parsing including EBML element handling
    and ReSampleFile/ReSampleTrack element extraction.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'SrsFileTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'ConvertFrom-SrsFile' {

    Context 'File existence checks' {

        It 'Throws when file does not exist' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $missingFile = Join-Path $dir 'nonexistent.srs'

                { ConvertFrom-SrsFile -FilePath $missingFile } | Should -Throw "*not found*"
            }
        }
    }

    Context 'Valid MKV SRS parsing' {

        BeforeAll {
            # Build a minimal valid MKV SRS structure
            # EBML Header + Segment containing ReSampleFile (0xC1) element
            $script:validMkvSrs = Join-Path $script:tempDir 'valid.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header element (ID: 0x1A45DFA3)
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            # EBML header size (using VINT encoding, 0x80 | size for sizes < 127)
            $ebmlHeaderContent = [byte[]]@(
                0x42, 0x86, 0x81, 0x01,  # EBMLVersion = 1
                0x42, 0xF7, 0x81, 0x01,  # EBMLReadVersion = 1
                0x42, 0xF2, 0x81, 0x04,  # EBMLMaxIDLength = 4
                0x42, 0xF3, 0x81, 0x08,  # EBMLMaxSizeLength = 8
                0x42, 0x82, 0x84, 0x6D, 0x61, 0x74, 0x72  # DocType = "matr" (partial)
            )
            $bw.Write([byte](0x80 -bor $ebmlHeaderContent.Length))
            $bw.Write($ebmlHeaderContent)

            # Segment element (ID: 0x18538067)
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))

            # Build ReSampleFile (0xC1) element content
            $appName = 'ReSample'
            $fileName = 'movie.mkv'

            $fileDataMs = [System.IO.MemoryStream]::new()
            $fileDataBw = [System.IO.BinaryWriter]::new($fileDataMs)
            $fileDataBw.Write([uint16]0)  # flags
            $fileDataBw.Write([uint16]$appName.Length)
            $fileDataBw.Write([System.Text.Encoding]::ASCII.GetBytes($appName))
            $fileDataBw.Write([uint16]$fileName.Length)
            $fileDataBw.Write([System.Text.Encoding]::ASCII.GetBytes($fileName))
            $fileDataBw.Write([uint32]50000000)  # original size (4 bytes, no BIG_FILE flag)
            $fileDataBw.Write([uint32]2882400001)  # CRC32 (0xABCDEF01 as decimal)
            $fileDataBw.Flush()
            $fileDataContent = $fileDataMs.ToArray()
            $fileDataBw.Dispose()
            $fileDataMs.Dispose()

            # Build ReSampleTrack (0xC2) element content
            $trackDataMs = [System.IO.MemoryStream]::new()
            $trackDataBw = [System.IO.BinaryWriter]::new($trackDataMs)
            $trackDataBw.Write([uint16]0)  # flags
            $trackDataBw.Write([uint16]1)  # track number
            $trackDataBw.Write([uint32]25000)  # data length
            $trackDataBw.Write([uint64]1024)  # match offset
            $trackDataBw.Write([uint16]4)  # signature length
            $trackDataBw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))  # signature bytes
            $trackDataBw.Flush()
            $trackDataContent = $trackDataMs.ToArray()
            $trackDataBw.Dispose()
            $trackDataMs.Dispose()

            # Calculate segment size
            $segmentContentSize = 1 + 1 + $fileDataContent.Length + 1 + 1 + $trackDataContent.Length

            # Write segment size (unknown size: 0x01FFFFFFFFFFFFFF for simplicity, or exact size)
            # Using exact size with VINT encoding
            if ($segmentContentSize -lt 127) {
                $bw.Write([byte](0x80 -bor $segmentContentSize))
            }
            else {
                # Use 2-byte VINT
                $bw.Write([byte](0x40 -bor ($segmentContentSize -shr 8)))
                $bw.Write([byte]($segmentContentSize -band 0xFF))
            }

            # ReSampleFile element (ID: 0xC1)
            $bw.Write([byte]0xC1)
            $bw.Write([byte](0x80 -bor $fileDataContent.Length))
            $bw.Write($fileDataContent)

            # ReSampleTrack element (ID: 0xC2)
            $bw.Write([byte]0xC2)
            $bw.Write([byte](0x80 -bor $trackDataContent.Length))
            $bw.Write($trackDataContent)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:validMkvSrs, $ms.ToArray())

            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Parses valid MKV SRS file' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:validMkvSrs } {
                $result = ConvertFrom-SrsFile -FilePath $file

                $result | Should -Not -BeNullOrEmpty
                $result.RawBytes | Should -Not -BeNullOrEmpty
                $result.SegmentDataOffset | Should -BeGreaterThan 0
            }
        }

        It 'Returns structured result with FileMetadata field' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:validMkvSrs } {
                $result = ConvertFrom-SrsFile -FilePath $file

                # FileMetadata property should exist (may be null if elements not found)
                $result.PSObject.Properties.Name | Should -Contain 'FileMetadata'
            }
        }

        It 'Returns structured result with Tracks property' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:validMkvSrs } {
                $result = ConvertFrom-SrsFile -FilePath $file

                # Tracks property should exist
                $result.PSObject.Properties.Name | Should -Contain 'Tracks'
            }
        }
    }

    Context 'Empty or minimal files' {

        BeforeAll {
            # Create minimal EBML file with just header
            $script:minimalSrs = Join-Path $script:tempDir 'minimal.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x80)  # size = 0

            # Empty Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte]0x80)  # size = 0

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:minimalSrs, $ms.ToArray())

            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Handles SRS with no metadata gracefully' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:minimalSrs } {
                $result = ConvertFrom-SrsFile -FilePath $file

                $result | Should -Not -BeNullOrEmpty
                $result.FileMetadata | Should -BeNullOrEmpty
                $result.Tracks.Count | Should -Be 0
            }
        }
    }
}
