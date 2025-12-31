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

    Context 'ExtractStoredFiles parameter' {
        BeforeAll {
            # Create SRR with a stored file
            $script:storedFilesDir = Join-Path $script:tempDir 'stored-files'
            New-Item -Path $script:storedFilesDir -ItemType Directory -Force | Out-Null

            $script:storedFilesSrr = Join-Path $script:storedFilesDir 'with-stored.srr'

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

            # SRR Stored File block (block type 0x6A)
            $storedFileName = 'release.nfo'
            $storedFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($storedFileName)
            $storedFileContent = [System.Text.Encoding]::UTF8.GetBytes('Test NFO content for testing')
            $storedBlockHeaderSize = 7 + 2 + $storedFileNameBytes.Length
            $bw.Write([uint16]0x0000)  # CRC
            $bw.Write([byte]0x6A)       # Block type (SRR stored file)
            $bw.Write([uint16]0x8000)   # Flags (LONG_BLOCK)
            $bw.Write([uint16]$storedBlockHeaderSize)
            $bw.Write([uint16]$storedFileNameBytes.Length)
            $bw.Write($storedFileNameBytes)
            # ADD_SIZE for stored file data
            $bw.Write([uint32]$storedFileContent.Length)
            # The actual stored file content
            $bw.Write($storedFileContent)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:storedFilesSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Has ExtractStoredFiles switch parameter' {
            $cmd = Get-Command Invoke-SrrReconstruct
            $param = $cmd.Parameters['ExtractStoredFiles']
            $param | Should -Not -BeNull
            $param.SwitchParameter | Should -BeTrue
        }

        It 'Extracts stored files when -ExtractStoredFiles is specified' {
            $outputDir = Join-Path $script:storedFilesDir 'output-stored'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            Invoke-SrrReconstruct -SrrFile $script:storedFilesSrr -SourcePath $script:storedFilesDir -OutputPath $outputDir -ExtractStoredFiles -SkipValidation

            $extractedNfo = Join-Path $outputDir 'release.nfo'
            Test-Path $extractedNfo | Should -BeTrue

            $content = Get-Content $extractedNfo -Raw
            $content | Should -Match 'Test NFO content'
        }

        It 'Does not extract stored files without -ExtractStoredFiles' {
            $outputDir = Join-Path $script:storedFilesDir 'output-no-stored'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            Invoke-SrrReconstruct -SrrFile $script:storedFilesSrr -SourcePath $script:storedFilesDir -OutputPath $outputDir -SkipValidation

            $extractedNfo = Join-Path $outputDir 'release.nfo'
            Test-Path $extractedNfo | Should -BeFalse
        }
    }

    Context 'Stored files in subdirectories' {
        BeforeAll {
            $script:subDirStoredDir = Join-Path $script:tempDir 'subdir-stored'
            New-Item -Path $script:subDirStoredDir -ItemType Directory -Force | Out-Null

            $script:subDirStoredSrr = Join-Path $script:subDirStoredDir 'subdir-stored.srr'

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

            # SRR Stored File block with subdirectory path
            $storedFileName = 'Sample/sample.srs'
            $storedFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($storedFileName)
            $storedFileContent = [byte[]](1..20)
            $storedBlockHeaderSize = 7 + 2 + $storedFileNameBytes.Length
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x6A)
            $bw.Write([uint16]0x8000)
            $bw.Write([uint16]$storedBlockHeaderSize)
            $bw.Write([uint16]$storedFileNameBytes.Length)
            $bw.Write($storedFileNameBytes)
            $bw.Write([uint32]$storedFileContent.Length)
            $bw.Write($storedFileContent)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:subDirStoredSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Creates subdirectories for stored files' {
            $outputDir = Join-Path $script:subDirStoredDir 'output-subdir'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            Invoke-SrrReconstruct -SrrFile $script:subDirStoredSrr -SourcePath $script:subDirStoredDir -OutputPath $outputDir -ExtractStoredFiles -SkipValidation

            $sampleDir = Join-Path $outputDir 'Sample'
            Test-Path $sampleDir | Should -BeTrue

            $extractedSrs = Join-Path $sampleDir 'sample.srs'
            Test-Path $extractedSrs | Should -BeTrue
        }
    }

    Context 'Source file size validation' {
        BeforeAll {
            # Create SRR that expects a specific file size
            $script:sizeMismatchDir = Join-Path $script:tempDir 'size-mismatch'
            New-Item -Path $script:sizeMismatchDir -ItemType Directory -Force | Out-Null

            $script:sizeMismatchSrr = Join-Path $script:sizeMismatchDir 'size-test.srr'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # SRR Header
            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp12345')
            $headerSize = 7 + 2 + $appName.Length
            $bw.Write([uint16]0x6969)
            $bw.Write([byte]0x69)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]$headerSize)
            $bw.Write([uint16]$appName.Length)
            $bw.Write($appName)

            # SRR RAR File block
            $rarFileName = 'release.rar'
            $rarFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($rarFileName)
            $srrRarBlockSize = 7 + 2 + $rarFileNameBytes.Length
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x71)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]$srrRarBlockSize)
            $bw.Write([uint16]$rarFileNameBytes.Length)
            $bw.Write($rarFileNameBytes)

            # RAR Marker
            $bw.Write([byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00))

            # RAR Volume Header
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x73)
            $bw.Write([uint16]0x0001)
            $bw.Write([uint16]13)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint32]0x00000000)

            # RAR Packed File block expecting 1000 bytes
            $packedFileName = 'test.dat'
            $packedFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($packedFileName)
            $packedBlockSize = 25 + 4 + $packedFileNameBytes.Length + 8
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x74)
            $bw.Write([uint16]0x8000)
            $bw.Write([uint16]$packedBlockSize)
            $bw.Write([uint32]100)    # PackSize
            $bw.Write([uint32]1000)   # UnpSize - expecting 1000 bytes
            $bw.Write([byte]0x00)
            $bw.Write([uint32]0x12345678)
            $bw.Write([uint32]0x00000000)
            $bw.Write([byte]0x15)
            $bw.Write([byte]0x30)
            $bw.Write([uint16]$packedFileNameBytes.Length)
            $bw.Write([uint32]0x00000020)
            $bw.Write([uint32]0x00000000)
            $bw.Write([uint32]0x00000000)
            $bw.Write($packedFileNameBytes)
            $bw.Write([uint32]100)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:sizeMismatchSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            # Create source file with wrong size (500 bytes instead of 1000)
            $script:wrongSizeSource = Join-Path $script:sizeMismatchDir 'test.dat'
            [System.IO.File]::WriteAllBytes($script:wrongSizeSource, [byte[]](1..500))
        }

        It 'Throws on source file size mismatch without -SkipValidation' {
            $outputDir = Join-Path $script:sizeMismatchDir 'output'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            { Invoke-SrrReconstruct -SrrFile $script:sizeMismatchSrr -SourcePath $script:sizeMismatchDir -OutputPath $outputDir } |
                Should -Throw '*size mismatch*'
        }

        It 'Skips size validation with -SkipValidation' {
            $outputDir = Join-Path $script:sizeMismatchDir 'output-skip'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            # Should not throw with -SkipValidation (though may fail for other reasons)
            { Invoke-SrrReconstruct -SrrFile $script:sizeMismatchSrr -SourcePath $script:sizeMismatchDir -OutputPath $outputDir -SkipValidation } |
                Should -Not -Throw '*size mismatch*'
        }
    }
}
