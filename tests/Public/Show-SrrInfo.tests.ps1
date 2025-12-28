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
        $bw.Write([uint16]0x0000)  # HEAD_FLAGS
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
            { Show-SrrInfo -SrrFile 'C:\NonExistent\File.srr' } | Should -Throw
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
    }
}
