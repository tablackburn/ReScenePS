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

        # Process SRR Parsing Tests - resolve paths (static SRR files in tests/samples/)
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
                    ExpectedSampleTracks = $test.ExpectedSampleTracks
                }
            } else {
                Write-Warning "SRR file not found: $fullPath"
                $null
            }
        } | Where-Object { $_ -ne $null })

        # Derive the SRS sample tests from the SRR parsing tests, as
        # TestConfig.Example.psd1 has always said they would be ("dynamically
        # populated ... where SampleType = 'MKV'"). Nothing ever populated
        # $script:srsSampleTests, so both SRS Describe blocks below have skipped on
        # an empty collection since they were written and have never once run.
        #
        # There is no path to an .srs on disk to point at: the sample is stored
        # *inside* the .srr, so each entry records the archive and the name of the
        # member to pull out of it, and the Context BeforeAll extracts it.
        #
        # MKV only, because ConvertFrom-SrsFileMetadata is documented as EBML-only.
        # See the SampleType note in TestConfig.psd1 for the other two containers.
        $script:srsSampleTests = @($script:srrParsingTests | ForEach-Object {
            $test = $_
            if ($test.SampleType -ne 'MKV') {
                return
            }

            $storedSrs = @($test.ExpectedStoredFiles) -match '\.srs$' | Select-Object -First 1
            if (-not $storedSrs) {
                return
            }

            @{
                Name           = Split-Path -Leaf $storedSrs
                SrrPath        = $test.FullPath
                StoredSrs      = $storedSrs
                ExpectedTracks = $test.ExpectedSampleTracks
            }
        })

        # Plex-based tests are discovered dynamically at runtime (in BeforeAll)
        # Set placeholder for test discovery - actual releases come from playlist
        $script:plexReleases = @()

        # Check if we have parsing tests to run (Plex tests are discovered at runtime)
        if ($script:srrParsingTests.Count -eq 0) {
            Write-Warning 'TestConfig.psd1 exists but no valid sample files found at configured paths'
            $script:skipFunctionalTests = $true
        }
    }
    else {
        Write-Warning 'TestConfig.psd1 not found - skipping functional tests. Copy TestConfig.Example.psd1 to TestConfig.psd1 and configure paths.'
        $script:skipFunctionalTests = $true
        $script:testConfig = $null
        $script:srrParsingTests = @()
        $script:plexReleases = @()
        $script:srsSampleTests = @()
    }

    # Check Plex and SrrDB availability for -Skip: conditions on Describe blocks
    # Import test helpers to access Test-PlexAvailable
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
    $script:plexEnabled = Test-PlexAvailable
    $script:srrdbAvailable = $null -ne (Get-Module -Name SrrDBAutomationToolkit -ListAvailable)

    # Discover Plex releases during discovery so ForEach data is available.
    #
    # Everything here must be non-fatal. Test-PlexAvailable only reports that a Plex
    # server is configured, not that this machine can authenticate to it, so on CI it
    # returns true and the first real call fails with 401 Unauthorized. That is a
    # terminating error -- -ErrorAction SilentlyContinue does not suppress it -- and a
    # throw in BeforeDiscovery kills the whole container, taking every non-Plex test in
    # this file with it. Under Pester 5 that failure was invisible (a dead container
    # generates no tests, so nothing was reported as missing); the container gate in
    # build.psake.ps1 now makes it a red build instead.
    #
    # Fall back to the same state as "no Plex configured" so the -Skip: conditions on the
    # Plex-backed Describe blocks do their job.
    if ($script:plexEnabled) {
        try {
            Initialize-PlexForCI | Out-Null
            $playlistName = 'ReScenePS-TestData'
            if ($script:testConfig.PlexDataSource.PlaylistName) {
                $playlistName = $script:testConfig.PlexDataSource.PlaylistName
            }
            $script:plexReleases = @(Get-PlexTestRelease -PlaylistName $playlistName -ErrorAction 'SilentlyContinue')

            # A reachable Plex with an empty playlist is still no test data. The
            # Plex-backed Describes skip on -not $script:plexEnabled, so leaving this
            # $true lets them run with an empty -ForEach: zero contexts, zero tests, and
            # nothing reported. Turning it off makes the skip explicit and visible.
            if ($script:plexReleases.Count -eq 0) {
                Write-Warning "Plex playlist '$playlistName' returned no releases; skipping Plex-backed functional tests."
                $script:plexEnabled = $false
            }
        }
        catch {
            Write-Warning "Plex test data unavailable ($($_.Exception.Message)); skipping Plex-backed functional tests."
            $script:plexEnabled = $false
            $script:plexReleases = @()
        }
    }
}

BeforeAll {
    # Import test helpers and module
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    # Create temp directory for test outputs
    $script:tempDir = New-TestTempDirectory -Prefix 'ReScenePS-Functional'

    # Re-load test config for test execution scope (BeforeDiscovery is separate)
    $testConfigPath = Join-Path $PSScriptRoot 'TestConfig.psd1'
    if (Test-Path -Path $testConfigPath) {
        $script:testConfig = Import-PowerShellDataFile -Path $testConfigPath
    }

    # Initialize Plex and discover test releases from playlist
    $script:plexEnabled = $false
    $script:plexReleases = @()
    $script:plexSourceDir = $null
    $script:srrdbAvailable = $false

    # Check for SrrDBAutomationToolkit
    if (Get-Module -Name SrrDBAutomationToolkit -ListAvailable) {
        Import-Module SrrDBAutomationToolkit -Force -ErrorAction 'SilentlyContinue'
        $script:srrdbAvailable = $null -ne (Get-Module -Name SrrDBAutomationToolkit)
    }

    # Get playlist name from config or use default
    $playlistName = 'ReScenePS-TestData'
    if ($script:testConfig.PlexDataSource.PlaylistName) {
        $playlistName = $script:testConfig.PlexDataSource.PlaylistName
    }

    # Auto-enable Plex if PAT env vars are set or module is configured
    if (Test-PlexAvailable) {
        Initialize-PlexForCI | Out-Null

        Write-Host "Discovering test releases from Plex playlist '$playlistName'..."

        try {
            # Discover releases from playlist (extracts release names from file paths)
            $script:plexReleases = @(Get-PlexTestRelease -PlaylistName $playlistName -ErrorAction 'Stop')

            if ($script:plexReleases.Count -gt 0) {
                Write-Host "Found $($script:plexReleases.Count) release(s) in playlist:"
                foreach ($release in $script:plexReleases) {
                    Write-Host "  - $($release.ReleaseName) ($($release.VideoCodec) $($release.VideoResolution))"
                }

                # Download SRRs from srrdb for each release
                if ($script:srrdbAvailable) {
                    $script:srrDir = New-TestTempDirectory -Prefix 'ReScenePS-SRRs'
                    foreach ($release in $script:plexReleases) {
                        try {
                            Write-Host "Downloading SRR for $($release.ReleaseName)..."
                            Get-SatSrr -ReleaseName $release.ReleaseName -OutPath $script:srrDir -ErrorAction 'Stop'
                            $srrFile = Get-ChildItem -Path $script:srrDir -Filter "$($release.ReleaseName).srr" -ErrorAction 'SilentlyContinue'
                            if ($srrFile) {
                                $release | Add-Member -NotePropertyName 'SrrPath' -NotePropertyValue $srrFile.FullName -Force
                            }
                        }
                        catch {
                            Write-Warning "Failed to download SRR for $($release.ReleaseName): $_"
                        }
                    }
                }

                # Download source files from Plex
                $script:plexSourceDir = New-TestTempDirectory -Prefix 'ReScenePS-PlexSource'
                Write-Host "Downloading source files from Plex..."
                Sync-PatMedia -PlaylistName $playlistName -Destination $script:plexSourceDir -SkipSubtitles -Force -Confirm:$false

                $script:plexEnabled = $true
                Write-Host "Plex setup complete."
            }
            else {
                Write-Warning "No releases found in playlist '$playlistName'"
            }
        }
        catch {
            Write-Warning "Failed to setup Plex: $_"
        }
    }
}

AfterAll {
    # Clean up Plex source files (contains copyrighted material)
    if ($script:plexSourceDir) {
        Remove-TestTempDirectory -Path $script:plexSourceDir
    }
    # Clean up downloaded SRR files
    if ($script:srrDir) {
        Remove-TestTempDirectory -Path $script:srrDir
    }
    Remove-TestTempDirectory -Path $script:tempDir
}

# =============================================================================
# SRR PARSING TESTS
# =============================================================================

Describe 'Get-SrrBlock - Parsing' -Skip:$script:skipFunctionalTests {

    Context 'Parsing <_.Name> (<_.ReleaseType>)' -ForEach $script:srrParsingTests -AllowNullOrEmptyForEach {

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

    Context 'Displaying info for <_.Name> (<_.ReleaseType>)' -ForEach $script:srrParsingTests -AllowNullOrEmptyForEach {

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
# SRR RECONSTRUCTION TESTS (dynamically discovered from Plex playlist)
# =============================================================================

Describe 'Invoke-SrrReconstruct - Plex Sources' -Skip:(-not $script:plexEnabled) {

    BeforeAll {
        # Filter to releases that have SRR files downloaded
        $script:testableReleases = @($script:plexReleases | Where-Object { $_.SrrPath })
    }

    Context 'Reconstructing <_.ReleaseName> (<_.VideoCodec> <_.VideoResolution>)' -ForEach $script:plexReleases -AllowNullOrEmptyForEach {

        BeforeAll {
            $release = $_
            # Create test-specific output directory
            $safeName = $release.ReleaseName -replace '[^\w\-\.]', '_'
            $script:testOutputDir = Join-Path -Path $script:tempDir -ChildPath "reconstruct-$safeName"
            New-Item -Path $script:testOutputDir -ItemType Directory -Force | Out-Null

            # Create source directory for extracted/downloaded files
            $script:sourceDir = Join-Path -Path $script:tempDir -ChildPath "source-$safeName"
            New-Item -Path $script:sourceDir -ItemType Directory -Force | Out-Null

            $script:extractedSuccessfully = $false

            # Look up SRR file from downloaded folder (ForEach data is from discovery, SrrPath added in BeforeAll)
            $script:srrPath = $null
            if ($script:srrDir) {
                $srrFile = Get-ChildItem -Path $script:srrDir -Filter "$($release.ReleaseName).srr" -ErrorAction 'SilentlyContinue'
                if ($srrFile) {
                    $script:srrPath = $srrFile.FullName
                }
            }

            # Find source file from downloaded Plex content by matching the original filename
            if ($script:plexSourceDir -and $script:srrPath) {
                # Search for the file by extension type
                $extension = [System.IO.Path]::GetExtension($release.FileName)
                $sourceFiles = Get-ChildItem -Path $script:plexSourceDir -Recurse -File |
                    Where-Object { $_.Extension -eq $extension }

                # For single file, use it directly; otherwise try to match by size
                $sourceFile = if ($sourceFiles.Count -eq 1) {
                    $sourceFiles[0].FullName
                } else {
                    $sourceFiles | Where-Object { $_.Length -eq $release.FileSize } |
                        Select-Object -First 1 -ExpandProperty FullName
                }

                if ($sourceFile -and (Test-Path $sourceFile)) {
                    # Get the expected source filename from the SRR
                    $srrBlocks = Get-SrrBlock -SrrFile $script:srrPath
                    $packedFiles = $srrBlocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
                    $mainFile = $packedFiles |
                        Where-Object { $_.FileName -match '\.(mkv|avi|mp4|m2ts)$' } |
                        Sort-Object -Property UnpackedSize -Descending |
                        Select-Object -First 1

                    if ($mainFile) {
                        $destPath = Join-Path $script:sourceDir $mainFile.FileName
                        Copy-Item -Path $sourceFile -Destination $destPath -Force
                    } else {
                        Copy-Item -Path $sourceFile -Destination $script:sourceDir -Force
                    }
                    $script:extractedSuccessfully = $true
                }
            }
        }

        It 'Source file obtained from Plex' {
            if (-not $script:extractedSuccessfully) {
                Set-ItResult -Skipped -Because "Source file not found in Plex download"
                return
            }
            $script:extractedSuccessfully | Should -Be $true
        }

        It 'Reconstructs RAR volumes' {
            if (-not $script:extractedSuccessfully) {
                Set-ItResult -Skipped -Because 'Source file not available'
                return
            }
            Invoke-SrrReconstruct -SrrFile $script:srrPath -SourcePath $script:sourceDir -OutputPath $script:testOutputDir

            $createdRars = Get-ChildItem -Path $script:testOutputDir -Filter '*.rar' -ErrorAction 'SilentlyContinue'
            $createdRars.Count | Should -BeGreaterThan 0
        }

        AfterAll {
            if ($script:testOutputDir -and (Test-Path -Path $script:testOutputDir)) {
                Remove-Item -Path $script:testOutputDir -Recurse -Force -ErrorAction 'SilentlyContinue'
            }
            if ($script:sourceDir -and (Test-Path -Path $script:sourceDir)) {
                Remove-Item -Path $script:sourceDir -Recurse -Force -ErrorAction 'SilentlyContinue'
            }
        }
    }
}

Describe 'Invoke-SrrRestore - Full Workflow' -Skip:(-not $script:plexEnabled) {

    Context 'Full restore for <_.ReleaseName>' -ForEach @($script:plexReleases | Select-Object -First 1) -AllowNullOrEmptyForEach {

        BeforeAll {
            $release = $_
            if (-not $release) {
                $script:setupSuccessful = $false
                return
            }

            $safeName = $release.ReleaseName -replace '[^\w\-\.]', '_'

            # Create isolated work directory
            $script:testWorkDir = Join-Path -Path $script:tempDir -ChildPath "restore-$safeName"
            New-Item -Path $script:testWorkDir -ItemType Directory -Force | Out-Null

            # Look up SRR file from downloaded folder
            $script:srrPath = $null
            if ($script:srrDir) {
                $srrFile = Get-ChildItem -Path $script:srrDir -Filter "$($release.ReleaseName).srr" -ErrorAction 'SilentlyContinue'
                if ($srrFile) {
                    $script:srrPath = $srrFile.FullName
                }
            }

            $script:setupSuccessful = $false
            if (-not $script:srrPath) {
                return
            }

            # Copy SRR to work directory
            $script:workSrrPath = Join-Path -Path $script:testWorkDir -ChildPath (Split-Path -Leaf $script:srrPath)
            Copy-Item -Path $script:srrPath -Destination $script:workSrrPath

            # Find source files from downloaded Plex content
            $script:sourceDir = Join-Path -Path $script:testWorkDir -ChildPath 'source'
            New-Item -Path $script:sourceDir -ItemType Directory -Force | Out-Null

            if ($script:plexSourceDir) {
                $extension = [System.IO.Path]::GetExtension($release.FileName)
                $sourceFiles = Get-ChildItem -Path $script:plexSourceDir -Recurse -File |
                    Where-Object { $_.Extension -eq $extension }

                $sourceFile = if ($sourceFiles.Count -eq 1) {
                    $sourceFiles[0].FullName
                } else {
                    $sourceFiles | Where-Object { $_.Length -eq $release.FileSize } |
                        Select-Object -First 1 -ExpandProperty FullName
                }

                if ($sourceFile -and (Test-Path $sourceFile)) {
                    $srrBlocks = Get-SrrBlock -SrrFile $script:srrPath
                    $packedFiles = $srrBlocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
                    $mainFile = $packedFiles |
                        Where-Object { $_.FileName -match '\.(mkv|avi|mp4|m2ts)$' } |
                        Sort-Object -Property UnpackedSize -Descending |
                        Select-Object -First 1

                    if ($mainFile) {
                        $destPath = Join-Path $script:sourceDir $mainFile.FileName
                        Copy-Item -Path $sourceFile -Destination $destPath -Force
                    } else {
                        Copy-Item -Path $sourceFile -Destination $script:sourceDir -Force
                    }
                    $script:setupSuccessful = $true
                }
            }
        }

        It 'Setup completed successfully' {
            if (-not $script:setupSuccessful) {
                Set-ItResult -Skipped -Because 'Source file not available'
                return
            }
            $script:setupSuccessful | Should -Be $true
        }

        It 'WhatIf mode shows preview without creating RAR files' {
            if (-not $script:setupSuccessful) {
                Set-ItResult -Skipped -Because 'Setup failed'
                return
            }
            $outputDir = Join-Path -Path $script:testWorkDir -ChildPath 'output'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            Invoke-SrrRestore -SrrFile $script:workSrrPath -SourcePath $script:sourceDir -OutputPath $outputDir -WhatIf

            $createdRars = Get-ChildItem -Path $outputDir -Filter '*.rar' -ErrorAction 'SilentlyContinue'
            $createdRars.Count | Should -Be 0
        }

        It 'Completes full restore' {
            if (-not $script:setupSuccessful) {
                Set-ItResult -Skipped -Because 'Setup failed'
                return
            }
            $outputDir = Join-Path -Path $script:testWorkDir -ChildPath 'output-full'
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

            # Use -SkipValidation because Plex source files won't have matching CRCs
            # (they're transcoded/different from the original scene release files)
            Invoke-SrrRestore -SrrFile $script:workSrrPath -SourcePath $script:sourceDir -OutputPath $outputDir -KeepSrr -SkipValidation -Confirm:$false

            $createdRars = Get-ChildItem -Path $outputDir -Filter '*.rar' -ErrorAction 'SilentlyContinue'
            $createdRars.Count | Should -BeGreaterThan 0
        }

        It 'DeleteSources parameter removes source files after restore' {
            if (-not $script:setupSuccessful) {
                Set-ItResult -Skipped -Because 'Setup failed'
                return
            }

            # Create a separate test directory for DeleteSources test
            $deleteSourcesDir = Join-Path -Path $script:testWorkDir -ChildPath 'delete-sources-test'
            $deleteSourcesSource = Join-Path -Path $deleteSourcesDir -ChildPath 'source'
            $deleteSourcesOutput = Join-Path -Path $deleteSourcesDir -ChildPath 'output'
            New-Item -Path $deleteSourcesSource -ItemType Directory -Force | Out-Null
            New-Item -Path $deleteSourcesOutput -ItemType Directory -Force | Out-Null

            # Copy SRR and source file
            Copy-Item -Path $script:workSrrPath -Destination $deleteSourcesOutput
            $sourceFiles = Get-ChildItem -Path $script:sourceDir -File
            foreach ($file in $sourceFiles) {
                Copy-Item -Path $file.FullName -Destination $deleteSourcesSource
            }

            # Get the source file path for verification
            $testSourceFile = Get-ChildItem -Path $deleteSourcesSource -File | Select-Object -First 1
            $testSourceFile | Should -Not -BeNull

            # Run restore with DeleteSources
            $srrInOutput = Get-ChildItem -Path $deleteSourcesOutput -Filter '*.srr' | Select-Object -First 1
            Invoke-SrrRestore -SrrFile $srrInOutput.FullName -SourcePath $deleteSourcesSource -OutputPath $deleteSourcesOutput -DeleteSources -SkipValidation -Confirm:$false

            # Verify source file was deleted
            Test-Path -Path $testSourceFile.FullName | Should -Be $false

            # Cleanup
            Remove-Item -Path $deleteSourcesDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        AfterAll {
            if ($script:testWorkDir -and (Test-Path -Path $script:testWorkDir)) {
                Remove-Item -Path $script:testWorkDir -Recurse -Force -ErrorAction 'SilentlyContinue'
            }

            # Note: Cached source files are cleaned up by TTL and CI runner temp cleanup
        }
    }
}

# =============================================================================
# SRS PARSING AND RECONSTRUCTION TESTS
# =============================================================================

Describe 'ConvertFrom-SrsFileMetadata' -Skip:($script:skipFunctionalTests -or $script:srsSampleTests.Count -eq 0) {

    Context 'Parsing <_.Name>' -ForEach $script:srsSampleTests -AllowNullOrEmptyForEach {

        BeforeAll {
            $sample = $_

            # The .srs is stored inside the .srr, so extract it first.
            # Export-StoredFile is private; reach into the module the same way the
            # tests under tests/Private do.
            $script:srsPath = Join-Path -Path $script:tempDir -ChildPath $sample.Name
            InModuleScope 'ReScenePS' -Parameters @{
                srr    = $sample.SrrPath
                member = $sample.StoredSrs
                dest   = $script:srsPath
            } {
                Export-StoredFile -SrrFile $srr -FileName $member -OutputPath $dest
            }

            $script:metadata = ConvertFrom-SrsFileMetadata -SrsFilePath $script:srsPath
        }

        AfterAll {
            if ($script:srsPath -and (Test-Path -Path $script:srsPath)) {
                Remove-Item -Path $script:srsPath -Force -ErrorAction 'SilentlyContinue'
            }
        }

        It 'Extracts the stored SRS from the SRR' {
            $script:srsPath | Should -Exist
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

        # -Skip: is evaluated during discovery, so it can only read the -ForEach
        # data. $expectedTracks was assigned in BeforeAll, which does not run until
        # execution, so the old condition saw $null and would have skipped this
        # unconditionally had the block ever run.
        #
        # The counts in TestConfig.psd1 were taken from a raw byte scan for the
        # ReSample track element id (0x6B75), not from this function's output, so
        # this compares the EBML walk against something that does not share its
        # code.
        # $null rather than -not: an ExpectedSampleTracks of 0 is a broken config
        # entry, and -not would skip it silently instead of failing on it.
        It 'Returns the expected number of tracks' -Skip:($null -eq $_.ExpectedTracks) {
            $script:metadata.Tracks.Count | Should -Be $sample.ExpectedTracks
        }

        # Without this the loop below passes vacuously on a sample that parsed to
        # zero tracks, which is exactly the failure it exists to catch.
        It 'Returns at least one track' {
            $script:metadata.Tracks.Count | Should -BeGreaterThan 0
        }

        It 'Tracks have valid MatchOffset and DataLength' {
            foreach ($track in $script:metadata.Tracks) {
                $track.MatchOffset | Should -Not -BeNullOrEmpty
                $track.DataLength | Should -BeGreaterThan 0
            }
        }
    }
}

# Restore-SrsVideo rebuilds the sample from the release's own source video, so
# unlike the parsing tests above it cannot be driven from tests/samples -- those
# ship the .srr and nothing else. The Plex playlist is the only source of real
# media here, so this reuses the releases the Restore-Release tests below use.
Describe 'Restore-SrsVideo' -Skip:(-not $script:plexEnabled) {

    Context 'Reconstructing the sample for <_.ReleaseName>' -ForEach $script:plexReleases -AllowNullOrEmptyForEach {

        BeforeAll {
            $release = $_
            $script:srsPath = $null
            $script:sourcePath = $null
            $script:outputPath = $null
            $script:expectedSize = 0
            $script:expectedCrc32 = $null
            $script:setupSkipReason = $null

            # Get-PlexTestRelease runs once in BeforeDiscovery and again in the
            # file-level BeforeAll, so the SrrPath added to the release objects
            # there was added to a different set of objects than the ones -ForEach
            # bound here. Locate the downloaded SRR by name instead of reading a
            # property off $_ that will always be null.
            #
            # -eq rather than Get-ChildItem -Filter: -Filter is case-sensitive on
            # Linux, and the name on disk is whatever case srrdb returned.
            $srrFile = $null
            if ($script:srrDir) {
                $srrFile = Get-ChildItem -Path $script:srrDir -File -ErrorAction 'SilentlyContinue' |
                    Where-Object { $_.Name -eq "$($release.ReleaseName).srr" } |
                    Select-Object -First 1
            }

            if (-not $srrFile) {
                $script:setupSkipReason = "no SRR was downloaded for $($release.ReleaseName)"
                return
            }

            # Not every release ships a sample. One that does not has no .srs to
            # reconstruct from, which is a property of the release rather than a
            # failure of the module.
            $storedSrs = @(Get-SrrBlock -SrrFile $srrFile.FullName |
                Where-Object { $_.GetType().Name -eq 'SrrStoredFileBlock' -and $_.FileName -like '*.srs' } |
                Select-Object -First 1)

            if ($storedSrs.Count -eq 0) {
                $script:setupSkipReason = "$($release.ReleaseName) stores no .srs sample"
                return
            }

            $srsMember = $storedSrs[0].FileName
            $script:srsPath = Join-Path -Path $script:tempDir -ChildPath (Split-Path -Leaf $srsMember)
            InModuleScope 'ReScenePS' -Parameters @{
                srr    = $srrFile.FullName
                member = $srsMember
                dest   = $script:srsPath
            } {
                Export-StoredFile -SrrFile $srr -FileName $member -OutputPath $dest
            }

            # Restore-SrsVideo dispatches on the container and only handles EBML and
            # RIFF; anything else it warns about and returns $false for. Naming that
            # here keeps an unsupported container reported as unsupported rather than
            # as a reconstruction failure.
            $srsType = (InModuleScope 'ReScenePS' -Parameters @{ path = $script:srsPath } {
                Get-SrsInfo -FilePath $path
            }).Type

            if ($srsType -notmatch 'EBML|RIFF') {
                $script:setupSkipReason = "the sample for $($release.ReleaseName) is $srsType, which Restore-SrsVideo does not support"
                return
            }

            # The SRS records the original sample's size and CRC32. Both parsers
            # expose them, under different names.
            $fileData = if ($srsType -match 'EBML') {
                $metadata = ConvertFrom-SrsFileMetadata -SrsFilePath $script:srsPath
                @{ Size = $metadata.FileData.OriginalSize; Crc32 = $metadata.FileData.CRC32 }
            }
            else {
                $avi = InModuleScope 'ReScenePS' -Parameters @{ path = $script:srsPath } {
                    ConvertFrom-SrsAviFile -FilePath $path
                }
                @{ Size = $avi.FileMetadata.FileSize; Crc32 = $avi.FileMetadata.Crc32 }
            }
            $script:expectedSize = [uint64]$fileData.Size
            $script:expectedCrc32 = [uint32]$fileData.Crc32

            $script:sourcePath = InModuleScope 'ReScenePS' -Parameters @{
                name = $release.FileName
                dir  = $script:plexSourceDir
                size = [uint64]$release.FileSize
            } {
                Find-SourceFile -FileName $name -SearchPath $dir -ExpectedSize $size
            }

            if (-not $script:sourcePath) {
                $script:setupSkipReason = "the source video for $($release.ReleaseName) was not downloaded from Plex"
                return
            }

            # The sample shares the release's container, and the .srs name does not
            # record it, so take the extension from the source file.
            $sourceExtension = [System.IO.Path]::GetExtension($release.FileName)
            $outputName = [System.IO.Path]::GetFileNameWithoutExtension($script:srsPath) + $sourceExtension
            $script:outputPath = Join-Path -Path $script:tempDir -ChildPath $outputName
        }

        It 'Reconstructs the sample from the source video' {
            if ($script:setupSkipReason) {
                Set-ItResult -Skipped -Because $script:setupSkipReason
            }

            $restoreParameters = @{
                SrsFilePath   = $script:srsPath
                SourceMkvPath = $script:sourcePath
                OutputMkvPath = $script:outputPath
            }
            Restore-SrsVideo @restoreParameters | Should -BeTrue
            $script:outputPath | Should -Exist
        }

        It 'Reconstructs the sample at its original size' {
            if ($script:setupSkipReason) {
                Set-ItResult -Skipped -Because $script:setupSkipReason
            }

            # Checked against the size recorded in the SRS rather than a number
            # written down in TestConfig.psd1. Restore-SrsVideo builds the output
            # from the track offsets and lengths, never from this field, so the two
            # agreeing means the extraction and remux produced the original byte
            # count -- it is not the function checking its own arithmetic.
            $script:expectedSize | Should -BeGreaterThan 0
            (Get-Item -Path $script:outputPath).Length | Should -Be $script:expectedSize
        }

        It 'Reconstructs the sample byte for byte' {
            if ($script:setupSkipReason) {
                Set-ItResult -Skipped -Because $script:setupSkipReason
            }

            # The point of the whole exercise. Restore-SrsVideo returns $true once
            # it has written a file and never verifies the result, so without this
            # the tests above would accept a corrupt sample of the right length.
            $actualCrc32 = InModuleScope 'ReScenePS' -Parameters @{ path = $script:outputPath } {
                Get-Crc32 -FilePath $path
            }
            $actualCrc32 | Should -Be $script:expectedCrc32
        }

        AfterAll {
            foreach ($path in @($script:outputPath, $script:srsPath)) {
                if ($path -and (Test-Path -Path $path)) {
                    Remove-Item -Path $path -Force -ErrorAction 'SilentlyContinue'
                }
            }
        }
    }
}

# =============================================================================
# RESTORE-RELEASE INTEGRATION TESTS
# Tests the full automation workflow using releases discovered from Plex
# =============================================================================

Describe 'Restore-Release - Integration' -Skip:(-not $script:plexEnabled -or -not $script:srrdbAvailable) {

    Context 'Srrdb query and parse for <_.ReleaseName>' -ForEach $script:plexReleases -AllowNullOrEmptyForEach {

        BeforeAll {
            $release = $_
            $safeName = $release.ReleaseName -replace '[^\w\-\.]', '_'

            $script:testWorkDir = Join-Path -Path $script:tempDir -ChildPath "restore-int-$safeName"
            $script:releaseDir = Join-Path -Path $script:testWorkDir -ChildPath $release.ReleaseName
            New-Item -Path $script:releaseDir -ItemType Directory -Force | Out-Null

            $script:testSucceeded = $false
        }

        It 'Downloads SRR from srrdb' {
            try {
                Get-SatSrr -ReleaseName $release.ReleaseName -OutPath $script:releaseDir -ErrorAction 'Stop'
                $srrFile = Get-ChildItem -Path $script:releaseDir -Filter '*.srr' -ErrorAction 'SilentlyContinue'
                $srrFile | Should -Not -BeNullOrEmpty
                $script:testSucceeded = $true
            }
            catch {
                Set-ItResult -Skipped -Because "srrdb query failed: $_"
            }
        }

        It 'Parses downloaded SRR correctly' {
            if (-not $script:testSucceeded) {
                Set-ItResult -Skipped -Because 'SRR download failed'
                return
            }

            $srrFile = Get-ChildItem -Path $script:releaseDir -Filter '*.srr' | Select-Object -First 1
            $blocks = Get-SrrBlock -SrrFile $srrFile.FullName
            $blocks | Should -Not -BeNullOrEmpty

            $headers = $blocks | Where-Object { $_.GetType().Name -eq 'SrrHeaderBlock' }
            $headers | Should -Not -BeNullOrEmpty
        }

        AfterAll {
            if ($script:testWorkDir -and (Test-Path -Path $script:testWorkDir)) {
                Remove-Item -Path $script:testWorkDir -Recurse -Force -ErrorAction 'SilentlyContinue'
            }
        }
    }

    Context 'Recurse mode - multiple releases' -Skip:($script:plexReleases.Count -lt 2) {

        BeforeAll {
            $script:recurseTestDir = Join-Path -Path $script:tempDir -ChildPath 'restore-recurse-test'
            if (Test-Path $script:recurseTestDir) {
                Remove-Item -Path $script:recurseTestDir -Recurse -Force
            }
            New-Item -Path $script:recurseTestDir -ItemType Directory -Force | Out-Null

            # Use discovered releases from playlist
            $script:releaseSubDirs = @()
            foreach ($release in $script:plexReleases) {
                $subDir = Join-Path -Path $script:recurseTestDir -ChildPath $release.ReleaseName
                New-Item -Path $subDir -ItemType Directory -Force | Out-Null
                $script:releaseSubDirs += $subDir
            }

            # Also create a fake release dir that won't be found on srrdb
            $fakeDir = Join-Path -Path $script:recurseTestDir -ChildPath 'Fake.Release.2024.NotOnSrrdb-TEST'
            New-Item -Path $fakeDir -ItemType Directory -Force | Out-Null
        }

        It 'Processes multiple subdirectories' {
            $subdirs = Get-ChildItem -Path $script:recurseTestDir -Directory
            $result = Restore-Release -Path $script:recurseTestDir -Recurse -WhatIf
            $result | Should -Not -BeNull
            $result.Processed | Should -BeGreaterOrEqual $subdirs.Count
        }

        It 'Skips releases not found on srrdb gracefully' {
            $result = Restore-Release -Path $script:recurseTestDir -Recurse -WhatIf -ErrorAction 'SilentlyContinue'
            $result.Skipped | Should -BeGreaterOrEqual 1
        }

        AfterAll {
            if ($script:recurseTestDir -and (Test-Path -Path $script:recurseTestDir)) {
                Remove-Item -Path $script:recurseTestDir -Recurse -Force -ErrorAction 'SilentlyContinue'
            }
        }
    }

    Context 'Full workflow with Plex source' -Skip:($script:plexReleases.Count -eq 0) {

        BeforeAll {
            # Use first discovered release from playlist that has an SRR downloaded
            $script:fullWorkflowRelease = $null
            $script:fullSrrPath = $null

            foreach ($release in $script:plexReleases) {
                if ($script:srrDir) {
                    $srrFile = Get-ChildItem -Path $script:srrDir -Filter "$($release.ReleaseName).srr" -ErrorAction 'SilentlyContinue'
                    if ($srrFile) {
                        $script:fullWorkflowRelease = $release
                        $script:fullSrrPath = $srrFile.FullName
                        break
                    }
                }
            }

            if ($script:fullWorkflowRelease) {
                $release = $script:fullWorkflowRelease
                $safeName = $release.ReleaseName -replace '[^\w\-\.]', '_'
                $script:fullWorkflowDir = Join-Path -Path $script:tempDir -ChildPath "restore-full-$safeName"
                $script:fullReleaseDir = Join-Path -Path $script:fullWorkflowDir -ChildPath $release.ReleaseName
                New-Item -Path $script:fullReleaseDir -ItemType Directory -Force | Out-Null
            }
        }

        It 'Completes full restore workflow' {
            if (-not $script:fullWorkflowRelease -or -not $script:fullSrrPath) {
                Set-ItResult -Skipped -Because 'No releases with SRR available'
                return
            }

            $release = $script:fullWorkflowRelease

            # Find source file from Plex download
            $extension = [System.IO.Path]::GetExtension($release.FileName)
            $sourceFiles = Get-ChildItem -Path $script:plexSourceDir -Recurse -File |
                Where-Object { $_.Extension -eq $extension }

            $sourceFile = if ($sourceFiles.Count -eq 1) {
                $sourceFiles[0].FullName
            } else {
                $sourceFiles | Where-Object { $_.Length -eq $release.FileSize } |
                    Select-Object -First 1 -ExpandProperty FullName
            }

            if (-not $sourceFile) {
                Set-ItResult -Skipped -Because 'Source file not found'
                return
            }

            # Copy SRR to release dir
            Copy-Item -Path $script:fullSrrPath -Destination $script:fullReleaseDir -Force

            # Get expected filename from SRR and copy source
            $srrBlocks = Get-SrrBlock -SrrFile $script:fullSrrPath
            $packedFiles = $srrBlocks | Where-Object { $_.GetType().Name -eq 'RarPackedFileBlock' }
            $mainFile = $packedFiles |
                Where-Object { $_.FileName -match '\.(mkv|avi|mp4|m2ts)$' } |
                Sort-Object -Property UnpackedSize -Descending |
                Select-Object -First 1

            if ($mainFile) {
                $destPath = Join-Path $script:fullReleaseDir $mainFile.FileName
                Copy-Item -Path $sourceFile -Destination $destPath -Force
            }

            # Run full restore (with SkipValidation since Plex source may differ)
            $result = Restore-Release -Path $script:fullReleaseDir -KeepSrr -SkipValidation -Confirm:$false

            $result.Succeeded | Should -Be 1

            $rarFiles = Get-ChildItem -Path $script:fullReleaseDir -Filter '*.rar' -ErrorAction 'SilentlyContinue'
            $rarFiles.Count | Should -BeGreaterThan 0
        }

        AfterAll {
            if ($script:fullWorkflowDir -and (Test-Path -Path $script:fullWorkflowDir)) {
                Remove-Item -Path $script:fullWorkflowDir -Recurse -Force -ErrorAction 'SilentlyContinue'
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
            $result = Restore-SrsVideo -SrsFilePath 'C:\nonexistent\file.srs' -SourceMkvPath 'C:\nonexistent\source.mkv' -OutputMkvPath 'C:\output.mkv' -ErrorAction 'Stop'
        } catch {
            $threw = $true
        }
        # Either it threw an exception or returned false - both are acceptable error handling
        ($threw -or $result -eq $false) | Should -Be $true
    }
}
