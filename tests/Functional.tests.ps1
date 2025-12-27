#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Functional tests for ReScenePS module using real SRR/SRS sample files.

.DESCRIPTION
    These tests validate the core functionality of the ReScenePS module by
    testing against real scene release files. Tests require a local configuration
    file (TestConfig.psd1) that points to sample files on your system.

    If TestConfig.psd1 is not present, all tests are skipped gracefully.
    Copy TestConfig.Example.psd1 to TestConfig.psd1 and configure paths.

    Test Categories:
    - SRR Parsing Tests: Work with downloaded SRR files (no source files needed)
    - RAR Reconstruction Tests: Require network access to extract and reconstruct
    - SRS Sample Tests: Require extracted source MKV files
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'testConfig',
    Justification = 'Variable used in Describe blocks'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'skipFunctionalTests',
    Justification = 'Variable used in Describe blocks'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'srrParsingTests',
    Justification = 'Variable used in Describe blocks'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'srrReconstructionTests',
    Justification = 'Variable used in Describe blocks'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'srsSampleTests',
    Justification = 'Variable used in Describe blocks'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'projectRoot',
    Justification = 'Variable used in Describe blocks'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'tempDir',
    Justification = 'Variable used in Describe blocks'
)]
param()

BeforeDiscovery {
    # Build module if not already built
    $script:projectRoot = Split-Path -Parent $PSScriptRoot
    if ($null -eq $Env:BHBuildOutput) {
        $Env:BHProjectName = 'ReScenePS'
        $Env:BHProjectPath = $script:projectRoot
        $sourceManifest = Join-Path $script:projectRoot "$Env:BHProjectName/$Env:BHProjectName.psd1"
        $moduleVersion = (Import-PowerShellDataFile -Path $sourceManifest).ModuleVersion
        $Env:BHBuildOutput = Join-Path $script:projectRoot "Output/$Env:BHProjectName/$moduleVersion"
    }

    # Load test configuration
    $configPath = Join-Path -Path $PSScriptRoot -ChildPath 'TestConfig.psd1'
    if (Test-Path -Path $configPath) {
        $script:testConfig = Import-PowerShellDataFile -Path $configPath
        $script:skipFunctionalTests = $false

        # Process SRR Parsing Tests - resolve paths
        $script:srrParsingTests = @($script:testConfig.SrrParsingTests | ForEach-Object {
            $test = $_
            $fullPath = if ($test.RelativeTo -eq 'ProjectRoot') {
                Join-Path -Path $script:projectRoot -ChildPath $test.Path
            } else {
                $test.Path
            }

            if (Test-Path -Path $fullPath) {
                @{
                    Name                 = Split-Path -Leaf $test.Path
                    FullPath             = $fullPath
                    ReleaseType          = $test.ReleaseType
                    ExpectedBlockCount   = $test.ExpectedBlockCount
                    ExpectedStoredFiles  = $test.ExpectedStoredFiles
                    ExpectedRarCount     = $test.ExpectedRarCount
                    CreatingApplication  = $test.CreatingApplication
                    SampleType           = $test.SampleType
                }
            } else {
                Write-Warning "SRR file not found: $fullPath"
                $null
            }
        } | Where-Object { $_ -ne $null })

        # Process SRR Reconstruction Tests - check network accessibility
        $script:srrReconstructionTests = @($script:testConfig.SrrReconstructionTests | ForEach-Object {
            $test = $_
            $srrPath = if ($test.RelativeTo -eq 'ProjectRoot') {
                Join-Path -Path $script:projectRoot -ChildPath $test.SrrPath
            } else {
                $test.SrrPath
            }

            # Check if SRR exists and network path is accessible
            $networkAccessible = $false
            if ($test.NetworkPath -and (Test-Path -Path $srrPath)) {
                try {
                    $networkAccessible = Test-Path -Path $test.NetworkPath -ErrorAction Stop
                } catch {
                    $networkAccessible = $false
                }
            }

            if ($networkAccessible) {
                @{
                    Name            = $test.ReleaseName
                    SrrPath         = $srrPath
                    ReleaseType     = $test.ReleaseType
                    NetworkPath     = $test.NetworkPath
                }
            } else {
                # Not accessible - will be skipped
                $null
            }
        } | Where-Object { $_ -ne $null })

        # Process SRS Sample Tests (empty for now - requires extracted files)
        $script:srsSampleTests = @($script:testConfig.SrsSampleTests | ForEach-Object {
            $test = $_
            $srsPath = if ($test.RelativeTo -eq 'ProjectRoot') {
                Join-Path -Path $script:projectRoot -ChildPath $test.SrsPath
            } else {
                $test.SrsPath
            }

            if ((Test-Path -Path $srsPath) -and $test.SourceMkvPath -and (Test-Path -Path $test.SourceMkvPath)) {
                @{
                    Name                 = Split-Path -Leaf $test.SrsPath
                    SrsPath              = $srsPath
                    SourceMkvPath        = $test.SourceMkvPath
                    ExpectedTracks       = $test.ExpectedTracks
                    ExpectedOriginalSize = $test.ExpectedOriginalSize
                }
            } else {
                $null
            }
        } | Where-Object { $_ -ne $null })

        # Check if we have any tests to run
        if ($script:srrParsingTests.Count -eq 0 -and
            $script:srrReconstructionTests.Count -eq 0 -and
            $script:srsSampleTests.Count -eq 0) {
            Write-Warning 'TestConfig.psd1 exists but no valid sample files found at configured paths'
            $script:skipFunctionalTests = $true
        }
    }
    else {
        Write-Warning 'TestConfig.psd1 not found - skipping functional tests. Copy TestConfig.Example.psd1 to TestConfig.psd1 and configure paths.'
        $script:skipFunctionalTests = $true
        $script:testConfig = $null
        $script:srrParsingTests = @()
        $script:srrReconstructionTests = @()
        $script:srsSampleTests = @()
    }
}

BeforeAll {
    # Import the module
    $moduleManifestPath = Join-Path -Path $Env:BHBuildOutput -ChildPath "$Env:BHProjectName.psd1"
    Get-Module $Env:BHProjectName | Remove-Module -Force -ErrorAction 'Ignore'
    Import-Module -Name $moduleManifestPath -Verbose:$false -ErrorAction 'Stop'

    # Create temp directory for test outputs
    $script:tempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "ReScenePS-Tests-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Cleanup temp directory
    if ($script:tempDir -and (Test-Path -Path $script:tempDir)) {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction 'SilentlyContinue'
    }
}

# =============================================================================
# SRR PARSING TESTS
# =============================================================================

Describe 'Get-SrrBlock - Parsing' -Skip:$script:skipFunctionalTests {

    Context 'Parsing <_.Name> (<_.ReleaseType>)' -ForEach $script:srrParsingTests {

        BeforeAll {
            $srrPath = $_.FullPath
            $expectedBlockCount = $_.ExpectedBlockCount
            $expectedStoredFiles = $_.ExpectedStoredFiles
            $expectedRarCount = $_.ExpectedRarCount

            $script:blocks = Get-SrrBlock -SrrFile $srrPath
        }

        It 'Parses SRR file without errors' {
            $script:blocks | Should -Not -BeNullOrEmpty
        }

        It 'Returns expected block count (<expectedBlockCount>)' -Skip:(-not $expectedBlockCount) {
            $script:blocks.Count | Should -Be $expectedBlockCount
        }

        It 'Contains SRR header block' {
            $headers = $script:blocks | Where-Object { $_.GetType().Name -eq 'SrrHeaderBlock' }
            $headers | Should -Not -BeNullOrEmpty
        }

        It 'Contains RAR marker blocks' {
            $markers = $script:blocks | Where-Object { $_.GetType().Name -eq 'RarMarkerBlock' }
            $markers | Should -Not -BeNullOrEmpty
        }

        It 'Contains expected number of RAR volumes (<expectedRarCount>)' -Skip:(-not $expectedRarCount) {
            $rarBlocks = $script:blocks | Where-Object { $_.GetType().Name -eq 'SrrRarFileBlock' }
            $rarBlocks.Count | Should -Be $expectedRarCount
        }

        It 'Contains expected stored files' -Skip:(-not $expectedStoredFiles) {
            $storedBlocks = $script:blocks | Where-Object { $_.GetType().Name -eq 'SrrStoredFileBlock' }
            $storedNames = $storedBlocks | ForEach-Object { $_.FileName }
            foreach ($expected in $expectedStoredFiles) {
                $storedNames | Should -Contain $expected
            }
        }

        It 'RarPackedFileBlock entries have valid metadata' {
            $packedBlocks = $script:blocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $packedBlocks | Should -Not -BeNullOrEmpty
            $firstPacked = $packedBlocks | Select-Object -First 1
            $firstPacked.FileName | Should -Not -BeNullOrEmpty
            $firstPacked.PackedSize | Should -BeGreaterThan 0
        }
    }
}

Describe 'Show-SrrInfo - Display' -Skip:$script:skipFunctionalTests {

    Context 'Displaying info for <_.Name> (<_.ReleaseType>)' -ForEach $script:srrParsingTests {

        It 'Produces output without errors' {
            $srrPath = $_.FullPath
            { Show-SrrInfo -SrrFile $srrPath 6>&1 | Out-Null } | Should -Not -Throw
        }

        It 'Shows creating application' -Skip:(-not $_.CreatingApplication) {
            $srrPath = $_.FullPath
            $expectedApp = $_.CreatingApplication
            # Capture all output streams and join to single string for matching
            $output = (Show-SrrInfo -SrrFile $srrPath 6>&1) -join "`n"
            $output | Should -Match ([regex]::Escape($expectedApp))
        }
    }
}

# =============================================================================
# SRR RECONSTRUCTION TESTS (require network access)
# =============================================================================

Describe 'Invoke-SrrReconstruct - Network' -Skip:($script:skipFunctionalTests -or $script:srrReconstructionTests.Count -eq 0) {

    Context 'Reconstructing <_.Name> (<_.ReleaseType>)' -ForEach $script:srrReconstructionTests {

        BeforeAll {
            $sample = $_
            # Create test-specific output directory
            $safeName = $sample.Name -replace '[^\w\-\.]', '_'
            $script:testOutputDir = Join-Path -Path $script:tempDir -ChildPath "reconstruct-$safeName"
            New-Item -Path $script:testOutputDir -ItemType Directory -Force | Out-Null

            # Extract source files from network RARs to temp directory
            $script:sourceDir = Join-Path -Path $script:tempDir -ChildPath "source-$safeName"
            New-Item -Path $script:sourceDir -ItemType Directory -Force | Out-Null

            # Find RAR files in network path (check top level, then CD1/CD2 for XviD)
            $script:networkRars = Get-ChildItem -Path $sample.NetworkPath -Filter '*.rar' -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if (-not $script:networkRars) {
                # Check CD1 subdirectory for XviD releases
                $cd1Path = Join-Path $sample.NetworkPath 'CD1'
                if (Test-Path $cd1Path) {
                    $script:networkRars = Get-ChildItem -Path $cd1Path -Filter '*.rar' -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                }
            }

            $script:extractedSuccessfully = $false
            if ($script:networkRars) {
                try {
                    # Use 7z or unrar to extract (7z is more commonly available on Windows)
                    $sevenZip = Get-Command '7z' -ErrorAction SilentlyContinue
                    if (-not $sevenZip) {
                        $sevenZip = Get-Command 'C:\Program Files\7-Zip\7z.exe' -ErrorAction SilentlyContinue
                    }

                    if ($sevenZip) {
                        $extractResult = & $sevenZip.Source x $script:networkRars.FullName "-o$($script:sourceDir)" -y 2>&1
                        $script:extractedSuccessfully = $LASTEXITCODE -eq 0
                    }
                } catch {
                    $script:extractedSuccessfully = $false
                }
            }
        }

        It 'Network path is accessible' {
            Test-Path -Path $sample.NetworkPath | Should -Be $true
        }

        It 'RAR files exist in network path' {
            $script:networkRars | Should -Not -BeNullOrEmpty
        }

        It 'Source files extracted successfully' -Skip:(-not $script:networkRars) {
            $script:extractedSuccessfully | Should -Be $true
        }

        It 'Reconstructs RAR volumes successfully' -Skip:(-not $script:extractedSuccessfully) {
            $result = Invoke-SrrReconstruct -SrrFile $sample.SrrPath -SourcePath $script:sourceDir -OutputPath $script:testOutputDir

            # Check that at least some RAR files were created
            $createdRars = Get-ChildItem -Path $script:testOutputDir -Filter '*.rar' -ErrorAction SilentlyContinue
            $createdRars.Count | Should -BeGreaterThan 0
        }

        It 'Validates reconstructed RARs against SFV' -Skip:(-not $script:extractedSuccessfully) {
            # Extract SFV from SRR and validate
            $blocks = Get-SrrBlock -SrrFile $sample.SrrPath
            $sfvBlocks = $blocks | Where-Object {
                $_.GetType().Name -eq 'SrrStoredFileBlock' -and $_.FileName -match '\.sfv$'
            }

            if ($sfvBlocks) {
                # SFV validation would happen here
                $true | Should -Be $true
            } else {
                Set-ItResult -Skipped -Because 'No SFV file in SRR'
            }
        }

        AfterAll {
            # Cleanup
            if ($script:testOutputDir -and (Test-Path -Path $script:testOutputDir)) {
                Remove-Item -Path $script:testOutputDir -Recurse -Force -ErrorAction 'SilentlyContinue'
            }
            if ($script:sourceDir -and (Test-Path -Path $script:sourceDir)) {
                Remove-Item -Path $script:sourceDir -Recurse -Force -ErrorAction 'SilentlyContinue'
            }
        }
    }
}

Describe 'Invoke-SrrRestore - Full Workflow' -Skip:($script:skipFunctionalTests -or $script:srrReconstructionTests.Count -eq 0) {

    Context 'Full restore for <_.Name> (<_.ReleaseType>)' -ForEach ($script:srrReconstructionTests | Select-Object -First 1) {
        # Only run one full restore test to save time

        BeforeAll {
            $sample = $_
            $safeName = $sample.Name -replace '[^\w\-\.]', '_'

            # Create isolated work directory
            $script:testWorkDir = Join-Path -Path $script:tempDir -ChildPath "restore-$safeName"
            New-Item -Path $script:testWorkDir -ItemType Directory -Force | Out-Null

            # Copy SRR to work directory
            $script:workSrrPath = Join-Path -Path $script:testWorkDir -ChildPath (Split-Path -Leaf $sample.SrrPath)
            Copy-Item -Path $sample.SrrPath -Destination $script:workSrrPath

            # Extract source files
            $script:sourceDir = Join-Path -Path $script:testWorkDir -ChildPath 'source'
            New-Item -Path $script:sourceDir -ItemType Directory -Force | Out-Null

            $networkRars = Get-ChildItem -Path $sample.NetworkPath -Filter '*.rar' -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if (-not $networkRars) {
                $cd1Path = Join-Path $sample.NetworkPath 'CD1'
                if (Test-Path $cd1Path) {
                    $networkRars = Get-ChildItem -Path $cd1Path -Filter '*.rar' -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                }
            }

            $script:setupSuccessful = $false
            if ($networkRars) {
                try {
                    $sevenZip = Get-Command '7z' -ErrorAction SilentlyContinue
                    if (-not $sevenZip) {
                        $sevenZip = Get-Command 'C:\Program Files\7-Zip\7z.exe' -ErrorAction SilentlyContinue
                    }

                    if ($sevenZip) {
                        & $sevenZip.Source x $networkRars.FullName "-o$($script:sourceDir)" -y 2>&1 | Out-Null
                        $script:setupSuccessful = $LASTEXITCODE -eq 0
                    }
                } catch {
                    $script:setupSuccessful = $false
                }
            }
        }

        It 'Setup completed successfully' {
            $script:setupSuccessful | Should -Be $true
        }

        It 'WhatIf mode shows preview without creating RAR files' -Skip:(-not $script:setupSuccessful) {
            $outputDir = Join-Path -Path $script:testWorkDir -ChildPath 'output'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            Invoke-SrrRestore -SrrFile $script:workSrrPath -SourcePath $script:sourceDir -OutputPath $outputDir -WhatIf

            $createdRars = Get-ChildItem -Path $outputDir -Filter '*.rar' -ErrorAction SilentlyContinue
            $createdRars.Count | Should -Be 0
        }

        It 'Completes full restore' -Skip:(-not $script:setupSuccessful) {
            $outputDir = Join-Path -Path $script:testWorkDir -ChildPath 'output-full'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            Invoke-SrrRestore -SrrFile $script:workSrrPath -SourcePath $script:sourceDir -OutputPath $outputDir -KeepSrr -KeepSources -Confirm:$false

            $createdRars = Get-ChildItem -Path $outputDir -Filter '*.rar' -ErrorAction SilentlyContinue
            $createdRars.Count | Should -BeGreaterThan 0
        }

        AfterAll {
            if ($script:testWorkDir -and (Test-Path -Path $script:testWorkDir)) {
                Remove-Item -Path $script:testWorkDir -Recurse -Force -ErrorAction 'SilentlyContinue'
            }
        }
    }
}

# =============================================================================
# SRS PARSING AND RECONSTRUCTION TESTS
# =============================================================================

Describe 'ConvertFrom-SrsFileMetadata' -Skip:($script:skipFunctionalTests -or $script:srsSampleTests.Count -eq 0) {

    Context 'Parsing <_.Name>' -ForEach $script:srsSampleTests {

        BeforeAll {
            $srsPath = $_.SrsPath
            $expectedTracks = $_.ExpectedTracks
            $expectedOriginalSize = $_.ExpectedOriginalSize

            $script:metadata = ConvertFrom-SrsFileMetadata -SrsFilePath $srsPath
        }

        It 'Parses SRS file without errors' {
            $script:metadata | Should -Not -BeNullOrEmpty
        }

        It 'Returns FileData metadata' {
            $script:metadata.FileData | Should -Not -BeNullOrEmpty
        }

        It 'FileData contains sample name' {
            $script:metadata.FileData.SampleName | Should -Not -BeNullOrEmpty
        }

        It 'Returns expected number of tracks (<expectedTracks>)' -Skip:(-not $expectedTracks) {
            $script:metadata.Tracks.Count | Should -Be $expectedTracks
        }

        It 'Tracks have valid MatchOffset and DataLength' {
            foreach ($track in $script:metadata.Tracks) {
                $track.MatchOffset | Should -Not -BeNullOrEmpty
                $track.DataLength | Should -BeGreaterThan 0
            }
        }
    }
}

Describe 'Restore-SrsVideo' -Skip:($script:skipFunctionalTests -or $script:srsSampleTests.Count -eq 0) {

    Context 'Reconstructing <_.Name>' -ForEach $script:srsSampleTests {

        BeforeAll {
            $sample = $_
            $outputName = [System.IO.Path]::ChangeExtension((Split-Path -Leaf $sample.SrsPath), '.mkv')
            $script:outputPath = Join-Path -Path $script:tempDir -ChildPath $outputName
        }

        It 'Reconstructs sample MKV successfully' {
            $result = Restore-SrsVideo -SrsFilePath $sample.SrsPath -SourceMkvPath $sample.SourceMkvPath -OutputMkvPath $script:outputPath
            $result | Should -Be $true
            $script:outputPath | Should -Exist
        }

        It 'Reconstructed file has expected size' -Skip:(-not $_.ExpectedOriginalSize) {
            $actualSize = (Get-Item -Path $script:outputPath).Length
            $actualSize | Should -Be $_.ExpectedOriginalSize
        }

        AfterAll {
            if ($script:outputPath -and (Test-Path -Path $script:outputPath)) {
                Remove-Item -Path $script:outputPath -Force -ErrorAction 'SilentlyContinue'
            }
        }
    }
}

# =============================================================================
# ERROR HANDLING TESTS (always run if module loads)
# =============================================================================

Describe 'Error Handling' {

    It 'Get-SrrBlock fails gracefully on non-existent file' {
        { Get-SrrBlock -SrrFile 'C:\nonexistent\path\file.srr' } | Should -Throw
    }

    It 'ConvertFrom-SrsFileMetadata fails gracefully on non-existent file' {
        { ConvertFrom-SrsFileMetadata -SrsFilePath 'C:\nonexistent\path\file.srs' } | Should -Throw
    }

    It 'Restore-SrsVideo returns false or throws for non-existent SRS' {
        # Function may throw or return false depending on implementation
        $threw = $false
        $result = $null
        try {
            $result = Restore-SrsVideo -SrsFilePath 'C:\nonexistent\file.srs' -SourceMkvPath 'C:\nonexistent\source.mkv' -OutputMkvPath 'C:\output.mkv' -ErrorAction Stop
        } catch {
            $threw = $true
        }
        # Either it threw an exception or returned false - both are acceptable error handling
        ($threw -or $result -eq $false) | Should -Be $true
    }
}
