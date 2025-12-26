function Find-SourceFile {
    <#
    .SYNOPSIS
    Find a source file by name in a directory, optionally matching expected size.

    .PARAMETER FileName
    Name of the file to find

    .PARAMETER SearchPath
    Directory to search in

    .PARAMETER ExpectedSize
    Optional: Expected file size in bytes

    .OUTPUTS
    [string] Full path to the found file, or $null if not found
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [string]$SearchPath,

        [Parameter()]
        [uint64]$ExpectedSize
    )

    $directPath = Join-Path $SearchPath $FileName
    if (Test-Path $directPath) {
        $fileInfo = Get-Item $directPath
        if ($ExpectedSize -eq 0 -or $fileInfo.Length -eq $ExpectedSize) {
            return $fileInfo.FullName
        }
    }

    $files = Get-ChildItem -Path $SearchPath -Recurse -File -Filter (Split-Path $FileName -Leaf) -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        if ($ExpectedSize -eq 0 -or $file.Length -eq $ExpectedSize) {
            return $file.FullName
        }
    }

    return $null
}
