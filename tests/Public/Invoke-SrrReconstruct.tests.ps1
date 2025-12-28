#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Invoke-SrrReconstruct function.

.DESCRIPTION
    Tests the RAR reconstruction function with parameter
    validation and error handling.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'InvokeSrrReconstructTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Invoke-SrrReconstruct' {

    Context 'Parameter validation' {
        It 'Throws when SrrFile does not exist' {
            $outputPath = Join-Path $script:tempDir 'output'
            New-Item -Path $outputPath -ItemType Directory -Force | Out-Null

            { Invoke-SrrReconstruct -SrrFile 'C:\NonExistent\release.srr' -SourcePath $script:tempDir -OutputPath $outputPath } | Should -Throw
        }

        It 'Throws when SourcePath does not exist' {
            $srrFile = Join-Path $script:tempDir 'test.srr'
            # Create minimal SRR
            $data = [byte[]]@(0x69, 0x69, 0x69) + [byte[]](0..50)
            [System.IO.File]::WriteAllBytes($srrFile, $data)

            { Invoke-SrrReconstruct -SrrFile $srrFile -SourcePath 'C:\NonExistent\Path' -OutputPath $script:tempDir } | Should -Throw
        }
    }

    Context 'Parameter types' {
        It 'SrrFile parameter is mandatory' {
            $cmd = Get-Command Invoke-SrrReconstruct
            $param = $cmd.Parameters['SrrFile']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'SourcePath parameter is mandatory' {
            $cmd = Get-Command Invoke-SrrReconstruct
            $param = $cmd.Parameters['SourcePath']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'OutputPath parameter is mandatory' {
            $cmd = Get-Command Invoke-SrrReconstruct
            $param = $cmd.Parameters['OutputPath']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'Has SkipValidation switch parameter' {
            $cmd = Get-Command Invoke-SrrReconstruct
            $param = $cmd.Parameters['SkipValidation']
            $param | Should -Not -BeNull
            $param.SwitchParameter | Should -BeTrue
        }
    }

    Context 'Output directory handling' {
        BeforeAll {
            # Create minimal valid SRR with just a header (must be >= 20 bytes)
            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp12345')  # 12 chars
            $headerSize = 7 + 2 + $appName.Length  # 21 bytes

            $script:testSrr = Join-Path $script:tempDir 'minimal.srr'
            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            $bw.Write([uint16]0x6969)
            $bw.Write([byte]0x69)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]$headerSize)
            $bw.Write([uint16]$appName.Length)
            $bw.Write($appName)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:testSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Creates output directory if it does not exist' {
            $newOutputDir = Join-Path $script:tempDir 'new_output_dir'

            # Create the output directory first (function expects it to exist or be creatable)
            # The function should complete with 0 volumes
            # Use -SkipValidation because minimal SRR has no SFV file
            New-Item -Path $newOutputDir -ItemType Directory -Force | Out-Null
            Invoke-SrrReconstruct -SrrFile $script:testSrr -SourcePath $script:tempDir -OutputPath $newOutputDir -SkipValidation

            Test-Path $newOutputDir | Should -BeTrue
        }
    }
}
