#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Export-MkvTrackData function.

.DESCRIPTION
    Tests MKV track data extraction by parsing EBML structure.
    Creates minimal MKV files for testing track extraction.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'MkvTrackTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Export-MkvTrackData' {

    Context 'File validation' {

        It 'Throws when main file does not exist' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $missingFile = Join-Path $dir 'nonexistent.mkv'
                $tracks = @{}
                $outputFiles = @{}

                { Export-MkvTrackData -MainFilePath $missingFile -Tracks $tracks -OutputFiles $outputFiles } | Should -Throw "*not found*"
            }
        }
    }

    Context 'Basic MKV parsing' {

        BeforeAll {
            # Build a minimal MKV file with EBML header, Segment, and a SimpleBlock
            $script:testMkv = Join-Path $script:tempDir 'test.mkv'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # EBML Header (ID: 0x1A45DFA3)
            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $ebmlContent = [byte[]]@(
                0x42, 0x86, 0x81, 0x01,  # EBMLVersion = 1
                0x42, 0xF7, 0x81, 0x01,  # EBMLReadVersion = 1
                0x42, 0xF2, 0x81, 0x04,  # EBMLMaxIDLength = 4
                0x42, 0xF3, 0x81, 0x08   # EBMLMaxSizeLength = 8
            )
            $bw.Write([byte](0x80 -bor $ebmlContent.Length))
            $bw.Write($ebmlContent)

            # Segment (ID: 0x18538067)
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))

            # Build segment content: Cluster with SimpleBlock
            $segmentMs = [System.IO.MemoryStream]::new()
            $segmentBw = [System.IO.BinaryWriter]::new($segmentMs)

            # Cluster (ID: 0x1F43B675)
            $segmentBw.Write([byte[]]@(0x1F, 0x43, 0xB6, 0x75))

            # Cluster content: Timecode + SimpleBlock
            $clusterMs = [System.IO.MemoryStream]::new()
            $clusterBw = [System.IO.BinaryWriter]::new($clusterMs)

            # Timecode (ID: 0xE7)
            $clusterBw.Write([byte]0xE7)
            $clusterBw.Write([byte]0x81)  # size = 1
            $clusterBw.Write([byte]0x00)  # timecode = 0

            # SimpleBlock (ID: 0xA3)
            $clusterBw.Write([byte]0xA3)
            $frameData = [byte[]]::new(100)
            for ($i = 0; $i -lt 100; $i++) { $frameData[$i] = [byte]($i % 256) }
            # SimpleBlock content: track number (VINT) + timecode (2 bytes) + flags (1 byte) + frame data
            $blockContent = [byte[]]::new(4 + $frameData.Length)
            $blockContent[0] = 0x81  # track number 1 (VINT encoded)
            $blockContent[1] = 0x00  # timecode high byte
            $blockContent[2] = 0x00  # timecode low byte
            $blockContent[3] = 0x00  # flags (no lacing)
            [Array]::Copy($frameData, 0, $blockContent, 4, $frameData.Length)

            $clusterBw.Write([byte](0x80 -bor $blockContent.Length))
            $clusterBw.Write($blockContent)

            $clusterBw.Flush()
            $clusterContent = $clusterMs.ToArray()
            $clusterBw.Dispose()
            $clusterMs.Dispose()

            $segmentBw.Write([byte](0x80 -bor $clusterContent.Length))
            $segmentBw.Write($clusterContent)

            $segmentBw.Flush()
            $segmentContent = $segmentMs.ToArray()
            $segmentBw.Dispose()
            $segmentMs.Dispose()

            # Write segment size (unknown size for simplicity)
            $bw.Write([byte[]]@(0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))
            $bw.Write($segmentContent)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:testMkv, $ms.ToArray())

            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Processes MKV file without throwing' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:testMkv } {
                $tracks = @{
                    1 = [PSCustomObject]@{
                        TrackNumber  = 1
                        DataLength   = 50
                        MatchOffset  = 0
                    }
                }
                $outputFiles = @{}

                # Should not throw - may or may not extract data depending on structure
                { Export-MkvTrackData -MainFilePath $file -Tracks $tracks -OutputFiles $outputFiles } | Should -Not -Throw
            }
        }

        It 'Creates output file entries for each track' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:testMkv } {
                $tracks = @{
                    1 = [PSCustomObject]@{
                        TrackNumber  = 1
                        DataLength   = 50
                        MatchOffset  = 0
                    }
                }
                $outputFiles = @{}

                Export-MkvTrackData -MainFilePath $file -Tracks $tracks -OutputFiles $outputFiles

                $outputFiles.ContainsKey(1) | Should -BeTrue
                $outputFiles[1] | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Empty tracks hashtable' {

        BeforeAll {
            $script:emptyTrackMkv = Join-Path $script:tempDir 'empty-track.mkv'

            # Minimal valid MKV
            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
            $bw.Write([byte]0x80)  # size = 0
            $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
            $bw.Write([byte]0x80)  # size = 0

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:emptyTrackMkv, $ms.ToArray())

            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Handles empty tracks hashtable gracefully' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:emptyTrackMkv } {
                $tracks = @{}
                $outputFiles = @{}

                # Should complete without extracting anything
                { Export-MkvTrackData -MainFilePath $file -Tracks $tracks -OutputFiles $outputFiles } | Should -Not -Throw
            }
        }
    }

    Context 'Multiple tracks' {

        It 'Handles multiple track entries' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:testMkv } {
                $tracks = @{
                    1 = [PSCustomObject]@{
                        TrackNumber  = 1
                        DataLength   = 25
                        MatchOffset  = 0
                    }
                    2 = [PSCustomObject]@{
                        TrackNumber  = 2
                        DataLength   = 25
                        MatchOffset  = 0
                    }
                }
                $outputFiles = @{}

                { Export-MkvTrackData -MainFilePath $file -Tracks $tracks -OutputFiles $outputFiles } | Should -Not -Throw

                # Both tracks should have output file entries
                $outputFiles.Count | Should -Be 2
            }
        }
    }
}
