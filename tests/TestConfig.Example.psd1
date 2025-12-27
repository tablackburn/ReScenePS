# Functional Test Configuration Template
# Copy this file to TestConfig.psd1 and update paths for your environment
# TestConfig.psd1 is gitignored and will not be committed

@{
    # Base path to sample files (network share or local directory)
    # All relative paths in SrrSamples and SrsSamples are resolved from here
    SampleBasePath = '\\server\scene-samples'

    # SRR test samples - each entry tests SRR parsing and reconstruction
    SrrSamples = @(
        @{
            # Relative path from SampleBasePath to the .srr file
            Path = 'Example.Release-GRP\example.srr'

            # Expected values for validation (set after first successful parse)
            ExpectedBlockCount       = 45
            ExpectedStoredFiles      = @('example.nfo', 'example.sfv')
            ExpectedRarVolumes       = @('example.rar', 'example.r00', 'example.r01')

            # Source files needed for reconstruction
            # Key = filename as referenced in SRR, Value = path relative to SampleBasePath
            SourceFiles = @{
                'movie.mkv' = 'sources\movie.mkv'
            }

            # Expected CRC32 values from SFV (optional, for reconstruction validation)
            ExpectedCrcs = @{
                'example.rar' = 'A1B2C3D4'
                'example.r00' = 'E5F6A7B8'
                'example.r01' = 'C9D0E1F2'
            }
        }
        # Add more SRR samples as needed:
        # @{
        #     Path = 'Another.Release-GRP\another.srr'
        #     ExpectedBlockCount = 30
        #     ...
        # }
    )

    # SRS test samples - each entry tests SRS parsing and video sample reconstruction
    SrsSamples = @(
        @{
            # Relative path from SampleBasePath to the .srs file
            Path = 'Example.Release-GRP\example-sample.srs'

            # Path to the source MKV (main movie file) for track data extraction
            SourceMkv = 'sources\movie.mkv'

            # Expected metadata values
            ExpectedTracks       = 2
            ExpectedOriginalSize = 52428800  # Original sample size in bytes

            # Optional: expected CRC32 of reconstructed sample
            ExpectedCrc = 'DEADBEEF'
        }
        # Add more SRS samples as needed
    )
}
