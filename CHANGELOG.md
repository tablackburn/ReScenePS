# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

### Fixed

- `Restore-SrsVideo` produced a truncated MKV sample and reported success. An SRS
  stores each block's header and original size but not the frame data, so the
  rebuild consumed bytes that were not there, ran past the end of the SRS after
  the first block, and wrote a fraction of the sample. For a 10,123,431 byte
  sample it produced 52,755 bytes. The rebuild now also verifies its output
  against the size and CRC32 the SRS records rather than returning `$true` as
  soon as a file exists, and fails loudly when a track runs out of data instead
  of padding the gap with zeros.

- `Restore-SrsVideo` could not reconstruct MKV samples. `SourceMkvPath` and
  `OutputMkvPath` are parameter aliases, not variables, so the MKV branch passed
  empty strings and failed with "Cannot bind argument to parameter
  'MainFilePath'". The AVI branch was unaffected. This went unnoticed because the
  tests covering it had never run.

## [0.2.3] - 2026-01-11

### Added

- `Restore-Release` command for automated release restoration from SRR files
- Integration with SrrDBAutomationToolkit for SRR file downloads
- Documentation for Restore-Release command
- High-performance CRC32 implementation using compiled C# via Add-Type

### Changed

- Renamed `requirements.psd1` to `runtime.depend.psd1` for clarity
- Enhanced CI workflow with linting, caching, and branch filtering
- Refactored test helpers and functional tests for better maintainability
- Replaced pure PowerShell CRC32 with C# implementation (IEEE 802.3 polynomial)
- CI test runtime reduced from 5+ hours to ~10 minutes

### Fixed

- Flaky performance tests: added warmup phases and increased thresholds for CI stability

### Security

- Added security policy (SECURITY.md)

## [0.2.2] - 2025-12-31

### Changed

- Fix PSScriptAnalyzer warnings by adding [OutputType()] attributes to all functions
- Suppress false-positive PSUseSingularNouns warnings for acronyms (Srs) and technical terms (Bytes, Chunks)
- Fix code coverage reporting by pointing to Output directory where tests execute
- Fix cross-platform path assertion in Get-SrsInfo test

## [0.2.1] - 2025-12-30

### Added

- TestDataBuilders.psm1 module for generating synthetic MKV test files
- Tests for MKV lacing types (Xiph, Fixed-size, EBML) in Export-MkvTrackData

### Changed

- Improve code coverage from 84% to 87%

## [0.2.0] - 2025-12-29

### Added

- AVI sample reconstruction support via `Build-SampleAviFromSrs`
- Comprehensive test coverage for EBML parsing edge cases
- Fallback scanning for legacy SRS formats (0xC0/0xC1/0xC2)
- Tests for multiple tracks, unknown elements, and combined flags

### Changed

- Improved code coverage from 74% to 78%
- Fixed PSScriptAnalyzer warnings for unused variables
- Updated README with CI badges and AVI documentation

### Fixed

- Flaky performance test threshold increased for CI stability
- Empty catch block now logs verbose message for debugging

## [0.1.0] - 2025-12-26

### Added

- Initial release of ReScenePS PowerShell module
- Complete SRR (Scene Release Reconstruct) file support:
  - `Show-SrrInfo` - Display SRR file metadata and block structure
  - `Get-SrrBlock` - Parse SRR files and return block objects
  - `Invoke-SrrReconstruct` - Reconstruct RAR archives from SRR metadata
  - `Invoke-SrrRestore` - Complete end-to-end restoration workflow with validation
- Complete SRS (Sample Reconstruction) file support:
  - `ConvertFrom-SrsFileMetadata` - Parse EBML SRS file metadata
  - `Export-SampleTrackData` - Extract track data from source MKV files
  - `Build-SampleMkvFromSrs` - Reconstruct sample MKV from SRS and track data
  - `Restore-SrsVideo` - High-level sample reconstruction entry point
- Modern build system using PowerShellBuild + psake + PSDepend
- Cross-platform CI/CD with GitHub Actions (Windows, Linux, macOS)
- Comprehensive Pester 5.x test infrastructure
- VSCode integration with build tasks and PowerShell formatting
