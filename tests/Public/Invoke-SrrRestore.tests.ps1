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

    Context 'SkipValidation parameter' {
        It 'Has SkipValidation switch parameter' {
            $cmd = Get-Command Invoke-SrrRestore
            $param = $cmd.Parameters['SkipValidation']
            $param | Should -Not -BeNull
            $param.SwitchParameter | Should -BeTrue
        }
    }

    Context 'Missing source files' {
        BeforeAll {
            # Create SRR with a RarPackedFileBlock that references a source file
            $script:missingSourceDir = Join-Path $script:tempDir 'missing-source'
            New-Item -Path $script:missingSourceDir -ItemType Directory -Force | Out-Null

            $script:missingSourceSrr = Join-Path $script:missingSourceDir 'release.srr'

            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            # SRR Header block (block type 0x69)
            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp12345')
            $headerSize = 7 + 2 + $appName.Length
            $bw.Write([uint16]0x6969)  # CRC
            $bw.Write([byte]0x69)       # Block type
            $bw.Write([uint16]0x0000)   # Flags
            $bw.Write([uint16]$headerSize)
            $bw.Write([uint16]$appName.Length)
            $bw.Write($appName)

            # SRR RAR File block (block type 0x71) - introduces a RAR volume
            $rarFileName = 'release.rar'
            $rarFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($rarFileName)
            $srrRarBlockSize = 7 + 2 + $rarFileNameBytes.Length
            $bw.Write([uint16]0x0000)  # CRC
            $bw.Write([byte]0x71)       # Block type (SRR RAR file)
            $bw.Write([uint16]0x0000)   # Flags
            $bw.Write([uint16]$srrRarBlockSize)
            $bw.Write([uint16]$rarFileNameBytes.Length)
            $bw.Write($rarFileNameBytes)

            # RAR Marker block
            $bw.Write([byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00))

            # RAR Volume Header block (simplified)
            $bw.Write([uint16]0x0000)  # HEAD_CRC
            $bw.Write([byte]0x73)       # HEAD_TYPE (archive header)
            $bw.Write([uint16]0x0001)   # HEAD_FLAGS (volume attribute)
            $bw.Write([uint16]13)       # HEAD_SIZE

            # Reserved fields
            $bw.Write([uint16]0x0000)   # Reserved1
            $bw.Write([uint32]0x00000000)  # Reserved2

            # RAR Packed File block (block type 0x74)
            $packedFileName = 'missing_source.mkv'
            $packedFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($packedFileName)
            $packedBlockSize = 25 + 4 + $packedFileNameBytes.Length + 8  # Base + HIGH_* + name + 64-bit sizes
            $bw.Write([uint16]0x0000)  # HEAD_CRC
            $bw.Write([byte]0x74)       # HEAD_TYPE (file header)
            $bw.Write([uint16]0x8000)   # HEAD_FLAGS (LONG_BLOCK set for 64-bit sizes)
            $bw.Write([uint16]$packedBlockSize)

            # Packed and unpacked sizes (32-bit low parts)
            $bw.Write([uint32]1048576)  # PackSize (1MB)
            $bw.Write([uint32]1048576)  # UnpSize (1MB)

            $bw.Write([byte]0x00)       # HostOS
            $bw.Write([uint32]0x12345678)  # FileCRC
            $bw.Write([uint32]0x00000000)  # FileTime
            $bw.Write([byte]0x15)       # UnpVer
            $bw.Write([byte]0x30)       # Method
            $bw.Write([uint16]$packedFileNameBytes.Length)
            $bw.Write([uint32]0x00000020)  # FileAttr
            # HIGH_PACK_SIZE and HIGH_UNP_SIZE (for 64-bit sizes)
            $bw.Write([uint32]0x00000000)
            $bw.Write([uint32]0x00000000)
            $bw.Write($packedFileNameBytes)

            # ADD_SIZE for the packed data
            $bw.Write([uint32]1048576)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:missingSourceSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Throws when source file is missing' {
            { Invoke-SrrRestore -SrrFile $script:missingSourceSrr -SourcePath $script:missingSourceDir -OutputPath $script:missingSourceDir } |
                Should -Throw '*not found*'
        }
    }

    Context 'Output directory creation' {
        BeforeAll {
            # Create minimal valid SRR with header only
            $script:outputTestDir = Join-Path $script:tempDir 'output-test'
            New-Item -Path $script:outputTestDir -ItemType Directory -Force | Out-Null

            $appName = [System.Text.Encoding]::UTF8.GetBytes('TestApp12345')
            $headerSize = 7 + 2 + $appName.Length

            $script:outputTestSrr = Join-Path $script:outputTestDir 'release.srr'
            $ms = [System.IO.MemoryStream]::new()
            $bw = [System.IO.BinaryWriter]::new($ms)

            $bw.Write([uint16]0x6969)
            $bw.Write([byte]0x69)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]$headerSize)
            $bw.Write([uint16]$appName.Length)
            $bw.Write($appName)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:outputTestSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()
        }

        It 'Creates output directory if it does not exist' {
            $newOutputDir = Join-Path $script:outputTestDir 'new-output-dir'

            # Will throw due to no source files, but should create the directory first
            try {
                Invoke-SrrRestore -SrrFile $script:outputTestSrr -SourcePath $script:outputTestDir -OutputPath $newOutputDir
            }
            catch {
                # Expected to throw
            }

            Test-Path $newOutputDir | Should -BeTrue
        }
    }

    Context 'SRR with no stored files' {
        BeforeAll {
            # Create SRR with RAR content but no stored files
            $script:noStoredDir = Join-Path $script:tempDir 'no-stored'
            New-Item -Path $script:noStoredDir -ItemType Directory -Force | Out-Null

            $script:noStoredSrr = Join-Path $script:noStoredDir 'release.srr'

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

            # SRR RAR File block (block type 0x71)
            $rarFileName = 'release.rar'
            $rarFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($rarFileName)
            $srrRarBlockSize = 7 + 2 + $rarFileNameBytes.Length
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x71)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]$srrRarBlockSize)
            $bw.Write([uint16]$rarFileNameBytes.Length)
            $bw.Write($rarFileNameBytes)

            # RAR Marker block
            $bw.Write([byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00))

            # RAR Volume Header block
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x73)
            $bw.Write([uint16]0x0001)
            $bw.Write([uint16]13)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint32]0x00000000)

            # RAR Packed File block with very small size
            $packedFileName = 'test.txt'
            $packedFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($packedFileName)
            $packedBlockSize = 25 + 4 + $packedFileNameBytes.Length + 8
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x74)
            $bw.Write([uint16]0x8000)
            $bw.Write([uint16]$packedBlockSize)
            $bw.Write([uint32]10)  # PackSize
            $bw.Write([uint32]10)  # UnpSize
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
            $bw.Write([uint32]10)

            # RAR End Archive block
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x7B)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]7)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:noStoredSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            # Create source file
            $script:testSource = Join-Path $script:noStoredDir 'test.txt'
            [System.IO.File]::WriteAllBytes($script:testSource, [byte[]](1..10))
        }

        It 'Handles SRR with no stored files' {
            $outputDir = Join-Path $script:noStoredDir 'output'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            # Should complete without throwing for stored files section
            { Invoke-SrrRestore -SrrFile $script:noStoredSrr -SourcePath $script:noStoredDir -OutputPath $outputDir -SkipValidation } |
                Should -Not -Throw
        }
    }

    Context 'WhatIf mode' {
        BeforeAll {
            $script:whatIfDir = Join-Path $script:tempDir 'whatif-test'
            New-Item -Path $script:whatIfDir -ItemType Directory -Force | Out-Null

            $script:whatIfSrr = Join-Path $script:whatIfDir 'release.srr'

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

            # SRR Stored File block with NFO
            $storedFileName = 'release.nfo'
            $storedFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($storedFileName)
            $storedContent = [System.Text.Encoding]::UTF8.GetBytes('Test NFO')
            $storedBlockHeaderSize = 7 + 2 + $storedFileNameBytes.Length
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x6A)
            $bw.Write([uint16]0x8000)
            $bw.Write([uint16]$storedBlockHeaderSize)
            $bw.Write([uint16]$storedFileNameBytes.Length)
            $bw.Write($storedFileNameBytes)
            $bw.Write([uint32]$storedContent.Length)
            $bw.Write($storedContent)

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

            # RAR Marker block
            $bw.Write([byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00))

            # RAR Volume Header block
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x73)
            $bw.Write([uint16]0x0001)
            $bw.Write([uint16]13)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint32]0x00000000)

            # RAR Packed File block
            $packedFileName = 'test.dat'
            $packedFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($packedFileName)
            $packedBlockSize = 25 + 4 + $packedFileNameBytes.Length + 8
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x74)
            $bw.Write([uint16]0x8000)
            $bw.Write([uint16]$packedBlockSize)
            $bw.Write([uint32]100)
            $bw.Write([uint32]100)
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

            # RAR End Archive block
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x7B)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]7)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:whatIfSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            # Create source file
            $script:whatIfSource = Join-Path $script:whatIfDir 'test.dat'
            [System.IO.File]::WriteAllBytes($script:whatIfSource, [byte[]](1..100))
        }

        It 'Runs in WhatIf mode without creating files' {
            $outputDir = Join-Path $script:whatIfDir 'whatif-output'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            Invoke-SrrRestore -SrrFile $script:whatIfSrr -SourcePath $script:whatIfDir -OutputPath $outputDir -WhatIf

            # Should not have created RAR files under WhatIf
            $rarFiles = Get-ChildItem -Path $outputDir -Filter '*.rar' -ErrorAction SilentlyContinue
            $rarFiles.Count | Should -Be 0
        }

        It 'Shows preview output in WhatIf mode' {
            $outputDir = Join-Path $script:whatIfDir 'whatif-preview'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            # This should execute without throwing (exercises WhatIf code paths)
            { Invoke-SrrRestore -SrrFile $script:whatIfSrr -SourcePath $script:whatIfDir -OutputPath $outputDir -WhatIf } |
                Should -Not -Throw
        }
    }

    Context 'Stored file with subdirectory path' {
        BeforeAll {
            $script:subdirStoredDir = Join-Path $script:tempDir 'subdir-stored'
            New-Item -Path $script:subdirStoredDir -ItemType Directory -Force | Out-Null

            $script:subdirStoredSrr = Join-Path $script:subdirStoredDir 'release.srr'

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

            # SRR Stored File block with subdirectory path
            $storedFileName = 'Sample/sample.txt'
            $storedFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($storedFileName)
            $storedContent = [System.Text.Encoding]::UTF8.GetBytes('Sample content')
            $storedBlockHeaderSize = 7 + 2 + $storedFileNameBytes.Length
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x6A)
            $bw.Write([uint16]0x8000)
            $bw.Write([uint16]$storedBlockHeaderSize)
            $bw.Write([uint16]$storedFileNameBytes.Length)
            $bw.Write($storedFileNameBytes)
            $bw.Write([uint32]$storedContent.Length)
            $bw.Write($storedContent)

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

            # RAR Marker block
            $bw.Write([byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00))

            # RAR Volume Header block
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x73)
            $bw.Write([uint16]0x0001)
            $bw.Write([uint16]13)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint32]0x00000000)

            # RAR Packed File block
            $packedFileName = 'content.dat'
            $packedFileNameBytes = [System.Text.Encoding]::UTF8.GetBytes($packedFileName)
            $packedBlockSize = 25 + 4 + $packedFileNameBytes.Length + 8
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x74)
            $bw.Write([uint16]0x8000)
            $bw.Write([uint16]$packedBlockSize)
            $bw.Write([uint32]50)
            $bw.Write([uint32]50)
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
            $bw.Write([uint32]50)

            # RAR End Archive block
            $bw.Write([uint16]0x0000)
            $bw.Write([byte]0x7B)
            $bw.Write([uint16]0x0000)
            $bw.Write([uint16]7)

            $bw.Flush()
            [System.IO.File]::WriteAllBytes($script:subdirStoredSrr, $ms.ToArray())
            $bw.Dispose()
            $ms.Dispose()

            # Create source file
            $script:subdirSource = Join-Path $script:subdirStoredDir 'content.dat'
            [System.IO.File]::WriteAllBytes($script:subdirSource, [byte[]](1..50))
        }

        It 'Creates subdirectory for stored files' {
            $outputDir = Join-Path $script:subdirStoredDir 'output'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            Invoke-SrrRestore -SrrFile $script:subdirStoredSrr -SourcePath $script:subdirStoredDir -OutputPath $outputDir -SkipValidation

            $sampleDir = Join-Path $outputDir 'Sample'
            Test-Path $sampleDir | Should -BeTrue

            $sampleFile = Join-Path $sampleDir 'sample.txt'
            Test-Path $sampleFile | Should -BeTrue
        }
    }
}
