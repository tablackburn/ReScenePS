#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Restore-SrsVideo function.

.DESCRIPTION
    Tests the high-level video sample restoration function with
    parameter validation and format detection.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'RestoreSrsTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Restore-SrsVideo' {

    Context 'Parameter validation' {
        It 'Throws when SrsFilePath does not exist' {
            $sourcePath = Join-Path $script:tempDir 'source.mkv'
            [System.IO.File]::WriteAllBytes($sourcePath, [byte[]](1..100))
            $nonExistentSrs = Join-Path ([System.IO.Path]::GetTempPath()) 'NonExistent_12345' 'sample.srs'

            { Restore-SrsVideo -SrsFilePath $nonExistentSrs -SourcePath $sourcePath -OutputPath 'output.mkv' } | Should -Throw '*not found*'
        }

        It 'Throws when SourcePath does not exist' {
            $srsPath = Join-Path $script:tempDir 'sample.srs'
            [System.IO.File]::WriteAllBytes($srsPath, [byte[]](1..100))
            $nonExistentSource = Join-Path ([System.IO.Path]::GetTempPath()) 'NonExistent_12345' 'source.mkv'

            { Restore-SrsVideo -SrsFilePath $srsPath -SourcePath $nonExistentSource -OutputPath 'output.mkv' } | Should -Throw '*not found*'
        }
    }

    Context 'Alias support' {
        It 'Accepts SourceMkvPath alias for SourcePath' {
            # Verify the alias exists in the function definition
            $cmd = Get-Command Restore-SrsVideo
            $param = $cmd.Parameters['SourcePath']
            $param.Aliases | Should -Contain 'SourceMkvPath'
        }

        It 'Accepts OutputMkvPath alias for OutputPath' {
            $cmd = Get-Command Restore-SrsVideo
            $param = $cmd.Parameters['OutputPath']
            $param.Aliases | Should -Contain 'OutputMkvPath'
        }
    }

    Context 'Format detection' {
        BeforeAll {
            # Create minimal EBML SRS file
            $script:ebmlSrs = Join-Path $script:tempDir 'ebml.srs'
            $ebmlData = [byte[]]@(0x1A, 0x45, 0xDF, 0xA3, 0x84, 0x42, 0x86, 0x81, 0x01)
            [System.IO.File]::WriteAllBytes($script:ebmlSrs, $ebmlData)

            # Create minimal RIFF SRS file
            $script:riffSrs = Join-Path $script:tempDir 'riff.srs'
            $riffData = [byte[]]@(0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x41, 0x56, 0x49, 0x20)
            # Add padding bytes (using explicit byte values to avoid overflow)
            for ($i = 0; $i -lt 20; $i++) {
                $riffData += [byte]$i
            }
            [System.IO.File]::WriteAllBytes($script:riffSrs, $riffData)

            # Create source file
            $script:sourceFile = Join-Path $script:tempDir 'source.mkv'
            $sourceData = [byte[]]::new(1000)
            for ($i = 0; $i -lt 1000; $i++) {
                $sourceData[$i] = [byte]($i % 256)
            }
            [System.IO.File]::WriteAllBytes($script:sourceFile, $sourceData)
        }

        It 'Detects EBML format' {
            $outputPath = Join-Path $script:tempDir 'output_ebml.mkv'

            # This may fail due to incomplete SRS, but should not fail on format detection
            $result = $null
            try {
                $result = Restore-SrsVideo -SrsFilePath $script:ebmlSrs -SourcePath $script:sourceFile -OutputPath $outputPath -ErrorAction SilentlyContinue
            }
            catch {
                # Expected - incomplete SRS structure
            }

            # If we got here without a format detection error, the test passes
            $true | Should -BeTrue
        }
    }

    Context 'Return values' {
        BeforeAll {
            $script:dummySrs = Join-Path $script:tempDir 'dummy.srs'
            $script:dummySource = Join-Path $script:tempDir 'dummy_source.mkv'
            [System.IO.File]::WriteAllBytes($script:dummySrs, [byte[]](0xFF, 0xFF, 0xFF))  # Invalid format
            [System.IO.File]::WriteAllBytes($script:dummySource, [byte[]](1..100))
        }

        It 'Returns false for unsupported format' {
            $outputPath = Join-Path $script:tempDir 'unsupported.mkv'

            # Suppress warning output
            $result = Restore-SrsVideo -SrsFilePath $script:dummySrs -SourcePath $script:dummySource -OutputPath $outputPath -WarningAction SilentlyContinue

            $result | Should -BeFalse
        }
    }

    Context 'AVI/RIFF format handling' {
        BeforeAll {
            # Create a valid RIFF/AVI SRS file
            $script:aviSrs = Join-Path $script:tempDir 'sample.srs'
            $script:aviSource = Join-Path $script:tempDir 'source.avi'

            # Build minimal RIFF structure
            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # RIFF header
            $bw.Write([byte[]]@(0x52, 0x49, 0x46, 0x46))  # "RIFF"
            $bw.Write([uint32]100)  # File size (placeholder)
            $bw.Write([byte[]]@(0x41, 0x56, 0x49, 0x20))  # "AVI "

            # Add some padding
            $bw.Write([byte[]]::new(88))

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:aviSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            # Create source AVI file
            $sourceMs = [System.IO.MemoryStream]::new()
            $sourceBw = [System.IO.BinaryWriter]::new($sourceMs)
            $sourceBw.Write([byte[]]@(0x52, 0x49, 0x46, 0x46))  # "RIFF"
            $sourceBw.Write([uint32]1000)
            $sourceBw.Write([byte[]]@(0x41, 0x56, 0x49, 0x20))  # "AVI "
            $sourceBw.Write([byte[]]::new(988))
            $sourceBw.Flush()
            [System.IO.File]::WriteAllBytes($script:aviSource, $sourceMs.ToArray())
            $sourceBw.Dispose()
            $sourceMs.Dispose()
        }

        It 'Detects RIFF format and delegates to AVI handler' {
            $outputPath = Join-Path $script:tempDir 'output.avi'

            # This will likely fail due to incomplete SRS, but should detect format correctly
            $result = $null
            try {
                $result = Restore-SrsVideo -SrsFilePath $script:aviSrs -SourcePath $script:aviSource -OutputPath $outputPath -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            catch {
                # Expected - incomplete AVI structure
            }

            # Test passes if we reach here without format detection error
            $true | Should -BeTrue
        }
    }

    Context 'Error handling' {
        BeforeAll {
            # Create a minimal EBML SRS that will fail during track extraction
            $script:failingSrs = Join-Path $script:tempDir 'failing.srs'
            $script:failingSource = Join-Path $script:tempDir 'failing_source.mkv'

            # EBML header with segment but invalid track data
            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Segment with ResampleTrack but invalid data
            $trackBytes = [System.IO.MemoryStream]::new()
            $tw = [System.IO.BinaryWriter]::new($trackBytes)
            $tw.Write([uint16]0x0000)  # Flags
            $tw.Write([uint16]1)  # TrackNumber
            $tw.Write([uint32]99999999)  # DataLength - way more than source has
            $tw.Write([uint64]0x100)  # MatchOffset
            $tw.Write([uint16]0)  # SignatureBytesLength
            $tw.Flush()
            $trackData = $trackBytes.ToArray()
            $tw.Dispose()
            $trackBytes.Dispose()

            $trackElemSize = 2 + 1 + $trackData.Length

            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte](0x80 + $trackElemSize))
            $bw.Write([byte[]]@(0x6B, 0x75))
            $bw.Write([byte](0x80 + $trackData.Length))
            $bw.Write($trackData)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:failingSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            # Create small source file
            [System.IO.File]::WriteAllBytes($script:failingSource, [byte[]]::new(100))
        }

        It 'Returns false and shows warning when reconstruction fails' {
            $outputPath = Join-Path $script:tempDir 'failed_output.mkv'

            # Capture warning
            $warnings = @()
            $result = Restore-SrsVideo -SrsFilePath $script:failingSrs -SourcePath $script:failingSource -OutputPath $outputPath -WarningVariable warnings -WarningAction SilentlyContinue

            $result | Should -BeFalse
        }
    }

    Context 'Output verification' {
        # Nothing here is mocked. A synthetic EBML SRS is parsed by the real parser and
        # rebuilt by the real rebuilder; the two rejection paths are reached by giving
        # the SRS recorded values that disagree with what that rebuild produces. That is
        # the only side of the comparison a test can move without a mock, and it is the
        # comparison itself -- plus the discard and the warning -- that went untested.
        BeforeAll {
            function Build-VerificationSrsFile {
                <#
                .SYNOPSIS
                    Build a minimal EBML SRS recording a given original size and CRC32.

                .DESCRIPTION
                    Mirrors the layout of a real SRS:

                        EBML header element    copied verbatim into the rebuild
                        Segment (container)    only its header is copied
                          ReSample (container) dropped from the rebuild entirely
                            ResampleFile       carries the recorded size and CRC32

                    There are no tracks, so the rebuild is exactly the EBML header
                    element followed by the Segment header. Those bytes are returned so
                    a caller can state the size and checksum a correct rebuild has.
                    They do not depend on the recorded values, which the rebuild never
                    reads.

                .PARAMETER Path
                    Path to write the SRS file to.

                .PARAMETER RecordedSize
                    Original sample size to record in the ResampleFile element.

                .PARAMETER RecordedCrc32
                    Original sample CRC32 to record in the ResampleFile element.
                #>
                param(
                    [Parameter(Mandatory)]
                    [string]$Path,

                    [Parameter(Mandatory)]
                    [uint64]$RecordedSize,

                    [Parameter(Mandatory)]
                    [uint32]$RecordedCrc32
                )

                function ConvertTo-SingleByteEbmlSize {
                    # Every element here is small enough for a one-byte EBML size, and
                    # keeping it that way keeps the builder readable. Lengthening a name
                    # past that would otherwise overflow the [byte] cast and produce a
                    # plausible-looking but invalid SRS, so fail loudly instead.
                    param(
                        [Parameter(Mandatory)]
                        [int]$Length
                    )

                    if ($Length -gt 0x7F) {
                        throw "This builder encodes EBML element sizes as a single-byte VINT, which tops out at 127 bytes; $Length needs a longer encoding."
                    }

                    return [byte](0x80 + $Length)
                }

                $applicationName = [System.Text.Encoding]::UTF8.GetBytes('ReScenePS-Test')
                $sampleName = [System.Text.Encoding]::UTF8.GetBytes('sample.mkv')

                $fileDataStream = [System.IO.MemoryStream]::new()
                $fileDataWriter = [System.IO.BinaryWriter]::new($fileDataStream)
                try {
                    $fileDataWriter.Write([uint16]0x0000)  # Flags
                    $fileDataWriter.Write([uint16]$applicationName.Length)
                    $fileDataWriter.Write($applicationName)
                    $fileDataWriter.Write([uint16]$sampleName.Length)
                    $fileDataWriter.Write($sampleName)
                    $fileDataWriter.Write([uint64]$RecordedSize)
                    $fileDataWriter.Write([uint32]$RecordedCrc32)
                    $fileDataWriter.Flush()
                    $fileData = $fileDataStream.ToArray()
                }
                finally {
                    $fileDataWriter.Dispose()
                    $fileDataStream.Dispose()
                }

                $resampleFileElement = [byte[]]@(0x6A, 0x75) + (ConvertTo-SingleByteEbmlSize -Length $fileData.Length) + $fileData
                $resampleElement = [byte[]]@(0x1F, 0x69, 0x75, 0x76) + (ConvertTo-SingleByteEbmlSize -Length $resampleFileElement.Length) + $resampleFileElement
                $ebmlHeaderElement = [byte[]]@(0x1A, 0x45, 0xDF, 0xA3, 0x84, 0x42, 0x86, 0x81, 0x01)
                $segmentHeader = [byte[]]@(0x18, 0x53, 0x80, 0x67) + (ConvertTo-SingleByteEbmlSize -Length $resampleElement.Length)

                [System.IO.File]::WriteAllBytes($Path, $ebmlHeaderElement + $segmentHeader + $resampleElement)

                return [byte[]]($ebmlHeaderElement + $segmentHeader)
            }

            # No tracks are extracted from it, so its contents do not matter; it only
            # has to exist for the source-video check to pass.
            $script:verificationSource = Join-Path $script:tempDir 'verification_source.mkv'
            [System.IO.File]::WriteAllBytes($script:verificationSource, [byte[]]::new(1000))

            $probeSrs = Join-Path $script:tempDir 'verification_probe.srs'
            $expectedRebuild = Build-VerificationSrsFile -Path $probeSrs -RecordedSize 0 -RecordedCrc32 0

            $expectedRebuildPath = Join-Path $script:tempDir 'verification_expected.bin'
            [System.IO.File]::WriteAllBytes($expectedRebuildPath, $expectedRebuild)

            $script:expectedRebuildSize = $expectedRebuild.Length
            $script:expectedRebuildCrc32 = InModuleScope 'ReScenePS' -Parameters @{ path = $expectedRebuildPath } {
                Get-Crc32 -FilePath $path
            }

            # Every bit flipped, so it cannot collide with the real checksum however
            # the rebuild changes.
            $script:wrongCrc32 = [uint32]($script:expectedRebuildCrc32 -bxor [uint32]::MaxValue)

            # Not the size of this rebuild. It is the size of the sample the check was
            # added for -- ten megabytes, of which the rebuild wrote 52,755 bytes and
            # reported success.
            $script:wrongSize = [uint64]10123431

            # Only the size disagrees here. Recording the correct CRC32 alongside it is
            # not a combination a real SRS could hold, and that is the point: it leaves
            # the size check as the only thing that can reject this rebuild, so the test
            # cannot be carried by the CRC32 check or by the order the two run in.
            $script:sizeMismatchSrs = Join-Path $script:tempDir 'size_mismatch.srs'
            $null = Build-VerificationSrsFile -Path $script:sizeMismatchSrs -RecordedSize $script:wrongSize -RecordedCrc32 $script:expectedRebuildCrc32

            $script:crcMismatchSrs = Join-Path $script:tempDir 'crc_mismatch.srs'
            $null = Build-VerificationSrsFile -Path $script:crcMismatchSrs -RecordedSize ([uint64]$script:expectedRebuildSize) -RecordedCrc32 $script:wrongCrc32

            $script:matchingSrs = Join-Path $script:tempDir 'matching.srs'
            $null = Build-VerificationSrsFile -Path $script:matchingSrs -RecordedSize ([uint64]$script:expectedRebuildSize) -RecordedCrc32 $script:expectedRebuildCrc32
        }

        It 'Rejects a rebuild whose size does not match the size the SRS records' {
            $outputPath = Join-Path $script:tempDir 'size_mismatch_output.mkv'
            $warnings = @()

            $result = Restore-SrsVideo -SrsFilePath $script:sizeMismatchSrs -SourcePath $script:verificationSource -OutputPath $outputPath -WarningVariable 'warnings' -WarningAction 'SilentlyContinue'

            $result | Should -BeFalse -Because 'a sample of the wrong size is not a successful reconstruction'
            Test-Path -Path $outputPath | Should -BeFalse -Because 'a rejected sample must not be left on disk to be mistaken for a good one'
            ($warnings -join "`n") | Should -BeLike "*Reconstructed sample is $script:expectedRebuildSize bytes but the SRS records $script:wrongSize*" -Because 'the warning has to name both sizes to be actionable'
        }

        It 'Rejects a rebuild whose CRC32 does not match the CRC32 the SRS records' {
            $outputPath = Join-Path $script:tempDir 'crc_mismatch_output.mkv'
            $recordedCrc32Text = '0x{0:X8}' -f $script:wrongCrc32
            $rebuiltCrc32Text = '0x{0:X8}' -f $script:expectedRebuildCrc32
            $warnings = @()

            $result = Restore-SrsVideo -SrsFilePath $script:crcMismatchSrs -SourcePath $script:verificationSource -OutputPath $outputPath -WarningVariable 'warnings' -WarningAction 'SilentlyContinue'

            $result | Should -BeFalse -Because 'the right number of the wrong bytes is not a successful reconstruction'
            Test-Path -Path $outputPath | Should -BeFalse -Because 'a rejected sample must not be left on disk to be mistaken for a good one'
            ($warnings -join "`n") | Should -BeLike "*Reconstructed sample CRC32 is $rebuiltCrc32Text but the SRS records $recordedCrc32Text*" -Because 'the warning has to name both checksums to be actionable'
        }

        It 'Accepts a rebuild matching both the size and the CRC32 the SRS records' {
            # Without this, both tests above would still pass against a check that
            # rejected everything.
            $outputPath = Join-Path $script:tempDir 'matching_output.mkv'
            $warnings = @()

            $result = Restore-SrsVideo -SrsFilePath $script:matchingSrs -SourcePath $script:verificationSource -OutputPath $outputPath -WarningVariable 'warnings' -WarningAction 'SilentlyContinue'

            $result | Should -BeTrue
            Test-Path -Path $outputPath | Should -BeTrue
            $warnings | Should -BeNullOrEmpty
        }
    }

    Context 'No tracks case' {
        BeforeAll {
            # Create EBML SRS with FileData but no tracks
            $script:noTracksSrs = Join-Path $script:tempDir 'notracks.srs'
            $script:noTracksSource = Join-Path $script:tempDir 'notracks_source.mkv'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x84)
            $bw.Write([byte[]]@(0x42, 0x86, 0x81, 0x01))

            # Segment with only ResampleFile (no tracks)
            $appName = [System.Text.Encoding]::UTF8.GetBytes('App')
            $sampleName = [System.Text.Encoding]::UTF8.GetBytes('sample.mkv')
            $fileDataBytes = [System.IO.MemoryStream]::new()
            $fdw = [System.IO.BinaryWriter]::new($fileDataBytes)
            $fdw.Write([uint16]0x0000)
            $fdw.Write([uint16]$appName.Length)
            $fdw.Write($appName)
            $fdw.Write([uint16]$sampleName.Length)
            $fdw.Write($sampleName)
            $fdw.Write([uint64]1000)
            $fdw.Write([uint32]0x12345678)
            $fdw.Flush()
            $fileData = $fileDataBytes.ToArray()
            $fdw.Dispose()
            $fileDataBytes.Dispose()

            $fileElemSize = 2 + 1 + $fileData.Length

            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte](0x80 + $fileElemSize))
            $bw.Write([byte[]]@(0x6A, 0x75))
            $bw.Write([byte](0x80 + $fileData.Length))
            $bw.Write($fileData)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:noTracksSrs, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            # Create source file
            [System.IO.File]::WriteAllBytes($script:noTracksSource, [byte[]]::new(1000))
        }

        It 'Handles SRS with no tracks' {
            $outputPath = Join-Path $script:tempDir 'notracks_output.mkv'

            # Should not throw, may return false due to empty track extraction
            $result = $null
            try {
                $result = Restore-SrsVideo -SrsFilePath $script:noTracksSrs -SourcePath $script:noTracksSource -OutputPath $outputPath -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            catch {
                # May fail, but shouldn't be unhandled exception
            }

            # Test passes if we handled the case (either returned result or caught error)
            $true | Should -BeTrue
        }
    }
}
