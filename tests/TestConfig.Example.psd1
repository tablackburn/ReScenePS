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
    # 2. PlexSourceMappings - Plex server (new, requires PlexDataSource config)
    # ==========================================================================
    SrrReconstructionTests = @(
        # ------------------------------------------------------------------
        # PUBLIC DOMAIN EXAMPLES - Use with Plex source
        # These use films in the public domain for copyright-free testing
        # ------------------------------------------------------------------
        # @{
        #     ReleaseName      = 'Night.Of.The.Living.Dead.1968.1080p.Bluray.x264-hV'
        #     SrrPath          = 'tests\samples\Night.Of.The.Living.Dead.1968.1080p.Bluray.x264-hV.srr'
        #     RelativeTo       = 'ProjectRoot'
        #     ReleaseType      = 'Movie-1080p-x264-PublicDomain'
        #     # No NetworkPath - uses Plex source via PlexSourceMappings
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
    # 4. Run Initialize-PlexTestCollection.ps1 to create the collection
    # 5. Copy the generated PlexSourceMappings below
    #
    # Or for CI/CD, set environment variables:
    #   PAT_SERVER_URI = 'https://your-plex-server:32400'
    #   PAT_TOKEN = 'your-plex-token'
    # ==========================================================================
    PlexDataSource = @{
        # Set to $true to enable Plex-sourced tests
        Enabled = $false

        # Name of the Plex collection containing test releases
        # Create with: .\tests\Initialize-PlexTestCollection.ps1
        CollectionName = 'ReScenePS-TestData'

        # Plex library to search (Movies, TV Shows, etc.)
        LibraryName = 'Movies'

        # Local cache directory for downloaded files
        # If not specified, uses $env:TEMP/ReScenePS-PlexCache
        CachePath = $null

        # Cache TTL in hours (0 = always redownload, -1 = never expire)
        # Default: 168 (1 week)
        CacheTtlHours = 168
    }

    # ==========================================================================
    # PLEX SOURCE MAPPINGS
    # Maps SRR files to Plex library items for reconstruction tests
    #
    # Run Initialize-PlexTestCollection.ps1 to auto-generate these mappings
    # based on your Plex library contents and SRR sample files.
    #
    # Key = SRR filename (matches files in tests/samples/)
    # Value = Search criteria to find the item in Plex
    #   - RatingKey: Direct Plex item ID (fastest, most reliable)
    #   - Title: Movie/show title for search
    #   - Year: Release year (for movies)
    #   - ShowTitle, Season, Episode: For TV episodes
    # ==========================================================================
    PlexSourceMappings = @{
        # ------------------------------------------------------------------
        # PUBLIC DOMAIN FILM MAPPINGS
        # Update RatingKey values to match your Plex library
        # Find RatingKey by running: Get-PatLibraryItem -SectionName 'Movies' |
        #   Where-Object { $_.title -like '*Night*Living*' } | Select ratingKey, title
        # ------------------------------------------------------------------
        # 'Night.Of.The.Living.Dead.1968.1080p.Bluray.x264-hV.srr' = @{
        #     RatingKey = 5503      # Update with your Plex ratingKey
        #     Title     = 'Night of the Living Dead'
        #     Year      = 1968
        # }
        # 'Metropolis.1927.1080p.BluRay.x264-AVCHD.srr' = @{
        #     RatingKey = 455999    # Update with your Plex ratingKey
        #     Title     = 'Metropolis'
        #     Year      = 1927
        # }
        # 'Sherlock.Jr.1924.1080p.BluRay.x264-PSYCHD.srr' = @{
        #     RatingKey = 484800    # Update with your Plex ratingKey
        #     Title     = 'Sherlock Jr.'
        #     Year      = 1924
        # }
        # 'Battleship.Potemkin.1925.1080p.BluRay.x264-CiNEFiLE.srr' = @{
        #     RatingKey = 527908    # Update with your Plex ratingKey
        #     Title     = 'Battleship Potemkin'
        #     Year      = 1925
        # }
        # 'The.Kid.1921.1080p.BluRay.x264-AVCHD.srr' = @{
        #     RatingKey = 458863    # Update with your Plex ratingKey
        #     Title     = 'The Kid'
        #     Year      = 1921
        # }

        # ------------------------------------------------------------------
        # CUSTOM MAPPINGS - add your own
        # ------------------------------------------------------------------
        # 'Your.Release.Name.srr' = @{
        #     RatingKey = 12345
        #     Title     = 'Movie Title'
        #     Year      = 2020
        # }
    }
}
