# ReScenePS Functional Test Configuration
# This file is committed to git and used by CI
# For local network paths, create TestConfig.Local.psd1 (gitignored)

@{
    # ==========================================================================
    # SRR PARSING TESTS (no source files needed)
    # These test Get-SrrBlock and Show-SrrInfo
    # Organized by release type for comprehensive codec/format coverage
    # ==========================================================================
    SrrParsingTests = @(
        # ------------------------------------------------------------------
        # MOVIES - XviD (AVI container)
        # ------------------------------------------------------------------
        @{
            Path                 = 'tests\samples\007.A.View.To.A.Kill.1985.UE.iNTERNAL.DVDRip.XviD-iNCiTE.srr'
            RelativeTo           = 'ProjectRoot'
            ReleaseType          = 'Movie-XviD'
            ExpectedBlockCount   = 500
            ExpectedStoredFiles  = @('incite-avtak.ue.xvid.nfo', 'Sample/incite-avtak.ue.xvid-sample.srs', 'CD1/incite-avtak.ue.xvid.cd1.sfv', 'CD2/incite-avtak.ue.xvid.cd2.sfv')
            ExpectedRarCount     = 98
            CreatingApplication  = 'ReScene .NET 1.3.3 GUI (beta)'
            SampleType           = 'AVI'
        }

        # ------------------------------------------------------------------
        # MOVIES - SD x264 (MKV container, DVDRip)
        # ------------------------------------------------------------------
        @{
            Path                 = 'tests\samples\The.Mummy.Resurrected.2014.PROPER.DVDRiP.X264-TASTE.srr'
            RelativeTo           = 'ProjectRoot'
            ReleaseType          = 'Movie-SD-x264'
            ExpectedBlockCount   = 171
            ExpectedStoredFiles  = @('the.mummy.resurrected.2014.proper.dvdrip.x264-taste.nfo', 'Proof/proof-the.mummy.resurrected.2014.proper.dvdrip.x264-taste.jpg', 'Sample/the.mummy.resurrected.2014.proper.dvdrip.x264-taste-sample.srs', 'the.mummy.resurrected.2014.proper.dvdrip.x264-taste.sfv')
            ExpectedRarCount     = 33
            CreatingApplication  = 'pyReScene Auto 0.5'
            SampleType           = 'MKV'
        }

        # ------------------------------------------------------------------
        # MOVIES - 720p x264 (MKV container, BluRay)
        # ------------------------------------------------------------------
        @{
            Path                 = 'tests\samples\007.For.Your.Eyes.Only.1981.720p.BluRay.x264-HANGOVER.srr'
            RelativeTo           = 'ProjectRoot'
            ReleaseType          = 'Movie-720p-x264'
            ExpectedBlockCount   = 360
            ExpectedStoredFiles  = @('h-007fyeo-x264.nfo', 'Sample/h-007fyeo-x264-sample.srs', 'h-007fyeo-x264.sfv')
            ExpectedRarCount     = 71
            CreatingApplication  = 'ReScene .NET 1.2'
            SampleType           = 'MKV'
        }

        # ------------------------------------------------------------------
        # MOVIES - 1080p x264 (MKV container, BluRay)
        # ------------------------------------------------------------------
        @{
            Path                 = 'tests\samples\009-1.The.End.Of.The.Beginning.2013.1080p.BluRay.x264-PFa.srr'
            RelativeTo           = 'ProjectRoot'
            ReleaseType          = 'Movie-1080p-x264'
            ExpectedBlockCount   = 301
            ExpectedStoredFiles  = @('pfa-009.re.cyborg.1080p.nfo', 'Proof/pfa-009.re.cyborg.1080p.proof.jpg', 'Sample/pfa-009.re.cyborg.1080p.sample.srs', 'pfa-009.re.cyborg.1080p.sfv')
            ExpectedRarCount     = 59
            CreatingApplication  = 'pyReScene Auto 0.5'
            SampleType           = 'MKV'
        }

        # ------------------------------------------------------------------
        # MOVIES - 2160p x265/HEVC (MKV container, UHD BluRay)
        # ------------------------------------------------------------------
        @{
            Path                 = 'tests\samples\1917.2019.2160p.UHD.BluRay.x265-AAAUHD.srr'
            RelativeTo           = 'ProjectRoot'
            ReleaseType          = 'Movie-2160p-x265'
            ExpectedBlockCount   = 460
            ExpectedStoredFiles  = @('1917.2019.2160p.uhd.bluray.x265-aaauhd.nfo', 'Sample/1917.2019.2160p.uhd.bluray.x265-aaauhd-sample.srs', '1917.2019.2160p.uhd.bluray.x265-aaauhd.sfv')
            ExpectedRarCount     = 91
            CreatingApplication  = 'pyReScene Auto 0.7'
            SampleType           = 'MKV'
        }

        # ------------------------------------------------------------------
        # MOVIES - Complete BluRay (disc image releases)
        # ------------------------------------------------------------------
        @{
            Path                 = 'tests\samples\Skyfall.2012.COMPLETE.BLURAY-LAZERS.srr'
            RelativeTo           = 'ProjectRoot'
            ReleaseType          = 'Movie-BluRay-Complete'
            ExpectedBlockCount   = 494
            ExpectedStoredFiles  = @('lazers-skyfall.nfo', 'Sample/lazers-skyfall.sample.srs', 'lazers-skyfall.sfv')
            ExpectedRarCount     = 98
            CreatingApplication  = 'pyReScene 0.1'
            SampleType           = 'MKV'
        }
        @{
            Path                 = 'tests\samples\Serenity.2005.COMPLETE.BLURAY-WHiZZ.srr'
            RelativeTo           = 'ProjectRoot'
            ReleaseType          = 'Movie-BluRay-Complete'
            ExpectedBlockCount   = 426
            ExpectedStoredFiles  = @('serenity.2005.complete.bluray-whizz.nfo', 'Proof/proof-serenity.2005.complete.bluray-whizz.jpg', 'Sample/sample-serenity.2005.complete.bluray-whizz.srs', 'serenity.2005.complete.bluray-whizz.sfv')
            ExpectedRarCount     = 84
            CreatingApplication  = 'pyReScene Auto 0.5'
            SampleType           = 'MKV'
        }
        @{
            Path                 = 'tests\samples\Iron.Man.3.2013.COMPLETE.BluRay-TRUEDEF.srr'
            RelativeTo           = 'ProjectRoot'
            ReleaseType          = 'Movie-BluRay-Complete'
            ExpectedBlockCount   = 471
            ExpectedStoredFiles  = @('truedef-ironmanlegit.nfo', 'Proof/truedef-ironmanlegit-proof.jpg', 'Sample/trudef-ironman3legit-sample.srs', 'truedef-ironmanlegit.sfv')
            ExpectedRarCount     = 93
            CreatingApplication  = 'pyReScene Auto 0.5'
            SampleType           = 'MKV'
        }

        # ------------------------------------------------------------------
        # TV SHOWS - XviD (AVI container)
        # ------------------------------------------------------------------
        @{
            Path                 = 'tests\samples\24.S01E01.DVDRip.XViD.INTERNAL-iMAGiNE.srr'
            RelativeTo           = 'ProjectRoot'
            ReleaseType          = 'TV-XviD'
            ExpectedBlockCount   = 119
            ExpectedStoredFiles  = @('24.s01e01.xvid.imagine.nfo', 'Sample/24.s01e01.sample.srs', '24.s01e01.xvid.imagine.sfv')
            ExpectedRarCount     = 19
            CreatingApplication  = 'pyReScene Auto 0.6'
            SampleType           = 'AVI'
        }

        # ------------------------------------------------------------------
        # TV SHOWS - SD x264 (MKV container, DVDRip)
        # ------------------------------------------------------------------
        @{
            Path                 = 'tests\samples\Teenage.Mutant.Ninja.Turtles.2012.S01E01-02.DVDRip.x264-DEiMOS.srr'
            RelativeTo           = 'ProjectRoot'
            ReleaseType          = 'TV-SD-x264'
            ExpectedBlockCount   = 126
            ExpectedStoredFiles  = @('teenage.mutant.ninja.turtles.2012.s01e01-02.dvdrip.x264-deimos.nfo', 'Proof/proof-teenage.mutant.ninja.turtles.2012.s01e01-02.dvdrip.x264-deimos.jpg', 'Sample/sample-teenage.mutant.ninja.turtles.2012.s01e01-02.rise.of.the.turtles.dvdrip.x264-deimos.srs', 'teenage.mutant.ninja.turtles.2012.s01e01-02.dvdrip.x264-deimos.sfv')
            ExpectedRarCount     = 24
            CreatingApplication  = 'pyReScene Auto 0.5'
            SampleType           = 'MKV'
        }

        # ------------------------------------------------------------------
        # TV SHOWS - 720p x264 (MKV container, BluRay)
        # ------------------------------------------------------------------
        @{
            Path                 = 'tests\samples\Game.of.Thrones.S01E01.720p.BluRay.X264-REWARD.srr'
            RelativeTo           = 'ProjectRoot'
            ReleaseType          = 'TV-720p-x264'
            ExpectedBlockCount   = 236
            ExpectedStoredFiles  = @('game.of.thrones.s01e01.720p.bluray.x264-reward.nfo', 'Proof/game.of.thrones.s01e01.720p.bluray.x264-reward.proof.jpg', 'Sample/game.of.thrones.s01e01.720p.bluray.x264-reward.sample.srs', 'Subs/game.of.thrones.s01e01.720p.bluray.x264-reward.subs.srr', 'Subs/game.of.thrones.s01e01.720p.bluray.x264-reward.subs.sfv', 'game.of.thrones.s01e01.720p.bluray.x264-reward.sfv')
            ExpectedRarCount     = 57
            CreatingApplication  = 'ReScene .NET Beta 11'
            SampleType           = 'MKV'
        }

        # ------------------------------------------------------------------
        # TV SHOWS - 1080p x264 (MKV container, BluRay)
        # ------------------------------------------------------------------
        @{
            Path                 = 'tests\samples\Game.Of.Thrones.S01E01.1080p.BluRay.x264-HD4U.srr'
            RelativeTo           = 'ProjectRoot'
            ReleaseType          = 'TV-1080p-x264'
            ExpectedBlockCount   = 296
            ExpectedStoredFiles  = @('game.of.thrones.s01e01.1080-hd4u.nfo', 'Proof/game.of.thrones.s01e01.1080-hd4u-proof.jpg', 'Sample/game.of.thrones.s01e01.1080-hd4u-sample.srs', 'Subs/game.of.thrones.s01e01.1080-hd4u-subs.srr', 'Subs/game.of.thrones.s01e01.1080-hd4u-subs.sfv', 'game.of.thrones.s01e01.1080-hd4u.sfv')
            ExpectedRarCount     = 48
            CreatingApplication  = 'ReScene .NET 1.2'
            SampleType           = 'MKV'
        }
    )

    # ==========================================================================
    # RAR RECONSTRUCTION TESTS
    # These test Invoke-SrrReconstruct and Invoke-SrrRestore
    # Requires: SRR file + source content (downloaded from Plex via PlexSourceMappings)
    # ==========================================================================
    SrrReconstructionTests = @(
        @{
            ReleaseName      = '007.For.Your.Eyes.Only.1981.720p.BluRay.x264-HANGOVER'
            SrrPath          = 'tests\samples\007.For.Your.Eyes.Only.1981.720p.BluRay.x264-HANGOVER.srr'
            RelativeTo       = 'ProjectRoot'
            ReleaseType      = 'Movie-720p-x264'
        }
        @{
            ReleaseName      = '009-1.The.End.Of.The.Beginning.2013.1080p.BluRay.x264-PFa'
            SrrPath          = 'tests\samples\009-1.The.End.Of.The.Beginning.2013.1080p.BluRay.x264-PFa.srr'
            RelativeTo       = 'ProjectRoot'
            ReleaseType      = 'Movie-1080p-x264'
        }
        @{
            ReleaseName      = 'Game.of.Thrones.S01E01.720p.BluRay.X264-REWARD'
            SrrPath          = 'tests\samples\Game.of.Thrones.S01E01.720p.BluRay.X264-REWARD.srr'
            RelativeTo       = 'ProjectRoot'
            ReleaseType      = 'TV-720p-x264'
        }
        @{
            ReleaseName      = 'Game.Of.Thrones.S01E01.1080p.BluRay.x264-HD4U'
            SrrPath          = 'tests\samples\Game.Of.Thrones.S01E01.1080p.BluRay.x264-HD4U.srr'
            RelativeTo       = 'ProjectRoot'
            ReleaseType      = 'TV-1080p-x264'
        }
        @{
            ReleaseName      = '24.S01E01.DVDRip.XViD.INTERNAL-iMAGiNE'
            SrrPath          = 'tests\samples\24.S01E01.DVDRip.XViD.INTERNAL-iMAGiNE.srr'
            RelativeTo       = 'ProjectRoot'
            ReleaseType      = 'TV-XviD'
        }
    )

    # ==========================================================================
    # SRS SAMPLE RECONSTRUCTION TESTS
    # These test ConvertFrom-SrsFileMetadata, Build-SampleMkvFromSrs, Restore-SrsVideo
    # Requires: SRS file (extracted from SRR) + source MKV (extracted from release RARs)
    # Note: AVI samples (XviD) require AVI reconstruction support (not yet implemented)
    # ==========================================================================
    SrsSampleTests = @(
        # MKV sample tests will be populated dynamically from SrrReconstructionTests
        # where SampleType = 'MKV'
    )

    # ==========================================================================
    # PLEX DATA SOURCE CONFIGURATION
    # Enables running tests with source files downloaded from a Plex server
    # For CI: Set PAT_SERVER_URI and PAT_TOKEN environment variables/secrets
    # ==========================================================================
    PlexDataSource = @{
        Enabled       = $true
        CollectionName = 'ReScenePS-TestData'
        LibraryName   = 'Movies'
        CachePath     = $null  # Uses Get-PlexCachePath (supports RUNNER_TEMP for CI)
        CacheTtlHours = 168    # 1 week
    }

    # ==========================================================================
    # PLEX SOURCE MAPPINGS
    # Maps release names to Plex RatingKeys for downloading source files
    # To find RatingKeys, run:
    #   Get-PatLibraryItem -SectionName 'Movies' | Where-Object { $_.title -like '*Title*' }
    # ==========================================================================
    PlexSourceMappings = @{
        # Movies
        '007.For.Your.Eyes.Only.1981.720p.BluRay.x264-HANGOVER.srr' = @{
            RatingKey = 4
            Title     = 'For Your Eyes Only'
            Year      = 1981
        }
        '009-1.The.End.Of.The.Beginning.2013.1080p.BluRay.x264-PFa.srr' = @{
            RatingKey = 2165
            Title     = '009-1: The End of the Beginning'
            Year      = 2013
        }

        # TV Shows (episode-level RatingKeys)
        'Game.of.Thrones.S01E01.720p.BluRay.X264-REWARD.srr' = @{
            RatingKey = 14501
            ShowTitle = 'Game of Thrones'
            Season    = 1
            Episode   = 1
        }
        'Game.Of.Thrones.S01E01.1080p.BluRay.x264-HD4U.srr' = @{
            RatingKey = 14501
            ShowTitle = 'Game of Thrones'
            Season    = 1
            Episode   = 1
        }
        '24.S01E01.DVDRip.XViD.INTERNAL-iMAGiNE.srr' = @{
            RatingKey = 26965
            ShowTitle = '24'
            Season    = 1
            Episode   = 1
        }
    }
}
