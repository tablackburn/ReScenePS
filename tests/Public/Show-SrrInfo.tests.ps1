#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Show-SrrInfo function.

.DESCRIPTION
    Tests the SRR info display function with synthetic test data.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'ShowSrrInfoTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Show-SrrInfo' {

    BeforeAll {
        # Create minimal valid SRR file
        $appName = [System.Text.Encoding]::UTF8.GetBytes('ReSceneTest v1.0')
        $headerSize = 7 + 2 + $appName.Length

        $script:testSrr = Join-Path $script:tempDir 'test.srr'
        $ms = [System.IO.MemoryStream]::new()
        $bw = [System.IO.BinaryWriter]::new($ms)

        # SRR Header block
        $bw.Write([uint16]0x6969)  # CRC placeholder
        $bw.Write([byte]0x69)      # HEAD_TYPE = SRR Header
        $bw.Write([uint16]0x0001)  # HEAD_FLAGS - 0x0001 indicates AppName is present
        $bw.Write([uint16]$headerSize)  # HEAD_SIZE
        $bw.Write([uint16]$appName.Length)  # AppName length
        $bw.Write($appName)        # AppName

        $bw.Flush()
        [System.IO.File]::WriteAllBytes($script:testSrr, $ms.ToArray())
        $bw.Dispose()
        $ms.Dispose()
    }

    Context 'Parameter validation' {
        It 'Throws when SrrFile parameter is missing' {
            { Show-SrrInfo } | Should -Throw
        }

        It 'Throws when file does not exist' {
            $nonExistentFile = Join-Path ([System.IO.Path]::GetTempPath()) 'NonExistent_12345' 'File.srr'
            { Show-SrrInfo -SrrFile $nonExistentFile } | Should -Throw
        }
    }

    Context 'Output generation' {
        It 'Produces output without errors' {
            { Show-SrrInfo -SrrFile $script:testSrr 6>&1 | Out-Null } | Should -Not -Throw
        }

        It 'Outputs block count' {
            $output = Show-SrrInfo -SrrFile $script:testSrr 6>&1 | Out-String
            $output | Should -Match 'Total blocks'
        }

        It 'Outputs block type summary' {
            $output = Show-SrrInfo -SrrFile $script:testSrr 6>&1 | Out-String
            $output | Should -Match 'Block type summary'
        }
    }

    Context 'Information displayed' {
        It 'Shows SRR header block info' {
            $output = Show-SrrInfo -SrrFile $script:testSrr 6>&1 | Out-String
            $output | Should -Match '0x69'  # SRR header type
        }

        It 'Shows application name' {
            $output = Show-SrrInfo -SrrFile $script:testSrr 6>&1 | Out-String
            $output | Should -Match 'Creating Application'
            $output | Should -Match 'ReSceneTest'
        }
    }

    Context 'Unknown block types' {
        BeforeAll {
            # Create SRR with an unknown block type
            $script:unknownTypeSrr = Join-Path $script:tempDir 'unknown-type.srr'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # SRR Header block
            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp12345')
            $headerSize = 7 + 2 + $appName.Length
            $bw.Write([uint16]0x6969)
            $bw.Write([byte]0x69)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]$headerSize)
            $bw.Write([uint16]$appName.Length)
            $bw.Write($appName)

            # Unknown block type (0xFF is not a standard SRR/RAR type)
            $bw.Write([uint16]0x0000)  # CRC
            $bw.Write([byte]0xFF)       # Unknown type
            $bw.Write([uint16]0x0000)   # Flags
            $bw.Write([uint16]7)        # Size (minimum)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:unknownTypeSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Shows Unknown for unrecognized block types' {
            $output = Show-SrrInfo -SrrFile $script:unknownTypeSrr 6>&1 | Out-String
            $output | Should -Match 'Unknown'
        }
    }

    Context 'SRR with stored files' {
        BeforeAll {
            # Create SRR with stored files
            $script:storedFileSrr = Join-Path $script:tempDir 'stored-files.srr'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # SRR Header block
            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp12345')
            $headerSize = 7 + 2 + $appName.Length
            $bw.Write([uint16]0x6969)
            $bw.Write([byte]0x69)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]$headerSize)
            $bw.Write([uint16]$appName.Length)
            $bw.Write($appName)

            # Stored file block (0x6A)
            # Format: [CRC(2)][Type(1)][Flags(2)][HeadSize(2)][AddSize(4)][NameLen(2)][FileName(n)][FileData(AddSize)]
            $storedFileName = 'release.nfo'
            $storedFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($storedFileName)
            $storedFileContent = [System.Text.Encoding]::UTF8.GetBytes('NFO content')
            # HeadSize = 7 (common) + 4 (AddSize) + 2 (NameLen) + len(FileName)
            $storedBlockHeaderSize = 7 + 4 + 2 + $storedFileNameBytes.Length
            $bw.Write([uint16]0x0000)  # CRC
            $bw.Write([byte]0x6A)       # Type = SRR Stored File
            $bw.Write([uint16]0x8000)   # Flags = LONG_BLOCK (has AddSize)
            $bw.Write([uint16]$storedBlockHeaderSize)  # HeadSize
            $bw.Write([uint32]$storedFileContent.Length)  # AddSize (file size) - comes first in RawData
            $bw.Write([uint16]$storedFileNameBytes.Length)  # NameLen
            $bw.Write($storedFileNameBytes)  # FileName
            $bw.Write($storedFileContent)  # Actual file data (skipped by parser)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:storedFileSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Shows stored files section' {
            $output = Show-SrrInfo -SrrFile $script:storedFileSrr 6>&1 | Out-String
            $output | Should -Match 'Stored files'
            $output | Should -Match 'release\.nfo'
        }
    }

    Context 'SRR with RAR files' {
        BeforeAll {
            # Create SRR with RAR file entry
            $script:rarFileSrr = Join-Path $script:tempDir 'rar-files.srr'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # SRR Header block
            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp12345')
            $headerSize = 7 + 2 + $appName.Length
            $bw.Write([uint16]0x6969)
            $bw.Write([byte]0x69)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]$headerSize)
            $bw.Write([uint16]$appName.Length)
            $bw.Write($appName)

            # RAR file block
            $rarFileName = 'release.rar'
            $rarFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($rarFileName)
            $rarBlockSize = 7 + 2 + $rarFileNameBytes.Length
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x71)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]$rarBlockSize)
            $bw.Write([uint16]$rarFileNameBytes.Length)
            $bw.Write($rarFileNameBytes)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:rarFileSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Shows RAR files section' {
            $output = Show-SrrInfo -SrrFile $script:rarFileSrr 6>&1 | Out-String
            $output | Should -Match 'RAR files'
            $output | Should -Match 'release\.rar'
        }
    }
}
