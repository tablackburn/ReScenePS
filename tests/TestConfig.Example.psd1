# ReScenePS Functional Test Configuration Template
# Copy this file to TestConfig.psd1 and update paths for your environment
# TestConfig.psd1 is gitignored and will not be committed

@{
    # ==========================================================================
    # PUBLIC DOMAIN RELEASES
    # These films are in the public domain and can be used for testing without
    # copyright concerns. Scene releases exist on srrdb.com for all of these.
    #
    # Pre-1928 (US public domain):
    #   - The Kid (1921) - Charlie Chaplin
    #   - Sherlock Jr. (1924) - Buster Keaton
    #   - Battleship Potemkin (1925) - Sergei Eisenstein
    #   - Metropolis (1927) - Fritz Lang
    #
    # Post-1928 with lapsed copyright:
    #   - Night of the Living Dead (1968) - George Romero
    #
    # Download SRR files from: https://www.srrdb.com/browse/<release-name>
    # ==========================================================================

    # ==========================================================================
    # SRR PARSING TESTS (no source files needed)
    # These test Get-SrrBlock and Show-SrrInfo
    # Organized by release type for comprehensive codec/format coverage
    # ==========================================================================
    SrrParsingTests = @(
        # ------------------------------------------------------------------
        # PUBLIC DOMAIN EXAMPLES - Download SRR files from srrdb.com
        # ------------------------------------------------------------------
        # @{
        #     Path                 = 'tests\samples\Night.Of.The.Living.Dead.1968.1080p.Bluray.x264-hV.srr'
        #     RelativeTo           = 'ProjectRoot'
        #     ReleaseType          = 'Movie-1080p-x264-PublicDomain'
        #     ExpectedBlockCount   = $null  # Set after first parse
        #     ExpectedStoredFiles  = @()    # Set after first parse
        #     ExpectedRarCount     = $null  # Set after first parse
        #     CreatingApplication  = $null  # Set after first parse
        #     SampleType           = 'MKV'
        # }
        # @{
        #     Path                 = 'tests\samples\Metropolis.1927.1080p.BluRay.x264-AVCHD.srr'
        #     RelativeTo           = 'ProjectRoot'
        #     ReleaseType          = 'Movie-1080p-x264-PublicDomain'
        #     SampleType           = 'MKV'
        # }
        # @{
        #     Path                 = 'tests\samples\Sherlock.Jr.1924.1080p.BluRay.x264-PSYCHD.srr'
        #     RelativeTo           = 'ProjectRoot'
        #     ReleaseType          = 'Movie-1080p-x264-PublicDomain'
        #     SampleType           = 'MKV'
        # }

        # ------------------------------------------------------------------
        # CUSTOM ENTRY TEMPLATE - copy and modify for each SRR sample
        # ------------------------------------------------------------------
        @{
            # Path to SRR file (relative to ProjectRoot or absolute)
            Path                 = 'tests\samples\Example.Release-GROUP.srr'
            RelativeTo           = 'ProjectRoot'

            # Descriptive label for test output
            ReleaseType          = 'Movie-720p-x264'

            # Expected values for validation (set after first successful parse)
            ExpectedBlockCount   = 100
            ExpectedStoredFiles  = @('example.nfo', 'example.sfv', 'Sample/example.srs')
            ExpectedRarCount     = 20
            CreatingApplication  = 'pyReScene Auto 0.5'

            # Container type: 'MKV' or 'AVI'
            SampleType           = 'MKV'
        }
    )

    # ==========================================================================
    # RAR RECONSTRUCTION TESTS
    # These test Invoke-SrrReconstruct and Invoke-SrrRestore
    # Requires: SRR file + source content file (the original MKV/video)
    #
    # Source files can come from:
    # 1. NetworkPath - local network share (existing behavior)
    # 2. Plex playlist - auto-discovered by matching file paths to release names
    # ==========================================================================
    SrrReconstructionTests = @(
        # ------------------------------------------------------------------
        # PUBLIC DOMAIN EXAMPLES - Use with Plex source
        # These use films in the public domain for copyright-free testing
        # Add these to your 'ReScenePS-TestData' playlist in Plex
        # ------------------------------------------------------------------
        # @{
        #     ReleaseName      = 'Night.Of.The.Living.Dead.1968.1080p.Bluray.x264-hV'
        #     SrrPath          = 'tests\samples\Night.Of.The.Living.Dead.1968.1080p.Bluray.x264-hV.srr'
        #     RelativeTo       = 'ProjectRoot'
        #     ReleaseType      = 'Movie-1080p-x264-PublicDomain'
        #     # No NetworkPath - auto-discovered from Plex playlist
        # }
        # @{
        #     ReleaseName      = 'Metropolis.1927.1080p.BluRay.x264-AVCHD'
        #     SrrPath          = 'tests\samples\Metropolis.1927.1080p.BluRay.x264-AVCHD.srr'
        #     RelativeTo       = 'ProjectRoot'
        #     ReleaseType      = 'Movie-1080p-x264-PublicDomain'
        # }
        # @{
        #     ReleaseName      = 'Sherlock.Jr.1924.1080p.BluRay.x264-PSYCHD'
        #     SrrPath          = 'tests\samples\Sherlock.Jr.1924.1080p.BluRay.x264-PSYCHD.srr'
        #     RelativeTo       = 'ProjectRoot'
        #     ReleaseType      = 'Movie-1080p-x264-PublicDomain'
        # }
        # @{
        #     ReleaseName      = 'Battleship.Potemkin.1925.1080p.BluRay.x264-CiNEFiLE'
        #     SrrPath          = 'tests\samples\Battleship.Potemkin.1925.1080p.BluRay.x264-CiNEFiLE.srr'
        #     RelativeTo       = 'ProjectRoot'
        #     ReleaseType      = 'Movie-1080p-x264-PublicDomain'
        # }
        # @{
        #     ReleaseName      = 'The.Kid.1921.1080p.BluRay.x264-AVCHD'
        #     SrrPath          = 'tests\samples\The.Kid.1921.1080p.BluRay.x264-AVCHD.srr'
        #     RelativeTo       = 'ProjectRoot'
        #     ReleaseType      = 'Movie-1080p-x264-PublicDomain'
        # }

        # ------------------------------------------------------------------
        # CUSTOM ENTRY TEMPLATE - network path approach
        # ------------------------------------------------------------------
        @{
            ReleaseName      = 'Example.Release.720p.BluRay.x264-GROUP'
            SrrPath          = 'tests\samples\Example.Release.720p.BluRay.x264-GROUP.srr'
            RelativeTo       = 'ProjectRoot'
            ReleaseType      = 'Movie-720p-x264'
            NetworkPath      = '\\server\scene\X264\Example.Release.720p.BluRay.x264-GROUP'
        }
    )

    # ==========================================================================
    # SRS SAMPLE RECONSTRUCTION TESTS
    # These test ConvertFrom-SrsFileMetadata, Build-SampleMkvFromSrs, Restore-SrsVideo
    # Requires: SRS file (extracted from SRR) + source MKV (extracted from release RARs)
    # ==========================================================================
    SrsSampleTests = @(
        # MKV sample tests - will be dynamically populated from SrrReconstructionTests
        # where SampleType = 'MKV', or define explicitly:
        # @{
        #     SrsPath          = 'path\to\sample.srs'
        #     SourceMkvPath    = 'path\to\source.mkv'
        #     ExpectedTracks   = 2
        #     ExpectedSize     = 52428800
        # }
    )

    # ==========================================================================
    # NETWORK PATHS (for reference)
    # These are the network shares containing scene releases
    # ==========================================================================
    NetworkPaths = @{
        Scene1 = '\\server\scene'
        Scene2 = '\\server\scene2'
    }

    # ==========================================================================
    # PLEX DATA SOURCE CONFIGURATION (optional)
    # Enables running tests with source files downloaded from a Plex server
    # Requires: PlexAutomationToolkit module (Install-Module PlexAutomationToolkit)
    #
    # Setup steps:
    # 1. Install PlexAutomationToolkit: Install-Module PlexAutomationToolkit
    # 2. Connect to your Plex account: Connect-PatAccount
    # 3. Add your server: Add-PatServer -ServerName 'MyPlex' -Default
    # 4. Create a playlist named 'ReScenePS-TestData' and add test media to it
    # 5. Ensure media files are stored in paths containing the release name
    #    (e.g., .../24.S01E01.DVDRip.XViD.INTERNAL-iMAGiNE/24.s01e01.avi)
    #
    # Or for CI/CD, set environment variables:
    #   PAT_SERVER_URI = 'https://your-plex-server:32400'
    #   PAT_TOKEN = 'your-plex-token'
    #
    # Privacy: Playlists are user-specific and not visible to other Plex users.
    # Source files are downloaded fresh each run and cleaned up after tests.
    # ==========================================================================
    PlexDataSource = @{
        # Set to $true to enable Plex-sourced tests
        Enabled = $false

        # Name of the Plex playlist containing test releases
        # Items are auto-discovered by matching file paths to release names
        PlaylistName = 'ReScenePS-TestData'
    }
}
