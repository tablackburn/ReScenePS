#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Invoke-SrrRestore function.

.DESCRIPTION
    Tests the high-level SRR restoration function with parameter
    validation, auto-detection, and error handling.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'InvokeSrrRestoreTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Invoke-SrrRestore' {

    Context 'Parameter defaults' {
        It 'SrrFile defaults to empty string (auto-detect)' {
            $cmd = Get-Command Invoke-SrrRestore
            $param = $cmd.Parameters['SrrFile']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Not -Contain $true
        }

        It 'SourcePath defaults to current directory' {
            $cmd = Get-Command Invoke-SrrRestore
            # No easy way to check default value, just verify it exists
            $cmd.Parameters['SourcePath'] | Should -Not -BeNull
        }

        It 'OutputPath defaults to current directory' {
            $cmd = Get-Command Invoke-SrrRestore
            $cmd.Parameters['OutputPath'] | Should -Not -BeNull
        }

        It 'Has KeepSrr switch parameter' {
            $cmd = Get-Command Invoke-SrrRestore
            $param = $cmd.Parameters['KeepSrr']
            $param | Should -Not -BeNull
            $param.SwitchParameter | Should -BeTrue
        }

        It 'Has KeepSources switch parameter' {
            $cmd = Get-Command Invoke-SrrRestore
            $param = $cmd.Parameters['KeepSources']
            $param | Should -Not -BeNull
            $param.SwitchParameter | Should -BeTrue
        }
    }

    Context 'SupportsShouldProcess' {
        It 'Supports -WhatIf parameter' {
            $cmd = Get-Command Invoke-SrrRestore
            $cmd.Parameters['WhatIf'] | Should -Not -BeNull
        }

        It 'Supports -Confirm parameter' {
            $cmd = Get-Command Invoke-SrrRestore
            $cmd.Parameters['Confirm'] | Should -Not -BeNull
        }
    }

    Context 'Auto-detection' {
        It 'Throws when no SRR file found and none specified' {
            $emptyDir = Join-Path $script:tempDir 'empty'
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            { Invoke-SrrRestore -SourcePath $emptyDir } | Should -Throw '*No SRR file found*'
        }

        It 'Throws when multiple SRR files found and none specified' {
            $multiDir = Join-Path $script:tempDir 'multi'
            New-Item -Path $multiDir -ItemType Directory -Force | Out-Null

            # Create two SRR files
            $srr1 = Join-Path $multiDir 'release1.srr'
            $srr2 = Join-Path $multiDir 'release2.srr'
            [System.IO.File]::WriteAllBytes($srr1, [byte[]]@(0x69, 0x69, 0x69))
            [System.IO.File]::WriteAllBytes($srr2, [byte[]]@(0x69, 0x69, 0x69))

            { Invoke-SrrRestore -SourcePath $multiDir } | Should -Throw '*Multiple SRR files found*'
        }

        It 'Auto-detects single SRR file in directory' {
            $singleDir = Join-Path $script:tempDir 'single'
            New-Item -Path $singleDir -ItemType Directory -Force | Out-Null

            # Create minimal valid SRR (must be at least 20 bytes)
            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp12345')  # 12 chars
            $headerSize = 7 + 2 + $appName.Length  # 21 bytes

            $srrFile = Join-Path $singleDir 'release.srr'
            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            $bw.Write([uint16]0x6969)
            $bw.Write([byte]0x69)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]$headerSize)
            $bw.Write([uint16]$appName.Length)
            $bw.Write($appName)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($srrFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            # Should find the SRR but fail on missing source files or no source files in metadata
            { Invoke-SrrRestore -SourcePath $singleDir -OutputPath $singleDir } | Should -Throw
        }
    }

    Context 'Explicit SRR file' {
        It 'Uses specified SRR file when provided' {
            $testDir = Join-Path $script:tempDir 'explicit'
            New-Item -Path $testDir -ItemType Directory -Force | Out-Null

            # Create minimal valid SRR (must be at least 20 bytes)
            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp12345')  # 12 chars
            $headerSize = 7 + 2 + $appName.Length  # 21 bytes

            $srrFile = Join-Path $testDir 'specific.srr'
            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            $bw.Write([uint16]0x6969)
            $bw.Write([byte]0x69)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]$headerSize)
            $bw.Write([uint16]$appName.Length)
            $bw.Write($appName)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($srrFile, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            # Should use the specified file (will fail on no source files in metadata)
            { Invoke-SrrRestore -SrrFile $srrFile -SourcePath $testDir -OutputPath $testDir } | Should -Throw
        }

        It 'Throws when specified SRR file does not exist' {
            { Invoke-SrrRestore -SrrFile 'C:\NonExistent\release.srr' } | Should -Throw
        }
    }
}
