function Invoke-SrrReconstruct {
    <#
    .SYNOPSIS
        Reconstruct RAR archive volumes from an SRR file and source files.

    .DESCRIPTION
        Reads SRR metadata and rebuilds the original RAR archive files by:
        1. Parsing SRR for block structure
        2. Writing RAR headers from SRR metadata
        3. Copying file data from source files

    .PARAMETER SrrFile
        Path to the SRR file.

    .PARAMETER SourcePath
        Directory containing source files.

    .PARAMETER OutputPath
        Directory for output RAR files.

    .PARAMETER SkipValidation
        Skip source file size validation.

    .PARAMETER ExtractStoredFiles
        Also extract stored files (NFO, SFV, etc.) to output directory.

    .EXAMPLE
        Invoke-SrrReconstruct -SrrFile "release.srr" -SourcePath "." -OutputPath "./output"

        Reconstructs RAR archives from the SRR file using source files in the current directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SrrFile,

        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [switch]$SkipValidation,

        [Parameter()]
        [switch]$ExtractStoredFiles
    )

    $SrrFile = (Resolve-Path -Path $SrrFile -ErrorAction Stop).Path
    $SourcePath = (Resolve-Path -Path $SourcePath -ErrorAction Stop).Path
    $OutputPath = (Resolve-Path -Path $OutputPath -ErrorAction Stop).Path

    Write-Host "Starting SRR reconstruction..." -ForegroundColor Cyan
    Write-Host "  SRR file: $SrrFile"
    Write-Host "  Source: $SourcePath"
    Write-Host "  Output: $OutputPath"
    Write-Host ""

    $reader = [BlockReader]::new($SrrFile)
    $blocks = $reader.ReadAllBlocks()

    Write-Host "Parsed $($blocks.Count) blocks from SRR file" -ForegroundColor Green

    if ($ExtractStoredFiles) {
        $storedBlocks = $blocks | Where-Object { $_ -is [SrrStoredFileBlock] }
        if ($storedBlocks.Count -gt 0) {
            Write-Host "Extracting stored files..." -ForegroundColor Cyan
            $fs = [System.IO.File]::OpenRead($SrrFile)
            try {
                $br = [System.IO.BinaryReader]::new($fs)
                $currentPos = 0
                foreach ($block in $blocks) {
                    $blockSize = $block.HeadSize + $block.AddSize
                    if ($block -is [SrrStoredFileBlock]) {
                        $relativePath = $block.FileName.TrimStart([char]92, [char]47)
                        $targetPath = Join-Path $OutputPath $relativePath
                        $targetDir = Split-Path $targetPath -Parent
                        if ($targetDir -and -not (Test-Path $targetDir)) {
                            [System.IO.Directory]::CreateDirectory($targetDir) | Out-Null
                        }
                        $dataStart = $currentPos + $block.HeadSize
                        $fs.Seek($dataStart, [System.IO.SeekOrigin]::Begin) | Out-Null
                        $fileData = $br.ReadBytes([int]$block.FileSize)
                        [System.IO.File]::WriteAllBytes($targetPath, $fileData)
                        Write-Host "  Extracted stored file: $($block.FileName) ($($block.FileSize) bytes)" -ForegroundColor Gray
                    }
                    $currentPos += $blockSize
                }
            }
            finally {
                $br.Dispose()
                $fs.Close()
            }
        }
    }

    $rarVolumes = @{}
    $currentVolume = $null
    foreach ($block in $blocks) {
        if ($block -is [SrrRarFileBlock]) {
            $currentVolume = $block.FileName
            $rarVolumes[$currentVolume] = @{ RarFileBlock = $block; Blocks = [System.Collections.Generic.List[Object]]::new() }
        }
        elseif ($currentVolume -and ($block -is [RarMarkerBlock] -or $block -is [RarVolumeHeaderBlock] -or $block -is [RarPackedFileBlock] -or $block -is [RarEndArchiveBlock] -or $block -is [RarNewSubBlock] -or $block -is [RarOldStyleBlock])) {
            $rarVolumes[$currentVolume].Blocks.Add($block)
        }
    }

    Write-Host "Found $($rarVolumes.Count) RAR volumes to reconstruct" -ForegroundColor Green

    if (-not (Test-Path $OutputPath)) { New-Item -Path $OutputPath -ItemType Directory | Out-Null }

    $sourceFile = $null
    $sourceFileHandle = $null
    $sourceFileOffset = [long]0

    try {
        $sortedVolumes = $rarVolumes.Keys | Sort-Object { if ($_ -match '\.rar$') { 0 } elseif ($_ -match '\.r(\d+)$') { [int]$matches[1] + 1 } else { 999 } }
        foreach ($volumeName in $sortedVolumes) {
            $volumeData = $rarVolumes[$volumeName]
            $outputFile = Join-Path $OutputPath $volumeName

            # Ensure parent directory exists (for multi-disc releases like CD1/, CD2/)
            $outputDir = Split-Path $outputFile -Parent
            if ($outputDir -and -not (Test-Path $outputDir)) {
                [System.IO.Directory]::CreateDirectory($outputDir) | Out-Null
            }

            Write-Host "Reconstructing: $volumeName" -ForegroundColor Yellow
            $rarStream = [System.IO.FileStream]::new($outputFile, [System.IO.FileMode]::Create)

            try {
                foreach ($block in $volumeData.Blocks) {
                    if ($block -is [RarMarkerBlock]) {
                        $markerBytes = [byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00)
                        $rarStream.Write($markerBytes, 0, $markerBytes.Length)
                    }
                    elseif ($block -is [RarVolumeHeaderBlock]) {
                        $blockBytes = $block.GetBlockBytes()
                        $rarStream.Write($blockBytes, 0, $blockBytes.Length)
                    }
                    elseif ($block -is [RarPackedFileBlock]) {
                        if ($sourceFile -ne $block.FileName) {
                            if ($sourceFileHandle) { $sourceFileHandle.Close(); $sourceFileHandle = $null }
                            $sourceFile = $block.FileName
                            $sourceFileOffset = 0
                            $sourcePath = Find-SourceFile -FileName $block.FileName -SearchPath $SourcePath -ExpectedSize $block.FullUnpackedSize
                            if (-not $sourcePath) { throw "Source file not found: $($block.FileName)" }
                            Write-Host "  Using source: $sourcePath" -ForegroundColor Gray
                            $sourceFileHandle = [System.IO.File]::OpenRead($sourcePath)
                            if (-not $SkipValidation) {
                                $fileInfo = Get-Item $sourcePath
                                if ($fileInfo.Length -ne $block.FullUnpackedSize) { throw "Source file size mismatch: Expected $($block.FullUnpackedSize) bytes, found $($fileInfo.Length) bytes" }
                            }
                        }
                        $blockBytes = $block.GetBlockBytes()
                        $rarStream.Write($blockBytes, 0, $blockBytes.Length)
                        if ($block.FullPackedSize -gt 0) {
                            $sourceFileHandle.Seek($sourceFileOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
                            $buffer = New-Object byte[] 65536
                            $remaining = [long]$block.FullPackedSize
                            while ($remaining -gt 0) {
                                $toRead = [Math]::Min($remaining, $buffer.Length)
                                $bytesRead = $sourceFileHandle.Read($buffer, 0, $toRead)
                                if ($bytesRead -eq 0) { break }
                                $rarStream.Write($buffer, 0, $bytesRead)
                                $remaining -= $bytesRead
                                $sourceFileOffset += $bytesRead
                            }
                        }
                    }
                    elseif ($block -is [RarNewSubBlock]) {
                        # Write new-style subblock (recovery record, comments, etc.)
                        $blockBytes = $block.GetBlockBytes()
                        $rarStream.Write($blockBytes, 0, $blockBytes.Length)
                        # Note: Subblock data (if any) is not stored in SRR files
                    }
                    elseif ($block -is [RarOldStyleBlock]) {
                        # Write old-style block as-is
                        $blockBytes = $block.GetBlockBytes()
                        $rarStream.Write($blockBytes, 0, $blockBytes.Length)
                    }
                    elseif ($block -is [RarEndArchiveBlock]) {
                        $blockBytes = $block.GetBlockBytes()
                        $rarStream.Write($blockBytes, 0, $blockBytes.Length)
                    }
                }
                Write-Host "  Created: $outputFile ($($rarStream.Length) bytes)" -ForegroundColor Green
            }
            finally {
                $rarStream.Close()
            }
        }
    }
    finally {
        if ($sourceFileHandle) { $sourceFileHandle.Close() }
    }

    Write-Host ""
    Write-Host "Reconstruction complete!" -ForegroundColor Green

    if (-not $SkipValidation) {
        Test-ReconstructedRar -SrrFile $SrrFile -OutputPath $OutputPath
    }
}
