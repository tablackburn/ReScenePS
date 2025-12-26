# ReScene PowerShell Module

PowerShell implementation for reconstructing RAR archives from SRR files and MKV samples from SRS files.

## Quick Start

```powershell
# Import the module
Import-Module .\ReScene.psm1

# Reconstruct RAR archive from SRR
Invoke-SrrRestore -SrrPath "archive.srr" -OutputPath ".\output"

# Reconstruct MKV sample from SRS
Restore-SrsVideo -SrsPath "sample.srs" -MainMkvPath "main.mkv" -OutputPath "sample.mkv"
```

## Requirements

- PowerShell 7+
- CRC Module: `Install-Module -Name CRC`

## Functions

### SRR (RAR Reconstruction)

| Function | Description |
|----------|-------------|
| `Show-SrrInfo` | Display SRR file metadata and structure |
| `Invoke-SrrReconstruct` | Reconstruct RAR files from SRR |
| `Invoke-SrrRestore` | Complete end-to-end restoration workflow |
| `Test-ReconstructedRar` | Validate reconstructed archives |

### SRS (MKV Reconstruction)

| Function | Description |
|----------|-------------|
| `Get-SrsInfo` | Display SRS file metadata |
| `Export-MkvTrackData` | Extract track data from source MKV |
| `Build-SampleMkvFromSrs` | Combine SRS structure with extracted data |
| `Restore-SrsVideo` | High-level reconstruction entry point |

## License

MIT
