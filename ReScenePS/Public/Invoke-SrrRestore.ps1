function Invoke-SrrRestore {
    <#
    .SYNOPSIS
        Complete SRR restoration - extracts stored files, reconstructs archives, validates, and cleans up.

    .DESCRIPTION
        This is the main entry point for SRR restoration. It performs:
        - Auto-detection of SRR file if not specified
        - Auto-detection of source files
        - Extraction of all stored files (NFO, SFV, etc.)
        - Reconstruction of RAR volumes
        - CRC validation against SFV
        - Cleanup of temporary and source files (with confirmation)

    .PARAMETER SrrFile
        Path to SRR file. If not specified, searches current directory for a single .srr file.

    .PARAMETER SourcePath
        Directory containing source files. Defaults to current directory.

    .PARAMETER OutputPath
        Directory for reconstructed release. Defaults to current directory.

    .PARAMETER KeepSrr
        If specified, do not delete SRR file after successful restoration.

    .PARAMETER KeepSources
        If specified, do not delete source files (e.g., .mkv) after successful restoration.

    .EXAMPLE
        Invoke-SrrRestore

        Auto-detects the SRR file and source files in the current directory and performs a complete restoration.

    .EXAMPLE
        Invoke-SrrRestore -SrrFile "Release.srr" -KeepSrr

        Specifies the SRR file explicitly and preserves it after successful restoration.
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter()]
        [string]$SrrFile = "",

        [Parameter()]
        [string]$SourcePath = ".",

        [Parameter()]
        [string]$OutputPath = ".",

        [Parameter()]
        [switch]$KeepSrr,

        [Parameter()]
        [switch]$KeepSources
    )

    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Cyan
    Write-Host "              SRR Release Restoration" -ForegroundColor Cyan
    Write-Host "===========================================================" -ForegroundColor Cyan
    Write-Host ""

    # Track files we create for potential cleanup
    $script:createdFiles = @()
    $script:validationPassed = $false

    try {
        # Step 1: Auto-detect or validate SRR file
        Write-Host "[1/6] Locating SRR file..." -ForegroundColor Yellow

        if ([string]::IsNullOrWhiteSpace($SrrFile)) {
            # Auto-detect SRR in current directory
            $srrFiles = Get-ChildItem -Path $SourcePath -Filter "*.srr" -File -ErrorAction SilentlyContinue

            if ($srrFiles.Count -eq 0) {
                throw "No SRR file found in current directory. Specify -SrrFile parameter or place .srr file in current directory."
            }
            elseif ($srrFiles.Count -gt 1) {
                Write-Host "  Multiple SRR files found:" -ForegroundColor Red
                foreach ($f in $srrFiles) {
                    Write-Host "    - $($f.Name)" -ForegroundColor Red
                }
                throw "Multiple SRR files found. Please specify which SRR to process using -SrrFile parameter."
            }
            else {
                $SrrFile = $srrFiles[0].FullName
                Write-Host "  [OK] Auto-detected: $($srrFiles[0].Name)" -ForegroundColor Green
            }
        }
        else {
            # Resolve provided path
            $SrrFile = (Resolve-Path -Path $SrrFile -ErrorAction Stop).Path
            Write-Host "  [OK] Using: $(Split-Path $SrrFile -Leaf)" -ForegroundColor Green
        }

        # Resolve other paths
        $SourcePath = (Resolve-Path -Path $SourcePath -ErrorAction Stop).Path

        # Normalize and ensure OutputPath exists (respect -WhatIf)
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        if (-not [System.IO.Directory]::Exists($OutputPath)) {
            if ($PSCmdlet.ShouldProcess($OutputPath, "Create directory")) {
                [System.IO.Directory]::CreateDirectory($OutputPath) | Out-Null
            }
        }

        Write-Host ""

        # Step 2: Parse SRR and discover source files
        Write-Host "[2/6] Parsing SRR and discovering source files..." -ForegroundColor Yellow

        $reader = [BlockReader]::new($SrrFile)
        $blocks = $reader.ReadAllBlocks()
        $reader.Close()

        Write-Host "  Parsed $($blocks.Count) blocks" -ForegroundColor Gray

        # Find all unique source files referenced in RAR packed file blocks
        $sourceFiles = @{}
        $packedBlocks = $blocks | Where-Object { $_ -is [RarPackedFileBlock] }

        foreach ($block in $packedBlocks) {
            if (-not $sourceFiles.ContainsKey($block.FileName)) {
                $sourceFiles[$block.FileName] = @{
                    Name = $block.FileName
                    Size = $block.FullUnpackedSize
                    Path = $null
                }
            }
        }

        if ($sourceFiles.Count -eq 0) {
            throw "No source files found in SRR metadata"
        }

        Write-Host "  Required source files: $($sourceFiles.Count)" -ForegroundColor Gray

        # Auto-detect each source file
        $allFound = $true
        foreach ($fileName in $sourceFiles.Keys) {
            $fileInfo = $sourceFiles[$fileName]
            $foundPath = Find-SourceFile -FileName $fileName -SearchPath $SourcePath -ExpectedSize $fileInfo.Size

            if ($foundPath) {
                $sourceFiles[$fileName].Path = $foundPath
                Write-Host "  [OK] Found: $fileName" -ForegroundColor Green
            }
            else {
                $sizeGB = [Math]::Round($fileInfo.Size / 1GB, 2)
                Write-Host ("  [X] Missing: {0} ({1} GB)" -f $fileName, $sizeGB) -ForegroundColor Red
                $allFound = $false
            }
        }

        if (-not $allFound) {
            throw "Required source file(s) not found. Searched in: $SourcePath"
        }

        Write-Host ""

        # Step 3: Extract all stored files
        Write-Host "[3/6] Extracting stored files..." -ForegroundColor Yellow

        $storedBlocks = $blocks | Where-Object { $_ -is [SrrStoredFileBlock] }

        if ($storedBlocks.Count -eq 0) {
            Write-Host "  No stored files found in SRR" -ForegroundColor Gray
        }
        else {
            $fs = [System.IO.File]::OpenRead($SrrFile)
            try {
                $br = [System.IO.BinaryReader]::new($fs)
                $currentPos = 0

                foreach ($block in $blocks) {
                    $blockSize = $block.HeadSize + $block.AddSize

                    if ($block -is [SrrStoredFileBlock]) {
                        # Skip SRR container itself if present in stored list
                        if ($block.FileName -match '\.srr$') {
                            $currentPos += $blockSize
                            continue
                        }

                        # Guard against rooted paths and preserve relative names
                        $relativePath = $block.FileName.TrimStart('\', '/')
                        $targetPath = Join-Path $OutputPath $relativePath
                        $targetDir = Split-Path $targetPath -Parent

                        if ($targetDir -and -not (Test-Path $targetDir)) {
                            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                        }

                        $dataStart = $currentPos + $block.HeadSize
                        $fs.Seek($dataStart, [System.IO.SeekOrigin]::Begin) | Out-Null

                        $fileData = $br.ReadBytes([int]$block.FileSize)
                        if ($PSCmdlet.ShouldProcess($targetPath, "Write stored file")) {
                            [System.IO.File]::WriteAllBytes($targetPath, $fileData)
                            $script:createdFiles += $targetPath
                            if ($targetPath.ToLower().EndsWith('.srs')) {
                                $info = Get-SrsInfo -FilePath $targetPath
                                Write-Host ("  [OK] Extracted SRS: {0} [{1}]" -f $block.FileName, $info.Type) -ForegroundColor Green
                            }
                            else {
                                Write-Host "  [OK] Extracted: $($block.FileName)" -ForegroundColor Green
                            }
                        }
                    }

                    $currentPos += $blockSize
                }
            }
            finally {
                $br.Dispose()
                $fs.Close()
            }
        }

        Write-Host ""

        # Step 3.5: Reconstruct video samples from SRS (if present and not under -WhatIf)
        $srsFiles = $storedBlocks | Where-Object { $_.FileName -match '\.srs$' }
        if ($srsFiles.Count -gt 0 -and -not $WhatIfPreference) {
            Write-Host "[3b/6] Reconstructing video samples from SRS..." -ForegroundColor Yellow

            foreach ($srsBlock in $srsFiles) {
                $srsPath = Join-Path $OutputPath $srsBlock.FileName

                if (Test-Path $srsPath) {
                    # Determine output sample filename (replace .srs with .mkv or .mp4)
                    $sampleBaseName = $srsPath -replace '\.(srs)$', '.mkv'

                    # Find source file for this sample (usually in source metadata or named similarly)
                    # For now, use the primary source file
                    $sourcePath = $sourceFiles.Values | Select-Object -First 1 | Select-Object -ExpandProperty Path

                    if ($sourcePath -and (Test-Path $sourcePath)) {
                        $reconstructed = Restore-SrsVideo -SrsFilePath $srsPath -SourceMkvPath $sourcePath -OutputMkvPath $sampleBaseName

                        if ($reconstructed) {
                            $script:createdFiles += $sampleBaseName
                        }
                    }
                    else {
                        Write-Warning "  Source file not available for SRS reconstruction"
                    }
                }
            }

            Write-Host ""
        }

        # Step 4: Reconstruct RAR volumes
        Write-Host "[4/6] Reconstructing RAR volumes..." -ForegroundColor Yellow

        # Group blocks by RAR volume
        $rarVolumes = @{}
        $currentVolume = $null

        foreach ($block in $blocks) {
            if ($block -is [SrrRarFileBlock]) {
                $currentVolume = $block.FileName
                $rarVolumes[$currentVolume] = @{
                    RarFileBlock = $block
                    Blocks = [System.Collections.Generic.List[Object]]::new()
                }
            }
            elseif ($currentVolume -and (
                $block -is [RarMarkerBlock] -or
                $block -is [RarVolumeHeaderBlock] -or
                $block -is [RarPackedFileBlock] -or
                $block -is [RarEndArchiveBlock]
            )) {
                $rarVolumes[$currentVolume].Blocks.Add($block)
            }
        }

        Write-Host "  RAR volumes to reconstruct: $($rarVolumes.Count)" -ForegroundColor Gray

        # Sort volumes: .rar first, then .r00, .r01, etc
        $sortedVolumes = $rarVolumes.Keys | Sort-Object {
            if ($_ -match '\.rar$') { 0 }
            elseif ($_ -match '\.r(\d+)$') { [int]$matches[1] + 1 }
            else { 999 }
        }

        # If -WhatIf: preview sources and target output files without writing
        if ($WhatIfPreference) {
            Write-Host "  Preview sources:" -ForegroundColor Gray
            foreach ($sf in $sourceFiles.Values) {
                Write-Host ("    - {0} <= {1}" -f $sf.Name, $sf.Path) -ForegroundColor Gray
            }
            Write-Host "  Preview outputs:" -ForegroundColor Gray
            foreach ($v in $sortedVolumes) {
                $previewPath = Join-Path $OutputPath $v
                Write-Host ("    - {0}" -f $previewPath) -ForegroundColor Gray
            }
        }

        $sourceFileHandle = $null
        $currentSourceFile = $null
        $sourceFileOffset = [long]0

        try {
            foreach ($volumeName in $sortedVolumes) {
                $volumeData = $rarVolumes[$volumeName]
                $outputFile = Join-Path $OutputPath $volumeName

                $proceed = $PSCmdlet.ShouldProcess($outputFile, "Create RAR volume")
                if (-not $proceed) { continue }

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
                            # Open source file if needed
                            if ($currentSourceFile -ne $block.FileName) {
                                if ($sourceFileHandle) {
                                    $sourceFileHandle.Close()
                                    $sourceFileHandle = $null
                                }

                                $currentSourceFile = $block.FileName
                                $sourceFileOffset = 0

                                # Get source path from our discovered list
                                $sourcePath = $sourceFiles[$block.FileName].Path

                                if (-not $sourcePath) {
                                    throw "Source file not found: $($block.FileName)"
                                }

                                $sourceFileHandle = [System.IO.File]::OpenRead($sourcePath)
                            }

                            # Write file header
                            $blockBytes = $block.GetBlockBytes()
                            $rarStream.Write($blockBytes, 0, $blockBytes.Length)

                            # Copy chunk data from source
                            $chunkSize = $block.FullPackedSize
                            $buffer = New-Object byte[] ([Math]::Min($chunkSize, 1MB))
                            $remaining = $chunkSize

                            $sourceFileHandle.Seek($sourceFileOffset, [System.IO.SeekOrigin]::Begin) | Out-Null

                            while ($remaining -gt 0) {
                                $toRead = [Math]::Min($remaining, $buffer.Length)
                                $bytesRead = $sourceFileHandle.Read($buffer, 0, $toRead)

                                if ($bytesRead -eq 0) {
                                    throw "Unexpected end of source file"
                                }

                                $rarStream.Write($buffer, 0, $bytesRead)
                                $remaining -= $bytesRead
                            }

                            $sourceFileOffset += $chunkSize
                        }
                        elseif ($block -is [RarEndArchiveBlock]) {
                            $blockBytes = $block.GetBlockBytes()
                            $rarStream.Write($blockBytes, 0, $blockBytes.Length)
                        }
                    }
                }
                finally {
                    $rarStream.Close()
                }

                $script:createdFiles += $outputFile
                $fileSize = (Get-Item $outputFile).Length
                Write-Host "  [OK] Created: $volumeName ($fileSize bytes)" -ForegroundColor Green
            }
        }
        finally {
            if ($sourceFileHandle) {
                $sourceFileHandle.Close()
            }
        }

        Write-Host ""

        # Step 5: Validate reconstructed archives
        Write-Host "[5/6] Validating reconstructed archives..." -ForegroundColor Yellow

        # Respect -WhatIf: skip validation to avoid temp file writes, but allow cleanup preview
        if ($WhatIfPreference) {
            Write-Host "  Skipping validation under -WhatIf (no temp files written)" -ForegroundColor Gray
            $script:validationPassed = $true
        }
        else {
            # Extract and parse SFV
            $tempSfv = [System.IO.Path]::GetTempFileName() + ".sfv"
            $sfvFound = $false

            try {
                # Try to extract SFV from SRR
                $storedSfv = $storedBlocks | Where-Object { $_.FileName -match '\.sfv$' } | Select-Object -First 1

                if ($storedSfv) {
                    $fs = [System.IO.File]::OpenRead($SrrFile)
                    try {
                        $br = [System.IO.BinaryReader]::new($fs)
                        $currentPos = 0

                        foreach ($block in $blocks) {
                            $blockSize = $block.HeadSize + $block.AddSize

                            if ($block -eq $storedSfv) {
                                $dataStart = $currentPos + $block.HeadSize
                                $fs.Seek($dataStart, [System.IO.SeekOrigin]::Begin) | Out-Null
                                $fileData = $br.ReadBytes([int]$block.FileSize)
                                [System.IO.File]::WriteAllBytes($tempSfv, $fileData)
                                $sfvFound = $true
                                break
                            }

                            $currentPos += $blockSize
                        }
                    }
                    finally {
                        $br.Dispose()
                        $fs.Close()
                    }
                }

                if (-not $sfvFound) {
                    Write-Warning "  SFV file not found in SRR, skipping CRC validation"
                }
                else {
                    # Parse SFV
                    $sfvData = ConvertFrom-SfvFile -FilePath $tempSfv
                    Write-Host "  SFV entries: $($sfvData.Count)" -ForegroundColor Gray

                    # Validate each RAR file
                    $allValid = $true
                    $validCount = 0
                    $failCount = 0

                    foreach ($rarFile in $sfvData.Keys | Sort-Object) {
                        $rarPath = Join-Path $OutputPath $rarFile

                        if (-not (Test-Path $rarPath)) {
                            Write-Host "  [X] $rarFile - NOT FOUND" -ForegroundColor Red
                            $allValid = $false
                            $failCount++
                            continue
                        }

                        $expectedCrc = $sfvData[$rarFile]
                        $actualCrc = Get-Crc32 -FilePath $rarPath

                        if ($actualCrc -eq $expectedCrc) {
                            Write-Host "  [OK] $rarFile" -ForegroundColor Green
                            $validCount++
                        }
                        else {
                            Write-Host ("  [X] $rarFile - CRC mismatch: Expected 0x{0:X8}, got 0x{1:X8}" -f $expectedCrc, $actualCrc) -ForegroundColor Red
                            $allValid = $false
                            $failCount++
                        }
                    }

                    if (-not $allValid) {
                        throw "Validation failed! $validCount valid, $failCount failed. Files not cleaned up for inspection."
                    }

                    $script:validationPassed = $true
                    Write-Host "  All $validCount RAR files validated successfully!" -ForegroundColor Green
                }
            }
            finally {
                Remove-Item $tempSfv -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Host ""

        # Step 6: Cleanup (only if validation passed)
            if ($script:validationPassed) {
            Write-Host "[6/6] Cleanup..." -ForegroundColor Yellow

            # SRR deletion via ShouldProcess/-Confirm
            if (-not $KeepSrr) {
                if ($PSCmdlet.ShouldProcess($SrrFile, "Delete SRR")) {
                    if (Test-Path $SrrFile) {
                        Remove-Item $SrrFile -Force -ErrorAction SilentlyContinue
                        Write-Host "  [OK] Deleted SRR: $(Split-Path $SrrFile -Leaf)" -ForegroundColor Gray
                    }
                }
                else {
                    Write-Host "  Keeping SRR (confirmation declined)" -ForegroundColor Gray
                }
            }
            else {
                Write-Host "  Keeping SRR (KeepSrr specified)" -ForegroundColor Gray
            }

            # Source deletions via ShouldProcess/-Confirm
            if (-not $KeepSources) {
                foreach ($fileName in $sourceFiles.Keys) {
                    $srcPath = $sourceFiles[$fileName].Path
                    if ($PSCmdlet.ShouldProcess($srcPath, "Delete source")) {
                        if (Test-Path $srcPath) {
                            Remove-Item $srcPath -Force -ErrorAction SilentlyContinue
                            Write-Host "  [OK] Deleted source: $(Split-Path $srcPath -Leaf)" -ForegroundColor Gray
                        }
                    }
                }
            }
            else {
                Write-Host "  Keeping source files (KeepSources specified)" -ForegroundColor Gray
            }

            # SRS deletions via ShouldProcess/-Confirm
            $srsBlocks = $storedBlocks | Where-Object { $_.FileName -match '\.srs$' }
            foreach ($srsBlock in $srsBlocks) {
                $srsPath = Join-Path $OutputPath $srsBlock.FileName
                if (Test-Path $srsPath) {
                    if ($PSCmdlet.ShouldProcess($srsPath, "Delete SRS")) {
                        Remove-Item $srsPath -Force -ErrorAction SilentlyContinue
                        Write-Host "  [OK] Deleted SRS: $(Split-Path $srsPath -Leaf)" -ForegroundColor Gray
                    }
                }
            }

            Write-Host ""
            Write-Host "===========================================================" -ForegroundColor Green
            Write-Host "         Restoration Complete & Validated!" -ForegroundColor Green
            Write-Host "===========================================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "Output directory: $OutputPath" -ForegroundColor Cyan
            Write-Host "  - RAR volumes: $($rarVolumes.Count)" -ForegroundColor Gray
            Write-Host "  - Stored files: $($storedBlocks.Count)" -ForegroundColor Gray
            Write-Host ""
        }
        else {
            Write-Host ""
            Write-Host "===========================================================" -ForegroundColor Yellow
            Write-Host "     Restoration Complete (Validation Skipped)" -ForegroundColor Yellow
            Write-Host "===========================================================" -ForegroundColor Yellow
            Write-Host ""
            Write-Warning "Validation was skipped or failed. No cleanup performed."
            Write-Host "Output directory: $OutputPath" -ForegroundColor Cyan
            Write-Host ""
        }

    }
    catch {
        Write-Host ""
        Write-Host "[X] Restoration failed: $_" -ForegroundColor Red
        Write-Host ""
        throw
    }
}
