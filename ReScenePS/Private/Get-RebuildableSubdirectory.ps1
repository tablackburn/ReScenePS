function Get-RebuildableSubdirectory {
    <#
    .SYNOPSIS
    Gets subdirectories containing rebuildable source files.

    .DESCRIPTION
    Scans subdirectories up to the specified depth and returns those that contain
    rebuildable content (video files >= 100MB or .srr files).

    .PARAMETER Path
    Root directory to scan for rebuildable subdirectories.

    .PARAMETER Depth
    Maximum depth to search. Uses 1-indexed depth where:
    - Depth 1 = immediate subdirectories only
    - Depth 2 = subdirectories and their children
    - etc.

    Internally converts to Get-ChildItem's 0-indexed -Depth parameter.

    .OUTPUTS
    [string[]] Array of full paths to rebuildable directories.

    .EXAMPLE
    Get-RebuildableSubdirectory -Path "D:\Downloads" -Depth 1
    Returns immediate subdirectories that contain rebuildable files.

    .EXAMPLE
    Get-RebuildableSubdirectory -Path "D:\Downloads" -Depth 2
    Returns subdirectories and their children that contain rebuildable files.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$Depth = 1
    )

    $rebuildableDirs = [System.Collections.Generic.List[string]]::new()

    # Validate path exists before scanning
    if (-not (Test-Path $Path -PathType Container)) {
        Write-Warning "Path does not exist or is not a directory: $Path"
        return $rebuildableDirs.ToArray()
    }

    # Get subdirectories up to specified depth using Get-ChildItem's -Depth parameter.
    # Get-ChildItem -Depth is 0-indexed: -Depth 0 = immediate children only,
    # -Depth 1 = children + grandchildren. Our Depth parameter is 1-indexed:
    # Depth 1 = immediate subdirs, Depth 2 = subdirs + their children.
    # So we subtract 1 to convert: Depth 1 -> -Depth 0, Depth 2 -> -Depth 1, etc.
    $subdirs = @(Get-ChildItem -Path $Path -Directory -Depth ($Depth - 1) -ErrorAction SilentlyContinue)
    $totalSubdirs = $subdirs.Count

    if ($totalSubdirs -gt 0) {
        $checkedCount = 0
        foreach ($subdir in $subdirs) {
            $checkedCount++
            Write-Progress -Activity "Scanning for rebuildable releases" -Status "Checking: $($subdir.Name)" -PercentComplete (($checkedCount / $totalSubdirs) * 100)

            try {
                if (Test-RebuildableDirectory -Path $subdir.FullName) {
                    $rebuildableDirs.Add($subdir.FullName)
                }
            }
            catch {
                Write-Warning "Error checking subdirectory '$($subdir.Name)': $($_.Exception.Message)"
            }
        }

        Write-Progress -Activity "Scanning for rebuildable releases" -Completed
    }

    return $rebuildableDirs.ToArray()
}
