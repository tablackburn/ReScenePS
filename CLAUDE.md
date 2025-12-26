# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ReScenePS is a PowerShell module for reconstructing RAR archives from SRR (Scene Release Reconstruct) files and MKV video samples from SRS (Sample ReScene) files. It provides a complete toolchain for scene release reconstruction.

## Build and Test Commands

### Running PowerShell Commands (Important for Claude Code)

When executing PowerShell scripts from a bash/sh shell environment (which Claude Code uses by default), always invoke `pwsh` explicitly:

```bash
# Correct - explicitly invoke PowerShell
pwsh -File ./build.ps1 -Task Test
pwsh -Command "Import-Module ./ReScenePS/ReScenePS.psd1 -Force"

# Incorrect - will fail with syntax errors in bash
./build.ps1 -Task Test  # Bash interprets PowerShell syntax as shell script
```

### Initial Setup
```powershell
pwsh -File ./build.ps1 -Bootstrap
```
This installs all build dependencies (PSDepend, Pester 5, psake, BuildHelpers, PowerShellBuild, PSScriptAnalyzer) to the current user scope.

### Primary Development Loop
```powershell
pwsh -File ./build.ps1 -Task Test
```
Default task that builds the module and runs all tests (Manifest, Help, Meta tests).

### List Available Tasks
```powershell
pwsh -File ./build.ps1 -Help
```

### Run Single Test File
```powershell
# First set build environment, then run specific test
pwsh -Command "Set-BuildEnvironment -Force; Invoke-Pester -Path tests/Help.tests.ps1"
```

### Import Module Locally
```powershell
# Import from built output
pwsh -Command "Import-Module ./Output/ReScenePS/<version>/ReScenePS.psd1 -Force"

# Or import from source during iteration
pwsh -Command "Import-Module ./ReScenePS/ReScenePS.psd1 -Force"
```

## Module Architecture

### File Structure Pattern
- **ReScenePS/ReScenePS.psm1** - Dot-sources all .ps1 files from `Classes/`, `Public/`, and `Private/` directories, exports only public functions via `Export-ModuleMember -Function $public.Basename`
- **Classes/** - Block type definitions (SrrBlock, RarPackedFileBlock, etc.) and BlockReader class
- **Public/** - Exported cmdlets available to users (must be in `FunctionsToExport` in manifest)
- **Private/** - Internal helper functions (not exported)
- **Output/** - Built module artifacts (created by build process, loads from here during tests)

### Core Classes (Classes/)

**BlockClasses.ps1** - Contains all block type definitions:
- `BlockType` enum - SRR/RAR block type identifiers
- `SrrBlock` - Base class for all blocks
- `SrrHeaderBlock`, `SrrStoredFileBlock`, `SrrRarFileBlock` - SRR-specific blocks
- `RarMarkerBlock`, `RarVolumeHeaderBlock`, `RarPackedFileBlock`, `RarEndArchiveBlock` - RAR blocks
- `BlockReader` - Binary reader for parsing SRR files

### Private Helper Functions

**EBML Parsing** (for MKV/SRS files):
- `Get-EbmlUIntLength`, `Get-EbmlUInt`, `Get-EbmlElementID` - EBML variable-length integer parsing
- `Read-EbmlUIntStream`, `Get-EbmlElementFromBuffer` - Stream-based EBML reading
- `ConvertTo-EbmlElementString` - Debug formatting

**SRS Parsing**:
- `ConvertFrom-SrsFile`, `ConvertFrom-SrsFileData`, `ConvertFrom-SrsTrackData` - SRS metadata extraction
- `Get-SrsInfo` - High-level SRS file info retrieval

**Utilities**:
- `Find-SourceFile` - Locate source files by name/size
- `Export-StoredFile` - Extract stored files from SRR
- `Export-MkvTrackData` - Extract track data from MKV files
- `ConvertFrom-SfvFile` - Parse SFV checksum files
- `Test-ReconstructedRar` - Validate RAR CRCs against SFV

### Public Commands

**SRR Functions**:
- `Get-SrrBlock` - Parse SRR file and return all block objects
- `Show-SrrInfo` - Display formatted SRR file information
- `Invoke-SrrReconstruct` - Reconstruct RAR archives from SRR + source files
- `Invoke-SrrRestore` - Complete workflow: extract, reconstruct, validate, cleanup

**SRS Functions**:
- `ConvertFrom-SrsFileMetadata` - Parse SRS file and return metadata object
- `Export-SampleTrackData` - Extract track data from main MKV for sample reconstruction
- `Build-SampleMkvFromSrs` - Combine SRS structure with extracted track data
- `Restore-SrsVideo` - High-level sample reconstruction entry point

## Testing Requirements

Tests run against built module in `Output/<ModuleName>/<Version>/` directory. The build sets `BH*` environment variables via `Set-BuildEnvironment` that tests rely on.

### Manifest.tests.ps1
- Validates manifest fields populated (ModuleVersion, Author, Copyright, Description)
- Ensures `ModuleVersion` matches `CHANGELOG.md` latest entry
- Verifies RootModule reference and required modules

### Help.tests.ps1
- Every public function requires non-auto-generated comment-based help
- Must include: Synopsis, Description, Parameter descriptions, Examples
- Parameter help must match actual parameters

### Meta.tests.ps1
- All files must be UTF-8 encoding (no UTF-16)
- No tab characters allowed (use 4 spaces for indentation)

## Binary File Formats

### SRR File Structure
SRR files contain:
1. SRR Header Block (magic: `0x69, 0x69, 0x69`)
2. SRR Stored File Blocks (NFO, SFV, SRS files)
3. SRR RAR File Blocks (one per volume)
4. RAR blocks within each volume section:
   - RAR Marker Block
   - RAR Volume Header Block
   - RAR Packed File Blocks (file headers without data)
   - RAR End Archive Block

### SRS File Structure
SRS files are EBML (like MKV) with:
1. Standard EBML header and Segment
2. ReSample container with metadata (track info, match offsets)
3. Cluster/Block structure matching original sample (headers only, no frame data)

### Reconstruction Process

**RAR Reconstruction**:
1. Parse SRR to extract block metadata
2. For each RAR volume:
   - Write RAR marker (7 bytes)
   - Write volume header from SRR
   - For each packed file block, write header + copy data from source file
   - Write end archive block
3. Validate CRCs against embedded SFV

**Sample MKV Reconstruction**:
1. Parse SRS to get track metadata and match offsets
2. Extract track data from source MKV starting at match offsets
3. Rebuild MKV: copy SRS structure, inject extracted track data into blocks

## Versioning and Changelog

- **ModuleVersion** in `ReScenePS.psd1` must match latest version in `CHANGELOG.md`
- Update both files together when releasing new version
- Changelog follows [Keep a Changelog](http://keepachangelog.com/) format
- Project uses [Semantic Versioning](http://semver.org/)

## Coding Conventions

### File and Encoding Standards
- 4-space indentation (no tabs)
- UTF-8 encoding only (no UTF-16)
- Opening braces on same line
- Newline at end of file
- One function per file (classes can be grouped)

### PowerShell Best Practices
- Use approved verbs (`Get`, `Set`, `Invoke`, `Export`, `ConvertFrom`)
- Full cmdlet names, no aliases
- `[CmdletBinding()]` on every function
- Proper parameter validation attributes
- Comment-based help for all public functions
