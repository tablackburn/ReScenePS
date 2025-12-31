#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for Export-SampleTrackData function.

.DESCRIPTION
    Tests data extraction from files at specified offsets.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'ExportTrackTest'
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Export-SampleTrackData' {

    BeforeAll {
        # Create test source file with known content
        $script:sourceFile = Join-Path $script:tempDir 'source.bin'
        $testData = [byte[]](0..255) * 100  # 25,600 bytes of repeating pattern
        [System.IO.File]::WriteAllBytes($script:sourceFile, $testData)
    }

    Context 'Parameter validation' {
        It 'Throws when MainFilePath does not exist' {
            $outputPath = Join-Path $script:tempDir 'output1.bin'
            $nonExistentFile = Join-Path ([System.IO.Path]::GetTempPath()) 'NonExistent_12345' 'File.mkv'
            { Export-SampleTrackData -MainFilePath $nonExistentFile -MatchOffset 0 -DataLength 100 -OutputPath $outputPath } | Should -Throw '*not found*'
        }

        It 'Accepts valid parameters' {
            $outputPath = Join-Path $script:tempDir 'output2.bin'
            { Export-SampleTrackData -MainFilePath $script:sourceFile -MatchOffset 0 -DataLength 100 -OutputPath $outputPath } | Should -Not -Throw
        }
    }

    Context 'Data extraction' {
        It 'Extracts correct number of bytes' {
            $outputPath = Join-Path $script:tempDir 'extract1.bin'
            Export-SampleTrackData -MainFilePath $script:sourceFile -MatchOffset 0 -DataLength 100 -OutputPath $outputPath

            $outputSize = (Get-Item $outputPath).Length
            $outputSize | Should -Be 100
        }

        It 'Extracts from correct offset' {
            $outputPath = Join-Path $script:tempDir 'extract2.bin'
            Export-SampleTrackData -MainFilePath $script:sourceFile -MatchOffset 50 -DataLength 10 -OutputPath $outputPath

            $extracted = [System.IO.File]::ReadAllBytes($outputPath)
            # Source has pattern 0..255 repeating, so offset 50 should start with byte 50
            $extracted[0] | Should -Be 50
            $extracted[1] | Should -Be 51
        }

        It 'Handles large extraction' {
            $outputPath = Join-Path $script:tempDir 'extract_large.bin'
            Export-SampleTrackData -MainFilePath $script:sourceFile -MatchOffset 0 -DataLength 20000 -OutputPath $outputPath

            $outputSize = (Get-Item $outputPath).Length
            $outputSize | Should -Be 20000
        }

        It 'Returns true on success' {
            $outputPath = Join-Path $script:tempDir 'extract_return.bin'
            $result = Export-SampleTrackData -MainFilePath $script:sourceFile -MatchOffset 0 -DataLength 50 -OutputPath $outputPath

            $result | Should -BeTrue
        }
    }

    Context 'Edge cases' {
        It 'Handles zero-length extraction' {
            $outputPath = Join-Path $script:tempDir 'zero.bin'
            Export-SampleTrackData -MainFilePath $script:sourceFile -MatchOffset 0 -DataLength 0 -OutputPath $outputPath

            $outputSize = (Get-Item $outputPath).Length
            $outputSize | Should -Be 0
        }

        It 'Creates output file in nested directory' {
            $nestedDir = Join-Path $script:tempDir 'nested\path'
            New-Item -Path $nestedDir -ItemType Directory -Force | Out-Null
            $outputPath = Join-Path $nestedDir 'output.bin'

            Export-SampleTrackData -MainFilePath $script:sourceFile -MatchOffset 0 -DataLength 10 -OutputPath $outputPath

            Test-Path $outputPath | Should -BeTrue
        }
    }
}
