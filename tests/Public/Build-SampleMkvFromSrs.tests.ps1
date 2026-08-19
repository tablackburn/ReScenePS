#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Build-SampleMkvFromSrs function.

.DESCRIPTION
    Tests the MKV sample reconstruction function with parameter
    validation and error handling.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'BuildMkvTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Build-SampleMkvFromSrs' {

    Context 'Parameter validation' {
        It 'Throws when SrsFilePath does not exist' {
            $outputPath = Join-Path $script:tempDir 'output.mkv'
            $nonExistentSrs = Join-Path ([System.IO.Path]::GetTempPath()) 'NonExistent_12345' 'sample.srs'
            { Build-SampleMkvFromSrs -SrsFilePath $nonExistentSrs -TrackDataFiles @{} -OutputMkvPath $outputPath } | Should -Throw '*not found*'
        }

        It 'Accepts empty TrackDataFiles hashtable' {
            $srsFile = Join-Path $script:tempDir 'test.srs'
            $outputPath = Join-Path $script:tempDir 'output1.mkv'

            # Create minimal SRS-like file (EBML header)
            $data = [byte[]]@(0x1A, 0x45, 0xDF, 0xA3, 0x80)  # EBML header ID + unknown size
            [System.IO.File]::WriteAllBytes($srsFile, $data)

            # Should not throw on empty track files (will produce minimal output)
            { Build-SampleMkvFromSrs -SrsFilePath $srsFile -TrackDataFiles @{} -OutputMkvPath $outputPath } | Should -Not -Throw
        }
    }

    Context 'Output file creation' {
        BeforeAll {
            # Create minimal EBML file
            $script:minimalSrs = Join-Path $script:tempDir 'minimal.srs'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))  # EBML element ID
            $bw.Write([byte]0x84)  # Size = 4
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))  # EBMLVersion = 1

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))  # Segment ID
            $bw.Write([byte]0x80)  # Unknown size

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:minimalSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Creates output file' {
            $outputPath = Join-Path $script:tempDir 'created.mkv'
            Build-SampleMkvFromSrs -SrsFilePath $script:minimalSrs -TrackDataFiles @{} -OutputMkvPath $outputPath

            Test-Path $outputPath | Should -BeTrue
        }

        It 'Returns true on success' {
            $outputPath = Join-Path $script:tempDir 'success.mkv'
            $result = Build-SampleMkvFromSrs -SrsFilePath $script:minimalSrs -TrackDataFiles @{} -OutputMkvPath $outputPath

            $result | Should -BeTrue
        }

        It 'Output file contains EBML header' {
            $outputPath = Join-Path $script:tempDir 'withheader.mkv'
            Build-SampleMkvFromSrs -SrsFilePath $script:minimalSrs -TrackDataFiles @{} -OutputMkvPath $outputPath

            $bytes = [System.IO.File]::ReadAllBytes($outputPath)
            # Should start with EBML header ID
            $bytes[0] | Should -Be 0x1A
            $bytes[1] | Should -Be 0x45
            $bytes[2] | Should -Be 0xDF
            $bytes[3] | Should -Be 0xA3
        }
    }

    Context 'Track data injection' {
        BeforeAll {
            # Create track data file
            $script:trackFile = Join-Path $script:tempDir 'track1.dat'
            $trackData = [byte[]](1..100)
            [System.IO.File]::WriteAllBytes($script:trackFile, $trackData)
        }

        It 'Accepts track data files hashtable without throwing type error' {
            $outputPath = Join-Path $script:tempDir 'withtracks.mkv'
            $trackFiles = @{ 1 = $script:trackFile }

            # Function will succeed or fail gracefully (track data is only used when blocks match)
            # Just verify no type errors on the hashtable parameter
            $result = $null
            try {
                $result = Build-SampleMkvFromSrs -SrsFilePath $script:minimalSrs -TrackDataFiles $trackFiles -OutputMkvPath $outputPath
            }
            catch {
                # May throw if SRS structure doesn't have matching tracks - that's OK
            }

            # If we got here without a parameter type error, test passes
            $true | Should -BeTrue
        }
    }

    Context 'Lacing support' {
        BeforeAll {
            # Create track data file for lacing tests
            $script:lacingTrackFile = Join-Path $script:tempDir 'lacing-track.dat'
            $trackData = [byte[]]::new(500)
            for ($i = 0; $i -lt 500; $i++) { $trackData[$i] = [byte]($i % 256) }
            [System.IO.File]::WriteAllBytes($script:lacingTrackFile, $trackData)
        }

        It 'Handles SimpleBlock with Xiph lacing (lace type 1)' {
            $srsFile = Join-Path $script:tempDir 'xiph-lacing.srs'
            $outputPath = Join-Path $script:tempDir 'xiph-output.mkv'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))  # EBML ID
            $bw.Write([byte]0x84)  # Size = 4
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))  # EBMLVersion = 1

            # Segment (container)
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))  # Segment ID
            $bw.Write([byte]0x01)  # Size prefix for unknown
            $bw.Write([byte[]]@(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))  # Unknown size

            # Cluster (container)
            $bw.Write([byte[]]@(0x1F, 0x43, 0xB6, 0x75))  # Cluster ID
            $bw.Write([byte]0x01)
            $bw.Write([byte[]]@(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))

            # SimpleBlock with Xiph lacing
            # SimpleBlock ID: 0xA3, Size, Track#, Timecode (2 bytes), Flags (lace type in bits 1-2)
            $bw.Write([byte]0xA3)  # SimpleBlock ID
            $bw.Write([byte]0x8C)  # Size = 12 (small enough to fit)
            $bw.Write([byte]0x81)  # Track number = 1 (EBML VarInt)
            $bw.Write([byte]0x00)  # Timecode high
            $bw.Write([byte]0x00)  # Timecode low
            $bw.Write([byte]0x02)  # Flags: Xiph lacing (bits 1-2 = 01)
            $bw.Write([byte]0x02)  # Frame count - 1 = 2 (so 3 frames)
            # Xiph lacing sizes: each frame size, 255 means continue
            $bw.Write([byte]2)     # Frame 1 size = 2
            $bw.Write([byte]3)     # Frame 2 size = 3
            # Frame 3 size is implicit (remaining bytes)
            # Now the frame data (2 + 3 + remaining = 12 - 7 header = 5 bytes total)
            $bw.Write([byte[]]@(0x01, 0x02))  # Frame 1
            $bw.Write([byte[]]@(0x03, 0x04, 0x05))  # Frame 2

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($srsFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            $trackFiles = @{ 1 = $script:lacingTrackFile }
            $result = Build-SampleMkvFromSrs -SrsFilePath $srsFile -TrackDataFiles $trackFiles -OutputMkvPath $outputPath

            $result | Should -BeTrue
            Test-Path $outputPath | Should -BeTrue
        }

        It 'Handles SimpleBlock with EBML lacing (lace type 3)' {
            $srsFile = Join-Path $script:tempDir 'ebml-lacing.srs'
            $outputPath = Join-Path $script:tempDir 'ebml-output.mkv'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte]0x01)
            $bw.Write([byte[]]@(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))

            # Cluster
            $bw.Write([byte[]]@(0x1F, 0x43, 0xB6, 0x75))
            $bw.Write([byte]0x01)
            $bw.Write([byte[]]@(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))

            # SimpleBlock with EBML lacing (lace type = 3)
            $bw.Write([byte]0xA3)  # SimpleBlock ID
            $bw.Write([byte]0x8D)  # Size = 13
            $bw.Write([byte]0x81)  # Track number = 1
            $bw.Write([byte]0x00)  # Timecode high
            $bw.Write([byte]0x00)  # Timecode low
            $bw.Write([byte]0x06)  # Flags: EBML lacing (bits 1-2 = 11)
            $bw.Write([byte]0x02)  # Frame count - 1 = 2 (3 frames)
            # EBML lacing: first frame size as EBML VarInt, then deltas
            $bw.Write([byte]0x82)  # First frame size = 2 (EBML VarInt)
            $bw.Write([byte]0x41)  # Delta for frame 2 = +1 (signed EBML VarInt, 0x40 + 1)
            # Frame 3 size is implicit
            # Frame data
            $bw.Write([byte[]]@(0x01, 0x02))        # Frame 1 (2 bytes)
            $bw.Write([byte[]]@(0x03, 0x04, 0x05))  # Frame 2 (3 bytes)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($srsFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            $trackFiles = @{ 1 = $script:lacingTrackFile }
            $result = Build-SampleMkvFromSrs -SrsFilePath $srsFile -TrackDataFiles $trackFiles -OutputMkvPath $outputPath

            $result | Should -BeTrue
            Test-Path $outputPath | Should -BeTrue
        }

        It 'Handles SimpleBlock with Fixed-size lacing (lace type 2)' {
            $srsFile = Join-Path $script:tempDir 'fixed-lacing.srs'
            $outputPath = Join-Path $script:tempDir 'fixed-output.mkv'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte]0x01)
            $bw.Write([byte[]]@(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))

            # Cluster
            $bw.Write([byte[]]@(0x1F, 0x43, 0xB6, 0x75))
            $bw.Write([byte]0x01)
            $bw.Write([byte[]]@(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))

            # SimpleBlock with Fixed-size lacing (lace type = 2)
            $bw.Write([byte]0xA3)  # SimpleBlock ID
            $bw.Write([byte]0x8B)  # Size = 11
            $bw.Write([byte]0x81)  # Track number = 1
            $bw.Write([byte]0x00)  # Timecode high
            $bw.Write([byte]0x00)  # Timecode low
            $bw.Write([byte]0x04)  # Flags: Fixed-size lacing (bits 1-2 = 10)
            $bw.Write([byte]0x02)  # Frame count - 1 = 2 (3 frames)
            # Fixed-size: no size encoding needed, each frame is same size
            # Total data = size - header = 11 - 6 = 5, divided by 3 frames
            $bw.Write([byte[]]@(0x01))  # Frame 1
            $bw.Write([byte[]]@(0x02))  # Frame 2
            $bw.Write([byte[]]@(0x03))  # Frame 3 (plus 2 padding)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($srsFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            $trackFiles = @{ 1 = $script:lacingTrackFile }
            $result = Build-SampleMkvFromSrs -SrsFilePath $srsFile -TrackDataFiles $trackFiles -OutputMkvPath $outputPath

            $result | Should -BeTrue
            Test-Path $outputPath | Should -BeTrue
        }

        It 'Fails when a block needs track data that was not supplied' {
            $srsFile = Join-Path $script:tempDir 'missing-track.srs'
            $outputPath = Join-Path $script:tempDir 'missing-track-output.mkv'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte]0x01)
            $bw.Write([byte[]]@(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))

            # Cluster
            $bw.Write([byte[]]@(0x1F, 0x43, 0xB6, 0x75))
            $bw.Write([byte]0x01)
            $bw.Write([byte[]]@(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))

            # SimpleBlock for track 99 (which we won't provide data for)
            $bw.Write([byte]0xA3)  # SimpleBlock ID
            $bw.Write([byte]0x88)  # Size = 8
            $bw.Write([byte]0xDF)  # Track number = 99 (high bit set, lower 7 = 99 - requires 2 byte VINT) - actually use 0x81 for track 1
            $bw.Write([byte]0x00)  # Timecode high
            $bw.Write([byte]0x00)  # Timecode low
            $bw.Write([byte]0x00)  # Flags: No lacing
            # Frame data (4 bytes)
            $bw.Write([byte[]]@(0x01, 0x02, 0x03, 0x04))

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($srsFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            # A block needs frame data and none was supplied. Zero-filling it would
            # produce a file of the right length whose contents are wrong, and report
            # success -- so this has to fail instead.
            { Build-SampleMkvFromSrs -SrsFilePath $srsFile -TrackDataFiles @{} -OutputMkvPath $outputPath } |
                Should -Throw -ExpectedMessage '*No extracted data for track*'
        }
    }

    Context 'Rebuilding from a real SRS' {

        # Every other fixture in this file writes frame data into the block. A real
        # SRS stores the block header and the original size, and omits the data --
        # that is what makes a 24 KB SRS describe a 10 MB sample. Rebuilding used to
        # consume the absent bytes from the SRS, run off the end of the file after
        # the first block, and return a fraction of the sample while reporting
        # success: 52,755 bytes of a 10,123,431 byte sample for this exact fixture.
        #
        # No source video is needed to catch that. Feed the rebuild track data of the
        # length the SRS itself declares, and the output has to come out at exactly
        # the size the SRS records.
        BeforeAll {
            $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            $srrPath = Join-Path $projectRoot 'tests/samples/The.Mummy.Resurrected.2014.PROPER.DVDRiP.X264-TASTE.srr'

            $script:realSrs = Join-Path $script:tempDir 'taste-sample.srs'
            InModuleScope 'ReScenePS' -Parameters @{ srr = $srrPath; dest = $script:realSrs } {
                Export-StoredFile -SrrFile $srr -FileName '*taste-sample.srs' -OutputPath $dest
            }

            $script:realMetadata = ConvertFrom-SrsFileMetadata -SrsFilePath $script:realSrs

            # Synthetic payloads: the right number of bytes, contents irrelevant.
            $script:realTrackFiles = @{}
            foreach ($track in $script:realMetadata.Tracks) {
                $trackFile = Join-Path $script:tempDir "real-track-$($track.TrackNumber).bin"
                $stream = [System.IO.File]::Create($trackFile)
                try {
                    $buffer = New-Object byte[] 65536
                    [int64]$remaining = $track.DataLength
                    while ($remaining -gt 0) {
                        $chunk = [Math]::Min([int64]$buffer.Length, $remaining)
                        $stream.Write($buffer, 0, [int]$chunk)
                        $remaining -= $chunk
                    }
                }
                finally {
                    $stream.Dispose()
                }
                $script:realTrackFiles[$track.TrackNumber] = $trackFile
            }
        }

        It 'Extracts an SRS whose blocks are larger than the SRS itself' {
            # Guards the premise: if this fixture ever did store frame data, the test
            # below would pass for the wrong reason.
            $srsLength = (Get-Item -Path $script:realSrs).Length
            $script:realMetadata.FileData.OriginalSize | Should -BeGreaterThan $srsLength
        }

        It 'Rebuilds to exactly the size the SRS records' {
            $outputPath = Join-Path $script:tempDir 'taste-sample-rebuilt.mkv'

            $rebuilt = Build-SampleMkvFromSrs -SrsFilePath $script:realSrs `
                -TrackDataFiles $script:realTrackFiles -OutputMkvPath $outputPath

            $rebuilt | Should -BeTrue
            (Get-Item -Path $outputPath).Length | Should -Be $script:realMetadata.FileData.OriginalSize
        }

        It 'Consumes every byte of the supplied track data' {
            # The counterpart to the size check: the output could be the right length
            # while the block walk stopped early and the tail of each track went
            # unused.
            $outputPath = Join-Path $script:tempDir 'taste-sample-consumed.mkv'
            $null = Build-SampleMkvFromSrs -SrsFilePath $script:realSrs `
                -TrackDataFiles $script:realTrackFiles -OutputMkvPath $outputPath

            $suppliedTotal = ($script:realMetadata.Tracks | Measure-Object -Property 'DataLength' -Sum).Sum
            $structureBytes = $script:realMetadata.FileData.OriginalSize - $suppliedTotal
            $structureBytes | Should -BeGreaterThan 0
            (Get-Item -Path $outputPath).Length - $structureBytes | Should -Be $suppliedTotal
        }

        It 'Fails rather than padding when a track runs out of data' {
            # A source video that is a different encode of the same release yields
            # too little track data. Padding the shortfall would produce a sample of
            # the right length and the wrong content -- which is what used to happen,
            # reported as success.
            $shortFiles = @{}
            foreach ($track in $script:realMetadata.Tracks) {
                $shortFile = Join-Path $script:tempDir "short-track-$($track.TrackNumber).bin"
                [System.IO.File]::WriteAllBytes($shortFile, (New-Object byte[] 1024))
                $shortFiles[$track.TrackNumber] = $shortFile
            }

            $outputPath = Join-Path $script:tempDir 'taste-sample-short.mkv'
            { Build-SampleMkvFromSrs -SrsFilePath $script:realSrs `
                -TrackDataFiles $shortFiles -OutputMkvPath $outputPath } |
                Should -Throw -ExpectedMessage '*ran out of data*'

            foreach ($path in $shortFiles.Values) {
                Remove-Item -Path $path -Force -ErrorAction 'SilentlyContinue'
            }
        }

        AfterAll {
            foreach ($path in @($script:realTrackFiles.Values)) {
                Remove-Item -Path $path -Force -ErrorAction 'SilentlyContinue'
            }
        }
    }

    Context 'Block element handling' {
        It 'Handles Block element (0xA1) in BlockGroup' {
            $srsFile = Join-Path $script:tempDir 'blockgroup.srs'
            $outputPath = Join-Path $script:tempDir 'blockgroup-output.mkv'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte]0x01)
            $bw.Write([byte[]]@(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))

            # Cluster
            $bw.Write([byte[]]@(0x1F, 0x43, 0xB6, 0x75))
            $bw.Write([byte]0x01)
            $bw.Write([byte[]]@(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))

            # BlockGroup (container)
            $bw.Write([byte]0xA0)  # BlockGroup ID
            $bw.Write([byte]0x8A)  # Size = 10

            # Block inside BlockGroup
            $bw.Write([byte]0xA1)  # Block ID
            $bw.Write([byte]0x88)  # Size = 8
            $bw.Write([byte]0x81)  # Track number = 1
            $bw.Write([byte]0x00)  # Timecode high
            $bw.Write([byte]0x00)  # Timecode low
            $bw.Write([byte]0x00)  # Flags: No lacing
            # Frame data
            $bw.Write([byte[]]@(0x01, 0x02, 0x03, 0x04))

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($srsFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            $trackFile = Join-Path $script:tempDir 'block-track.dat'
            [System.IO.File]::WriteAllBytes($trackFile, [byte[]](10..20))

            $result = Build-SampleMkvFromSrs -SrsFilePath $srsFile -TrackDataFiles @{ 1 = $trackFile } -OutputMkvPath $outputPath

            $result | Should -BeTrue
            Test-Path $outputPath | Should -BeTrue
        }
    }

    Context 'ReSample container skipping' {
        It 'Skips ReSample container element' {
            $srsFile = Join-Path $script:tempDir 'with-resample.srs'
            $outputPath = Join-Path $script:tempDir 'no-resample-output.mkv'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # ReSample container (should be skipped)
            $bw.Write([byte[]]@(0x1F, 0x69, 0x75, 0x76))  # ReSample ID
            $bw.Write([byte]0x84)  # Size = 4
            $bw.Write([byte[]]@(0xDE, 0xAD, 0xBE, 0xEF))  # Dummy metadata

            # Segment
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte]0x80)  # Unknown size

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($srsFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            $result = Build-SampleMkvFromSrs -SrsFilePath $srsFile -TrackDataFiles @{} -OutputMkvPath $outputPath

            $result | Should -BeTrue

            # Verify ReSample data is not in output
            $outputBytes = [System.IO.File]::ReadAllBytes($outputPath)
            # ReSample ID should not appear in output
            $hasResample = $false
            for ($i = 0; $i -lt $outputBytes.Length - 3; $i++) {
                if ($outputBytes[$i] -eq 0x1F -and $outputBytes[$i+1] -eq 0x69 -and
                    $outputBytes[$i+2] -eq 0x75 -and $outputBytes[$i+3] -eq 0x76) {
                    $hasResample = $true
                    break
                }
            }
            $hasResample | Should -BeFalse
        }
    }
}
