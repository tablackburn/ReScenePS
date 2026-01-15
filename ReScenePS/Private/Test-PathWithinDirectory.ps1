function Test-PathWithinDirectory {
    <#
    .SYNOPSIS
    Tests if a path is within a specified directory (prevents path traversal attacks).

    .DESCRIPTION
    Validates that a resolved path is contained within a base directory. This function
    prevents path traversal attacks where malicious input like "..\..\file.txt" could
    write files outside the intended output directory.

    The validation:
    1. Resolves the full path (normalizes ".." and "." sequences)
    2. Checks the resolved path starts with BaseDirectory + separator

    The separator suffix prevents false positives where BaseDirectory="C:\Output"
    and Path="C:\OutputMalicious\file.txt" would incorrectly pass a simple
    StartsWith("C:\Output") check.

    .NOTES
    Security consideration: GetFullPath resolves symbolic links on some platforms.
    In environments where an attacker can create symlinks pointing outside the base
    directory, additional symlink validation may be needed. For typical SRR/SRS
    reconstruction scenarios where input comes from trusted archive files, this
    is not a concern.

    .PARAMETER Path
    The path to validate (may contain relative components like ".." or ".").

    .PARAMETER BaseDirectory
    The directory that Path must be within.

    .OUTPUTS
    [bool] $true if Path is within BaseDirectory, $false otherwise.

    .EXAMPLE
    Test-PathWithinDirectory -Path "C:\Output\subdir\file.txt" -BaseDirectory "C:\Output"
    Returns $true because the path is within the base directory.

    .EXAMPLE
    Test-PathWithinDirectory -Path "C:\Output\..\Other\file.txt" -BaseDirectory "C:\Output"
    Returns $false because the resolved path "C:\Other\file.txt" is outside the base directory.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$BaseDirectory
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedBase = [System.IO.Path]::GetFullPath($BaseDirectory)

    # Check if path equals base directory or starts with base directory + separator
    # The separator check prevents "C:\OutputMalicious" matching base "C:\Output"
    return $resolvedPath -eq $resolvedBase -or
        $resolvedPath.StartsWith(
            $resolvedBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase
        )
}
