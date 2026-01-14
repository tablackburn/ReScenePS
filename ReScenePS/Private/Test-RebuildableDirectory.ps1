function Test-RebuildableDirectory {
    <#
    .SYNOPSIS
    Tests if a directory contains rebuildable source files (video files or SRR).

    .DESCRIPTION
    Checks if a directory contains files that can be used for scene release reconstruction:
    - Existing .srr files (already have metadata for rebuild)
    - Video files (.mkv, .avi, .mp4, .m2ts) that are >= 100MB

    The 100MB threshold filters out sample files, which are typically 50MB or less for
    standard scene samples. This prevents the function from incorrectly identifying
    sample-only directories as rebuildable releases.

    .PARAMETER Path
    Directory to check for rebuildable content.

    .OUTPUTS
    [bool] $true if directory contains rebuildable files, $false otherwise.

    .EXAMPLE
    Test-RebuildableDirectory -Path "D:\Downloads\Movie.2024.1080p.BluRay-GROUP"
    Returns $true if the directory contains a large video file or .srr file.

    .EXAMPLE
    Test-RebuildableDirectory -Path "D:\Downloads\Movie.2024.1080p.BluRay-GROUP\Sample"
    Returns $false because sample directories typically only contain small sample files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path -PathType Container)) {
        return $false
    }

    # Check for existing SRR file (already has metadata for rebuild)
    $srrFiles = Get-ChildItem -Path $Path -Filter "*.srr" -File -ErrorAction SilentlyContinue
    if ($srrFiles.Count -gt 0) {
        return $true
    }

    # Get video files directly in this directory (not recursive - we want to find release dirs, not drill down)
    # Use wildcard path with -Include for filesystem-level filtering (more efficient than Where-Object)
    # Note: -Include requires wildcard in path to work without -Recurse. Using Join-Path with '*'
    # ensures we only get direct children while benefiting from filesystem-level extension filtering.
    # This approach is case-insensitive on Windows and prevents accidental recursion.
    try {
        $videoFiles = Get-ChildItem -Path (Join-Path $Path '*') -File -Include '*.mkv', '*.avi', '*.mp4', '*.m2ts' -ErrorAction Stop
    }
    catch {
        # Handle access denied or other errors gracefully
        Write-Verbose "Could not enumerate files in '$Path': $($_.Exception.Message)"
        return $false
    }

    foreach ($file in $videoFiles) {
        # Skip small files - 100MB threshold filters out samples
        # Scene samples are typically 50MB or less; main video files are usually several GB
        if ($file.Length -ge 100MB) {
            return $true
        }
    }

    return $false
}
