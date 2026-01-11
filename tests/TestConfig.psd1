# ReScenePS Functional Test Configuration
# This file is committed to git and used by CI

@{
    # ==========================================================================
    # SRR PARSING TESTS (no source files needed)
    # These test Get-SrrBlock and Show-SrrInfo using pre-downloaded SRR files
    # in tests/samples/. Organized by release type for comprehensive coverage.
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
    # PLEX DATA SOURCE CONFIGURATION
    # Reconstruction and integration tests dynamically discover releases from
    # this Plex playlist. Add items to the playlist to test different codecs,
    # resolutions, and release types. SRRs are downloaded from srrdb.
    #
    # Auto-enabled when PAT_SERVER_URI/PAT_TOKEN env vars are set.
    # ==========================================================================
    PlexDataSource = @{
        PlaylistName = 'ReScenePS-TestData'
    }
}
