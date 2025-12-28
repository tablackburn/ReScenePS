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
}
