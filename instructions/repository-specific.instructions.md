# Repository-Specific Instructions

Instructions specific to the ReScenePS repository.

## Project Overview

ReScenePS is a PowerShell module for reconstructing RAR archives from SRR (Scene Release Reconstruct) files and video samples (MKV and AVI) from SRS (Sample ReScene) files.

## Build Commands

```powershell
# Bootstrap (install dependencies)
pwsh -File ./build.ps1 -Bootstrap

# Build and test
pwsh -File ./build.ps1 -Task Test

# Run specific test file
pwsh -Command "Set-BuildEnvironment -Force; Invoke-Pester -Path tests/Unit/Get-EbmlUInt.tests.ps1"

# Import module from source
pwsh -Command "Import-Module ./ReScenePS/ReScenePS.psd1 -Force"
```

## Module Structure

- `ReScenePS/` - Module source
  - `Classes/` - Block type definitions and BlockReader class
  - `Public/` - Exported cmdlets (must be in FunctionsToExport)
  - `Private/` - Internal helper functions
- `Output/` - Built module artifacts (created by build process)
- `tests/` - Pester tests
  - `Unit/` - Unit tests using InModuleScope
  - `Functional.tests.ps1` - End-to-end tests with real SRR/SRS files

## Key Public Commands

- `Get-SrrBlock` - Parse SRR file and return block objects
- `Show-SrrInfo` - Display formatted SRR file information
- `Invoke-SrrReconstruct` - Reconstruct RAR archives from SRR + source files
- `Invoke-SrrRestore` - Complete workflow: extract, reconstruct, validate, cleanup
- `ConvertFrom-SrsFileMetadata` - Parse SRS file metadata
- `Restore-SrsVideo` - Reconstruct video samples (auto-detects MKV/AVI)

## Testing

Tests run against built module in `Output/ReScenePS/<version>/`. The build sets `BH*` environment variables via `Set-BuildEnvironment`.

### Test Configuration

Copy `tests/TestConfig.Example.psd1` to `tests/TestConfig.psd1` for functional tests. This file is gitignored.

### Public Domain Test Releases

For copyright-free testing, use these public domain films (scene releases available on srrdb.com):

| Film | Year | Example Release |
|------|------|-----------------|
| The Kid | 1921 | `The.Kid.1921.1080p.BluRay.x264-AVCHD` |
| Sherlock Jr. | 1924 | `Sherlock.Jr.1924.1080p.BluRay.x264-PSYCHD` |
| Battleship Potemkin | 1925 | `Battleship.Potemkin.1925.1080p.BluRay.x264-CiNEFiLE` |
| Metropolis | 1927 | `Metropolis.1927.1080p.BluRay.x264-AVCHD` |
| Night of the Living Dead | 1968 | `Night.Of.The.Living.Dead.1968.1080p.Bluray.x264-hV` |

## Versioning

- `ModuleVersion` in `ReScenePS.psd1` must match latest version in `CHANGELOG.md`
- Update both files together when releasing

## Additional Context

See `ARCHITECTURE.md` for detailed architecture documentation including:

- Binary file format specifications (SRR, SRS, RAR, EBML)
- Reconstruction process details
- Complete function reference
- Plex data source testing setup
