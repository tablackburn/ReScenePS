# ReScenePS

[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/ReScenePS)](https://www.powershellgallery.com/packages/ReScenePS/)
[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/ReScenePS)](https://www.powershellgallery.com/packages/ReScenePS/)
[![CI](https://img.shields.io/github/actions/workflow/status/tablackburn/ReScenePS/CI.yaml?branch=main)](https://github.com/tablackburn/ReScenePS/actions/workflows/CI.yaml)
![Platform](https://img.shields.io/powershellgallery/p/ReScenePS)
[![AI Assisted](https://img.shields.io/badge/AI-Assisted-blue)](https://claude.ai)
[![License](https://img.shields.io/github/license/tablackburn/ReScenePS)](LICENSE)

PowerShell module for reconstructing RAR archives from SRR files and MKV/AVI samples from SRS files.

## Installation

### From PowerShell Gallery (Recommended)
```powershell
Install-Module -Name ReScenePS
```

### From Source
```powershell
git clone https://github.com/tablackburn/ReScenePS.git
cd ReScenePS
./build.ps1 -Bootstrap
./build.ps1 -Task Build
Import-Module ./Output/ReScenePS/ReScenePS.psd1
```

## Requirements

- PowerShell 7.0+
- CRC Module: `Install-Module -Name CRC`

## Quick Start

### Reconstruct RAR Archives from SRR

```powershell
# Simple usage - auto-detects SRR and source files in current directory
Invoke-SrrRestore

# Explicit paths
Invoke-SrrRestore -SrrFile "release.srr" -SourcePath "./sources" -OutputPath "./output"

# Keep source files after reconstruction
Invoke-SrrRestore -KeepSrr -KeepSources
```

### Reconstruct Video Sample from SRS

```powershell
# MKV sample reconstruction
Restore-SrsVideo -SrsFilePath "sample.srs" -SourcePath "main.mkv" -OutputPath "sample.mkv"

# AVI sample reconstruction (auto-detected from SRS format)
Restore-SrsVideo -SrsFilePath "sample.srs" -SourcePath "main.avi" -OutputPath "sample.avi"
```

### Inspect SRR/SRS Files

```powershell
# Display SRR structure and metadata
Show-SrrInfo -SrrFile "release.srr"

# Get SRS metadata
ConvertFrom-SrsFileMetadata -FilePath "sample.srs"
```

## Functions

### SRR (RAR Reconstruction)

| Function | Description |
|----------|-------------|
| `Show-SrrInfo` | Display SRR file metadata and block structure |
| `Get-SrrBlock` | Parse SRR file and return block objects |
| `Invoke-SrrReconstruct` | Reconstruct RAR files from SRR and source files |
| `Invoke-SrrRestore` | Complete end-to-end restoration with validation and cleanup |

### SRS (Video Sample Reconstruction)

| Function | Description |
|----------|-------------|
| `Restore-SrsVideo` | High-level sample reconstruction (MKV/AVI auto-detected) |
| `ConvertFrom-SrsFileMetadata` | Parse SRS file and return metadata object |
| `Build-SampleMkvFromSrs` | Reconstruct MKV sample from SRS and track data |
| `Build-SampleAviFromSrs` | Reconstruct AVI sample from SRS and source data |
| `Export-SampleTrackData` | Extract track data from source video |

## Development

### Build System

This project uses PowerShellBuild + psake for builds:

```powershell
# Install build dependencies
./build.ps1 -Bootstrap

# Run tests
./build.ps1 -Task Test

# Build module
./build.ps1 -Task Build

# Run PSScriptAnalyzer
./build.ps1 -Task Analyze

# List all available tasks
./build.ps1 -Help
```

### VSCode Integration

Open the project in VSCode and use:
- `Ctrl+Shift+B` - Build module
- `Ctrl+Shift+T` - Run tests

### Project Structure

```
ReScenePS/
├── ReScenePS/
│   ├── Classes/          # Block type definitions
│   ├── Private/          # Internal helper functions
│   ├── Public/           # Exported cmdlets
│   ├── ReScenePS.psd1    # Module manifest
│   └── ReScenePS.psm1    # Module loader
├── tests/
│   ├── Manifest.tests.ps1
│   ├── Help.tests.ps1
│   └── Meta.tests.ps1
├── .github/workflows/    # CI/CD
├── .vscode/              # VSCode configuration
├── build.ps1             # Build entry point
├── build.psake.ps1       # Build tasks
├── build.depend.psd1     # Build dependencies
└── requirements.psd1     # Runtime dependencies
```

### Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed documentation on:

- Binary file formats (SRR, SRS, RAR, EBML)
- Module internals and class structure
- Reconstruction algorithms
- Test infrastructure and Plex integration

## How It Works

### SRR Reconstruction

SRR files contain RAR metadata without the actual file data:
1. Parse SRR to extract block structure (headers, file entries)
2. Locate source files matching the expected names and sizes
3. Reconstruct RAR volumes by combining headers from SRR with data from source files
4. Validate CRCs against embedded SFV checksums

### SRS Reconstruction

SRS files contain MKV structure without frame data:
1. Parse SRS to get track metadata and byte offsets where data matches
2. Extract matching track data from the full source MKV
3. Rebuild sample by injecting extracted data into the SRS structure


## Acknowledgments

This project was developed with assistance from [Claude](https://claude.ai) by Anthropic.

## License

MIT
