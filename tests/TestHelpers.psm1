# TestHelpers.psm1 - Shared test utilities for ReScenePS tests

#region Module Setup

function Initialize-TestEnvironment {
    <#
    .SYNOPSIS
    Sets up the test environment with proper paths and imports the module.

    .DESCRIPTION
    Configures BH* environment variables and imports the built module.
    Call this in BeforeAll blocks of test files.

    .OUTPUTS
    [hashtable] Contains ProjectRoot, ModulePath, and ModuleName
    #>
    [CmdletBinding()]
    param()

    $projectRoot = Split-Path -Parent $PSScriptRoot
    $moduleName = 'ReScenePS'

    # Always compute the correct build output path from the source manifest
    # This ensures we find the module even if BHBuildOutput was set incorrectly
    $Env:BHProjectName = $moduleName
    $Env:BHProjectPath = $projectRoot
    $sourceManifest = Join-Path $projectRoot "$moduleName/$moduleName.psd1"
    $moduleVersion = (Import-PowerShellDataFile -Path $sourceManifest).ModuleVersion
    $Env:BHBuildOutput = Join-Path $projectRoot "Output/$moduleName/$moduleVersion"

    # Verify the module exists
    $moduleManifestPath = Join-Path -Path $Env:BHBuildOutput -ChildPath "$moduleName.psd1"
    if (-not (Test-Path -Path $moduleManifestPath)) {
        throw "Module not found at $moduleManifestPath. Run 'build.ps1 -Task Build' first."
    }

    # Import the module globally so it's available in calling scope
    Get-Module $moduleName | Remove-Module -Force -ErrorAction 'Ignore'
    Import-Module -Name $moduleManifestPath -Global -Verbose:$false -ErrorAction 'Stop'

    return @{
        ProjectRoot = $projectRoot
        ModulePath  = $Env:BHBuildOutput
        ModuleName  = $moduleName
    }
}

#endregion

#region Test Tools

function Get-UnrarPath {
    <#
    .SYNOPSIS
    Returns the path to UnRAR executable, downloading if necessary.

    .DESCRIPTION
    Checks for UnRAR in the following order:
    1. tools/unrar.exe in project root (downloaded by build task)
    2. UnRAR.exe in PATH
    3. Common installation locations

    Returns $null if UnRAR is not available.

    .OUTPUTS
    [string] Path to UnRAR executable, or $null if not found
    #>
    [CmdletBinding()]
    param()

    $projectRoot = Split-Path -Parent $PSScriptRoot

    # Check tools directory first (downloaded by DownloadTestTools task)
    $toolsUnrar = Join-Path -Path $projectRoot -ChildPath 'tools/unrar.exe'
    if (Test-Path -Path $toolsUnrar) {
        return $toolsUnrar
    }

    # Check PATH
    $pathUnrar = Get-Command 'unrar' -ErrorAction SilentlyContinue
    if ($pathUnrar) {
        return $pathUnrar.Source
    }

    # Check common Windows locations
    $commonPaths = @(
        'C:\Program Files\WinRAR\UnRAR.exe',
        'C:\Program Files (x86)\WinRAR\UnRAR.exe',
        "$env:LOCALAPPDATA\Programs\WinRAR\UnRAR.exe"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path -Path $path) {
            return $path
        }
    }

    return $null
}

function Invoke-UnrarExtract {
    <#
    .SYNOPSIS
    Extracts files from a RAR archive using UnRAR.

    .PARAMETER RarPath
    Path to the RAR archive to extract.

    .PARAMETER OutputPath
    Directory to extract files to.

    .PARAMETER Overwrite
    If specified, overwrites existing files without prompting.

    .OUTPUTS
    [bool] True if extraction succeeded, False otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RarPath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [switch]$Overwrite
    )

    $unrar = Get-UnrarPath
    if (-not $unrar) {
        Write-Warning "UnRAR not available. Run 'build.ps1 -Task DownloadTestTools' to download."
        return $false
    }

    if (-not (Test-Path -Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    $args = @('x')
    if ($Overwrite) {
        $args += '-o+'
    }
    else {
        $args += '-o-'
    }
    $args += '-y'  # Assume yes to all queries
    $args += $RarPath
    $args += "$OutputPath\"

    try {
        $result = & $unrar @args 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        Write-Warning "UnRAR extraction failed: $_"
        return $false
    }
}

#endregion

#region Test Data Helpers

function New-TestTempDirectory {
    <#
    .SYNOPSIS
    Creates a uniquely-named temporary directory for test use.

    .PARAMETER Prefix
    Optional prefix for the directory name.

    .OUTPUTS
    [string] Path to the created temporary directory.
    #>
    [CmdletBinding()]
    param(
        [string]$Prefix = 'ReScenePS-Test'
    )

    $uniqueId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $tempPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "$Prefix-$uniqueId"
    New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    return $tempPath
}

function Remove-TestTempDirectory {
    <#
    .SYNOPSIS
    Safely removes a test temporary directory.

    .PARAMETER Path
    Path to the directory to remove.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($Path -and (Test-Path -Path $Path)) {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Initialize-TestEnvironment'
    'Get-UnrarPath'
    'Invoke-UnrarExtract'
    'New-TestTempDirectory'
    'Remove-TestTempDirectory'
)
