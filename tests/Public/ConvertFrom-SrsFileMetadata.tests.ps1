#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for ConvertFrom-SrsFileMetadata function.

.DESCRIPTION
    Tests SRS file metadata parsing and error handling.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'SrsMetadataTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'ConvertFrom-SrsFileMetadata' {

    Context 'Parameter validation' {
        It 'Throws when SrsFilePath does not exist' {
            { ConvertFrom-SrsFileMetadata -SrsFilePath 'C:\NonExistent\sample.srs' } | Should -Throw '*not found*'
        }

        It 'Throws when file is empty' {
            $emptyFile = Join-Path $script:tempDir 'empty.srs'
            [System.IO.File]::WriteAllBytes($emptyFile, [byte[]]@())
            { ConvertFrom-SrsFileMetadata -SrsFilePath $emptyFile } | Should -Throw
        }
    }

    Context 'Invalid SRS format' {
        It 'Handles non-EBML file gracefully' {
            $invalidFile = Join-Path $script:tempDir 'invalid.srs'
            # Create file with random content that's not valid EBML
            $randomData = [byte[]](1..100)
            [System.IO.File]::WriteAllBytes($invalidFile, $randomData)

            # Should either throw or return empty metadata
            $result = $null
            try {
                $result = ConvertFrom-SrsFileMetadata -SrsFilePath $invalidFile
            }
            catch {
                # Expected - invalid format
            }

            # If it returns, FileData should be null or Tracks should be empty
            if ($result) {
                ($result.FileData -eq $null -or $result.Tracks.Count -eq 0) | Should -BeTrue
            }
        }
    }

    Context 'Return structure' {
        BeforeAll {
            # Create a minimal valid EBML SRS file structure
            # EBML Header + Segment with ReSample container
            $script:minimalSrs = Join-Path $script:tempDir 'minimal.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header (simplified)
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))  # EBML element ID
            $bw.Write([byte]0x84)  # Size = 4
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))  # EBMLVersion = 1

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))  # Segment ID
            $bw.Write([byte]0x80)  # Unknown size (minimal)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:minimalSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Returns hashtable with expected keys' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:minimalSrs
            $result.Keys | Should -Contain 'FileData'
            $result.Keys | Should -Contain 'Tracks'
            $result.Keys | Should -Contain 'SrsSize'
        }

        It 'Returns correct SrsSize' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:minimalSrs
            $fileSize = (Get-Item $script:minimalSrs).Length
            $result.SrsSize | Should -Be $fileSize
        }

        It 'Tracks is an array or empty' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:minimalSrs
            # Tracks can be empty array which PowerShell may evaluate differently
            ($result.Tracks -is [array] -or $result.Tracks.Count -eq 0) | Should -BeTrue
        }
    }

    Context 'Parsing ResampleFile element' {
        BeforeAll {
            # Create SRS file with ResampleFile element (0x6A75) at top level
            $script:fileDataSrs = Join-Path $script:tempDir 'filedata.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Build ResampleFile data
            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp')
            $sampleName = [System.Text.Encoding]::UTF8.GetBytes('sample.mkv')
            $fileDataBytes = [System.IO.MemoryStream]::new()
            $fdw = [System.IO.BinaryWriter]::new($fileDataBytes)
            $fdw.Write([uint16]0x0000)  # Flags
            $fdw.Write([uint16]$appName.Length)
            $fdw.Write($appName)
            $fdw.Write([uint16]$sampleName.Length)
            $fdw.Write($sampleName)
            $fdw.Write([uint64]1234567890)  # OriginalSize
            $fdw.Write([uint32]0x12345678)  # CRC32
            $fdw.Flush()
            $fileData = $fileDataBytes.ToArray()
            $fdw.Dispose()
            $fileDataBytes.Dispose()

            # Calculate segment size (ResampleFile element)
            $resampleFileSize = 2 + 1 + $fileData.Length  # ID + size byte + data

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))  # Segment ID
            $bw.Write([byte](0x80 + $resampleFileSize))  # Size

            # ResampleFile element (0x6A75)
            $bw.Write([byte[]]@(0x6A, 0x75))
            $bw.Write([byte](0x80 + $fileData.Length))
            $bw.Write($fileData)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:fileDataSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Parses ResampleFile data correctly' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:fileDataSrs
            $result.FileData | Should -Not -BeNullOrEmpty
        }

        It 'Extracts AppName from FileData' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:fileDataSrs
            $result.FileData.AppName | Should -Be 'TestApp'
        }

        It 'Extracts SampleName from FileData' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:fileDataSrs
            $result.FileData.SampleName | Should -Be 'sample.mkv'
        }

        It 'Extracts OriginalSize from FileData' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:fileDataSrs
            $result.FileData.OriginalSize | Should -Be 1234567890
        }

        It 'Extracts CRC32 from FileData' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:fileDataSrs
            $result.FileData.CRC32 | Should -Be 0x12345678
        }
    }

    Context 'Parsing ResampleTrack element' {
        BeforeAll {
            # Create SRS file with ResampleTrack element (0x6B75)
            $script:trackDataSrs = Join-Path $script:tempDir 'trackdata.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Build ResampleTrack data (standard: 2-byte track, 4-byte dataLength)
            $trackBytes = [System.IO.MemoryStream]::new()
            $tw = [System.IO.BinaryWriter]::new($trackBytes)
            $tw.Write([uint16]0x0000)  # Flags (no big track, no big file)
            $tw.Write([uint16]1)  # TrackNumber (2 bytes)
            $tw.Write([uint32]5000)  # DataLength (4 bytes)
            $tw.Write([uint64]0x1234)  # MatchOffset (8 bytes)
            $tw.Write([uint16]4)  # SignatureBytesLength
            $tw.Write([byte[]]@(0xDE, 0xAD, 0xBE, 0xEF))  # SignatureBytes
            $tw.Flush()
            $trackData = $trackBytes.ToArray()
            $tw.Dispose()
            $trackBytes.Dispose()

            # Calculate segment size
            $trackElemSize = 2 + 1 + $trackData.Length

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte](0x80 + $trackElemSize))

            # ResampleTrack element (0x6B75)
            $bw.Write([byte[]]@(0x6B, 0x75))
            $bw.Write([byte](0x80 + $trackData.Length))
            $bw.Write($trackData)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:trackDataSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Parses ResampleTrack data' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:trackDataSrs
            $result.Tracks.Count | Should -BeGreaterThan 0
        }

        It 'Extracts TrackNumber' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:trackDataSrs
            $result.Tracks[0].TrackNumber | Should -Be 1
        }

        It 'Extracts DataLength' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:trackDataSrs
            $result.Tracks[0].DataLength | Should -Be 5000
        }

        It 'Extracts MatchOffset' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:trackDataSrs
            $result.Tracks[0].MatchOffset | Should -Be 0x1234
        }

        It 'Extracts SignatureBytes' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:trackDataSrs
            $result.Tracks[0].SignatureBytes | Should -Be @(0xDE, 0xAD, 0xBE, 0xEF)
        }
    }

    Context 'Parsing ResampleTrack with BigTrack flag' {
        BeforeAll {
            # Create SRS with BigTrack flag (0x0008) set
            $script:bigTrackSrs = Join-Path $script:tempDir 'bigtrack.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Build ResampleTrack with BigTrack flag
            $trackBytes = [System.IO.MemoryStream]::new()
            $tw = [System.IO.BinaryWriter]::new($trackBytes)
            $tw.Write([uint16]0x0008)  # Flags: BigTrack
            $tw.Write([uint32]12345)  # TrackNumber (4 bytes due to BigTrack)
            $tw.Write([uint32]8000)  # DataLength (4 bytes)
            $tw.Write([uint64]0x5678)  # MatchOffset
            $tw.Write([uint16]0)  # SignatureBytesLength = 0
            $tw.Flush()
            $trackData = $trackBytes.ToArray()
            $tw.Dispose()
            $trackBytes.Dispose()

            $trackElemSize = 2 + 1 + $trackData.Length

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte](0x80 + $trackElemSize))

            # ResampleTrack element
            $bw.Write([byte[]]@(0x6B, 0x75))
            $bw.Write([byte](0x80 + $trackData.Length))
            $bw.Write($trackData)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:bigTrackSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Parses track with BigTrack flag' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:bigTrackSrs
            $result.Tracks.Count | Should -Be 1
        }

        It 'Reads 4-byte TrackNumber with BigTrack flag' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:bigTrackSrs
            $result.Tracks[0].TrackNumber | Should -Be 12345
        }
    }

    Context 'Parsing ResampleTrack with BigFile flag' {
        BeforeAll {
            # Create SRS with BigFile flag (0x0004) set
            $script:bigFileSrs = Join-Path $script:tempDir 'bigfile.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Build ResampleTrack with BigFile flag
            $trackBytes = [System.IO.MemoryStream]::new()
            $tw = [System.IO.BinaryWriter]::new($trackBytes)
            $tw.Write([uint16]0x0004)  # Flags: BigFile
            $tw.Write([uint16]2)  # TrackNumber (2 bytes)
            $tw.Write([uint64]9876543210)  # DataLength (8 bytes due to BigFile)
            $tw.Write([uint64]0xABCD)  # MatchOffset
            $tw.Write([uint16]0)  # SignatureBytesLength = 0
            $tw.Flush()
            $trackData = $trackBytes.ToArray()
            $tw.Dispose()
            $trackBytes.Dispose()

            $trackElemSize = 2 + 1 + $trackData.Length

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte](0x80 + $trackElemSize))

            # ResampleTrack element
            $bw.Write([byte[]]@(0x6B, 0x75))
            $bw.Write([byte](0x80 + $trackData.Length))
            $bw.Write($trackData)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:bigFileSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Parses track with BigFile flag' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:bigFileSrs
            $result.Tracks.Count | Should -Be 1
        }

        It 'Reads 8-byte DataLength with BigFile flag' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:bigFileSrs
            $result.Tracks[0].DataLength | Should -Be 9876543210
        }
    }

    Context 'Parsing ReSample container' {
        BeforeAll {
            # Create SRS with full ReSample container (0x1F697576)
            $script:containerSrs = Join-Path $script:tempDir 'container.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Build ResampleFile inside container
            $appName = [System.Text.Encoding]::UTF8.GetBytes('App')
            $sampleName = [System.Text.Encoding]::UTF8.GetBytes('file.mkv')
            $fileDataBytes = [System.IO.MemoryStream]::new()
            $fdw = [System.IO.BinaryWriter]::new($fileDataBytes)
            $fdw.Write([uint16]0x0000)
            $fdw.Write([uint16]$appName.Length)
            $fdw.Write($appName)
            $fdw.Write([uint16]$sampleName.Length)
            $fdw.Write($sampleName)
            $fdw.Write([uint64]999999)
            $fdw.Write([uint32]0x12345678)
            $fdw.Flush()
            $fileData = $fileDataBytes.ToArray()
            $fdw.Dispose()
            $fileDataBytes.Dispose()

            # Build ResampleTrack inside container
            $trackBytes = [System.IO.MemoryStream]::new()
            $tw = [System.IO.BinaryWriter]::new($trackBytes)
            $tw.Write([uint16]0x0000)
            $tw.Write([uint16]1)
            $tw.Write([uint32]2000)
            $tw.Write([uint64]0x100)
            $tw.Write([uint16]0)
            $tw.Flush()
            $trackData = $trackBytes.ToArray()
            $tw.Dispose()
            $trackBytes.Dispose()

            # Container content
            $containerContent = [System.IO.MemoryStream]::new()
            $ccw = [System.IO.BinaryWriter]::new($containerContent)
            # ResampleFile (0x6A75)
            $ccw.Write([byte[]]@(0x6A, 0x75))
            $ccw.Write([byte](0x80 + $fileData.Length))
            $ccw.Write($fileData)
            # ResampleTrack (0x6B75)
            $ccw.Write([byte[]]@(0x6B, 0x75))
            $ccw.Write([byte](0x80 + $trackData.Length))
            $ccw.Write($trackData)
            $ccw.Flush()
            $containerData = $containerContent.ToArray()
            $ccw.Dispose()
            $containerContent.Dispose()

            # ReSample container size
            $containerSize = 4 + 1 + $containerData.Length

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte](0x80 + $containerSize))

            # ReSample container (0x1F697576)
            $bw.Write([byte[]]@(0x1F, 0x69, 0x75, 0x76))
            $bw.Write([byte](0x80 + $containerData.Length))
            $bw.Write($containerData)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:containerSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Parses ReSample container' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:containerSrs
            $result.FileData | Should -Not -BeNullOrEmpty
            $result.Tracks.Count | Should -Be 1
        }

        It 'Extracts FileData from container' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:containerSrs
            $result.FileData.SampleName | Should -Be 'file.mkv'
            $result.FileData.CRC32 | Should -Be 0x12345678
        }

        It 'Extracts TrackData from container' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:containerSrs
            $result.Tracks[0].DataLength | Should -Be 2000
        }
    }

    Context 'Fallback scanning with 0xC0/0xC1/0xC2 format' {
        BeforeAll {
            # Create an SRS file that triggers the fallback scanning logic
            # The fallback looks for 0xC0 (ReSample container), 0xC1 (FileData), 0xC2 (TrackData)
            $script:fallbackSrs = Join-Path $script:tempDir 'fallback.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header (minimal, but valid enough to not throw on magic check)
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Segment with unknown size (forces fallback scanning)
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte]0xFF)  # Unknown size marker

            # Some padding before the 0xC0 container
            $bw.Write([byte[]]@(0x00, 0x00, 0x00))

            # 0xC0 = ReSample container in fallback format
            $bw.Write([byte]0xC0)

            # Build container content with 0xC1 (FileData) and 0xC2 (TrackData)
            $containerContent = [System.IO.MemoryStream]::new()
            $ccw = [System.IO.BinaryWriter]::new($containerContent)

            # 0xC1 = ResampleFile in fallback format
            $appName = [System.Text.Encoding]::UTF8.GetBytes('FallbackApp')
            $sampleName = [System.Text.Encoding]::UTF8.GetBytes('fallback.mkv')
            $fileDataBytes = [System.IO.MemoryStream]::new()
            $fdw = [System.IO.BinaryWriter]::new($fileDataBytes)
            $fdw.Write([uint16]0x0000)  # Flags
            $fdw.Write([uint16]$appName.Length)
            $fdw.Write($appName)
            $fdw.Write([uint16]$sampleName.Length)
            $fdw.Write($sampleName)
            $fdw.Write([uint64]555555)  # OriginalSize
            $fdw.Write([uint32]0x11223344)  # CRC32
            $fdw.Flush()
            $fileData = $fileDataBytes.ToArray()
            $fdw.Dispose()
            $fileDataBytes.Dispose()

            $ccw.Write([byte]0xC1)  # FileData element
            $ccw.Write([byte](0x80 + $fileData.Length))  # Size
            $ccw.Write($fileData)

            # 0xC2 = ResampleTrack in fallback format
            $trackBytes = [System.IO.MemoryStream]::new()
            $tw = [System.IO.BinaryWriter]::new($trackBytes)
            $tw.Write([uint16]0x0000)  # Flags
            $tw.Write([uint16]3)  # TrackNumber
            $tw.Write([uint32]7777)  # DataLength
            $tw.Write([uint64]0x9999)  # MatchOffset
            $tw.Write([uint16]0)  # SignatureBytesLength
            $tw.Flush()
            $trackData = $trackBytes.ToArray()
            $tw.Dispose()
            $trackBytes.Dispose()

            $ccw.Write([byte]0xC2)  # TrackData element
            $ccw.Write([byte](0x80 + $trackData.Length))
            $ccw.Write($trackData)

            $ccw.Flush()
            $containerData = $containerContent.ToArray()
            $ccw.Dispose()
            $containerContent.Dispose()

            # Write container size and data
            $bw.Write([byte](0x80 + $containerData.Length))
            $bw.Write($containerData)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:fallbackSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Falls back to scanning and parses 0xC0 container' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:fallbackSrs
            $result.FileData | Should -Not -BeNullOrEmpty
        }

        It 'Parses 0xC1 FileData element in fallback mode' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:fallbackSrs
            $result.FileData.AppName | Should -Be 'FallbackApp'
            $result.FileData.SampleName | Should -Be 'fallback.mkv'
            $result.FileData.OriginalSize | Should -Be 555555
            $result.FileData.CRC32 | Should -Be 0x11223344
        }

        It 'Parses 0xC2 TrackData element in fallback mode' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:fallbackSrs
            $result.Tracks.Count | Should -Be 1
            $result.Tracks[0].TrackNumber | Should -Be 3
            $result.Tracks[0].DataLength | Should -Be 7777
            $result.Tracks[0].MatchOffset | Should -Be 0x9999
        }
    }

    Context 'Multiple tracks' {
        BeforeAll {
            $script:multiTrackSrs = Join-Path $script:tempDir 'multitrack.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Build two ResampleTrack elements
            $trackData1 = [System.IO.MemoryStream]::new()
            $tw1 = [System.IO.BinaryWriter]::new($trackData1)
            $tw1.Write([uint16]0x0000)
            $tw1.Write([uint16]1)
            $tw1.Write([uint32]1000)
            $tw1.Write([uint64]0x100)
            $tw1.Write([uint16]0)
            $tw1.Flush()
            $track1 = $trackData1.ToArray()
            $tw1.Dispose()
            $trackData1.Dispose()

            $trackData2 = [System.IO.MemoryStream]::new()
            $tw2 = [System.IO.BinaryWriter]::new($trackData2)
            $tw2.Write([uint16]0x0000)
            $tw2.Write([uint16]2)
            $tw2.Write([uint32]2000)
            $tw2.Write([uint64]0x200)
            $tw2.Write([uint16]0)
            $tw2.Flush()
            $track2 = $trackData2.ToArray()
            $tw2.Dispose()
            $trackData2.Dispose()

            # Calculate total size
            $elem1Size = 2 + 1 + $track1.Length
            $elem2Size = 2 + 1 + $track2.Length
            $totalSize = $elem1Size + $elem2Size

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte](0x80 + $totalSize))

            # First track
            $bw.Write([byte[]]@(0x6B, 0x75))
            $bw.Write([byte](0x80 + $track1.Length))
            $bw.Write($track1)

            # Second track
            $bw.Write([byte[]]@(0x6B, 0x75))
            $bw.Write([byte](0x80 + $track2.Length))
            $bw.Write($track2)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:multiTrackSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Parses multiple tracks' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:multiTrackSrs
            $result.Tracks.Count | Should -Be 2
        }

        It 'Correctly identifies each track number' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:multiTrackSrs
            $result.Tracks[0].TrackNumber | Should -Be 1
            $result.Tracks[1].TrackNumber | Should -Be 2
        }

        It 'Correctly parses each track DataLength' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:multiTrackSrs
            $result.Tracks[0].DataLength | Should -Be 1000
            $result.Tracks[1].DataLength | Should -Be 2000
        }
    }

    Context 'Skip unknown elements' {
        BeforeAll {
            $script:unknownElemSrs = Join-Path $script:tempDir 'unknown.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Build track data
            $trackBytes = [System.IO.MemoryStream]::new()
            $tw = [System.IO.BinaryWriter]::new($trackBytes)
            $tw.Write([uint16]0x0000)
            $tw.Write([uint16]5)
            $tw.Write([uint32]9999)
            $tw.Write([uint64]0x5555)
            $tw.Write([uint16]0)
            $tw.Flush()
            $trackData = $trackBytes.ToArray()
            $tw.Dispose()
            $trackBytes.Dispose()

            # Unknown element (0xBF = some random ID)
            $unknownData = [byte[]]@(0x01, 0x02, 0x03, 0x04, 0x05)
            $unknownElemSize = 1 + 1 + $unknownData.Length

            # Track element
            $trackElemSize = 2 + 1 + $trackData.Length

            $totalSize = $unknownElemSize + $trackElemSize

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte](0x80 + $totalSize))

            # Unknown element first
            $bw.Write([byte]0xBF)
            $bw.Write([byte](0x80 + $unknownData.Length))
            $bw.Write($unknownData)

            # Then track element
            $bw.Write([byte[]]@(0x6B, 0x75))
            $bw.Write([byte](0x80 + $trackData.Length))
            $bw.Write($trackData)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:unknownElemSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Skips unknown elements and continues parsing' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:unknownElemSrs
            $result.Tracks.Count | Should -Be 1
            $result.Tracks[0].TrackNumber | Should -Be 5
        }
    }

    Context 'Combined BigTrack and BigFile flags' {
        BeforeAll {
            $script:bothFlagsSrs = Join-Path $script:tempDir 'bothflags.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Build ResampleTrack with both flags
            $trackBytes = [System.IO.MemoryStream]::new()
            $tw = [System.IO.BinaryWriter]::new($trackBytes)
            $tw.Write([uint16]0x000C)  # Flags: BigTrack (0x8) + BigFile (0x4)
            $tw.Write([uint32]99999)  # TrackNumber (4 bytes due to BigTrack)
            $tw.Write([uint64]8888888888)  # DataLength (8 bytes due to BigFile)
            $tw.Write([uint64]0x7777)  # MatchOffset
            $tw.Write([uint16]2)  # SignatureBytesLength
            $tw.Write([byte[]]@(0xAA, 0xBB))  # SignatureBytes
            $tw.Flush()
            $trackData = $trackBytes.ToArray()
            $tw.Dispose()
            $trackBytes.Dispose()

            $trackElemSize = 2 + 1 + $trackData.Length

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte](0x80 + $trackElemSize))

            # ResampleTrack element
            $bw.Write([byte[]]@(0x6B, 0x75))
            $bw.Write([byte](0x80 + $trackData.Length))
            $bw.Write($trackData)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:bothFlagsSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Parses track with both BigTrack and BigFile flags' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:bothFlagsSrs
            $result.Tracks.Count | Should -Be 1
        }

        It 'Reads 4-byte TrackNumber correctly' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:bothFlagsSrs
            $result.Tracks[0].TrackNumber | Should -Be 99999
        }

        It 'Reads 8-byte DataLength correctly' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:bothFlagsSrs
            $result.Tracks[0].DataLength | Should -Be 8888888888
        }

        It 'Reads signature bytes correctly' {
            $result = ConvertFrom-SrsFileMetadata -SrsFilePath $script:bothFlagsSrs
            $result.Tracks[0].SignatureBytes | Should -Be @(0xAA, 0xBB)
        }
    }
}
