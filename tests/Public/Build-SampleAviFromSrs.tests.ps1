#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Build-SampleAviFromSrs function.

.DESCRIPTION
    Tests the AVI sample reconstruction function with parameter
    validation and error handling.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'BuildAviTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Build-SampleAviFromSrs' {

    Context 'Parameter validation' {
        It 'Throws when SourcePath does not exist' {
            $srsData = [byte[]](1..100)
            $outputPath = Join-Path $script:tempDir 'output.avi'
            $nonExistentSource = Join-Path ([System.IO.Path]::GetTempPath()) 'NonExistent_12345' 'source.avi'

            { Build-SampleAviFromSrs -SrsData $srsData -SourcePath $nonExistentSource -OutputPath $outputPath } | Should -Throw '*not found*'
        }

        It 'Throws for invalid SRS data' {
            $sourceFile = Join-Path $script:tempDir 'source.avi'
            $outputPath = Join-Path $script:tempDir 'output.avi'

            # Create minimal source AVI
            $aviData = [byte[]]@(0x52, 0x49, 0x46, 0x46) + [byte[]](0..100)  # "RIFF" + padding
            [System.IO.File]::WriteAllBytes($sourceFile, $aviData)

            # Invalid SRS data (too small to parse)
            $srsData = [byte[]](1..10)

            { Build-SampleAviFromSrs -SrsData $srsData -SourcePath $sourceFile -OutputPath $outputPath } | Should -Throw
        }
    }

    Context 'Input requirements' {
        It 'Requires SrsData as byte array' {
            $cmd = Get-Command Build-SampleAviFromSrs
            $param = $cmd.Parameters['SrsData']
            $param.ParameterType | Should -Be ([byte[]])
        }

        It 'SrsData parameter is mandatory' {
            $cmd = Get-Command Build-SampleAviFromSrs
            $param = $cmd.Parameters['SrsData']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'SourcePath parameter is mandatory' {
            $cmd = Get-Command Build-SampleAviFromSrs
            $param = $cmd.Parameters['SourcePath']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'OutputPath parameter is mandatory' {
            $cmd = Get-Command Build-SampleAviFromSrs
            $param = $cmd.Parameters['OutputPath']
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }
    }
}
