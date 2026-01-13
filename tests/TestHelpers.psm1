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
    $pathUnrar = Get-Command 'unrar' -ErrorAction 'SilentlyContinue'
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
        Remove-Item -Path $Path -Recurse -Force -ErrorAction 'SilentlyContinue'
    }
}

function New-MinimalSrrFile {
    <#
    .SYNOPSIS
    Creates a minimal valid SRR file for testing purposes.

    .PARAMETER Path
    Path where the SRR file should be created.

    .PARAMETER AppName
    Application name to embed in the SRR header. Defaults to 'TestApp'.

    .DESCRIPTION
    Creates a minimal SRR file containing only the required header block.
    This is sufficient for tests that need to verify SRR file detection
    without requiring full SRR parsing or reconstruction.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$AppName = 'TestApp'
    )

    $appBytes = [System.Text.Encoding]::UTF8.GetBytes($AppName)
    $headerSize = 7 + 2 + $appBytes.Length
    $ms = [System.IO.MemoryStream]::new()
    $bw = [System.IO.BinaryWriter]::new($ms)
    try {
        $bw.Write([uint16]0x6969)
        $bw.Write([byte]0x69)
        $bw.Write([uint16]0x0000)
        $bw.Write([uint16]$headerSize)
        $bw.Write([uint16]$appBytes.Length)
        $bw.Write($appBytes)
        $bw.Flush()
        [System.IO.File]::WriteAllBytes($Path, $ms.ToArray())
    }
    finally {
        $bw.Dispose()
        $ms.Dispose()
    }
}

#endregion

#region Plex Data Source

function Test-PlexAvailable {
    <#
    .SYNOPSIS
    Checks if PlexAutomationToolkit is available and configured.

    .DESCRIPTION
    Returns true if:
    - PlexAutomationToolkit module is installed, AND
    - Either PAT_SERVER_URI/PAT_TOKEN env vars are set (CI), OR
    - A default server is configured (developer machine)

    .OUTPUTS
    [bool] True if Plex is available for use
    #>
    [CmdletBinding()]
    param()

    # Check if module is available
    if (-not (Get-Module -Name PlexAutomationToolkit -ListAvailable)) {
        return $false
    }

    # Check for CI environment variables
    if ($env:PAT_SERVER_URI -and $env:PAT_TOKEN) {
        return $true
    }

    # Check for stored config
    try {
        Import-Module PlexAutomationToolkit -ErrorAction 'Stop'
        $server = Get-PatStoredServer -Default -ErrorAction 'SilentlyContinue'
        return $null -ne $server
    }
    catch {
        return $false
    }
}

function Initialize-PlexForCI {
    <#
    .SYNOPSIS
    Configures PlexAutomationToolkit for CI environments using environment variables.

    .DESCRIPTION
    Sets up PAT with credentials from PAT_SERVER_URI and PAT_TOKEN environment variables.
    Creates necessary config directories and registers the server.
    No-op if env vars are not set or if already configured.

    .OUTPUTS
    [bool] True if Plex was configured successfully
    #>
    [CmdletBinding()]
    param()

    # Only needed for CI with env vars
    if (-not $env:PAT_SERVER_URI -or -not $env:PAT_TOKEN) {
        return $false
    }

    if (-not (Get-Module -Name PlexAutomationToolkit -ListAvailable)) {
        Write-Warning "PlexAutomationToolkit module not installed"
        return $false
    }

    # Ensure PAT config directories exist (required for CI runners)
    $tempBase = [System.IO.Path]::GetTempPath()
    if (-not $env:USERPROFILE) { $env:USERPROFILE = $tempBase }
    if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = Join-Path $tempBase 'LocalAppData' }

    $patConfigDirs = @(
        (Join-Path $env:USERPROFILE 'Documents\PlexAutomationToolkit'),
        (Join-Path $env:LOCALAPPDATA 'PlexAutomationToolkit')
    )
    foreach ($dir in $patConfigDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }

    # Import module and configure server
    Remove-Module PlexAutomationToolkit -ErrorAction 'SilentlyContinue'
    Import-Module PlexAutomationToolkit -Force

    try {
        $existingServer = Get-PatStoredServer -Name 'CI-Plex' -ErrorAction 'SilentlyContinue'
        if (-not $existingServer -or $existingServer.uri -ne $env:PAT_SERVER_URI) {
            Add-PatServer -Name 'CI-Plex' -ServerUri $env:PAT_SERVER_URI -Token $env:PAT_TOKEN -Default -Force -SkipValidation
        } else {
            Set-PatDefaultServer -Name 'CI-Plex' -ErrorAction 'SilentlyContinue'
        }
    }
    catch {
        Add-PatServer -Name 'CI-Plex' -ServerUri $env:PAT_SERVER_URI -Token $env:PAT_TOKEN -Default -Force -SkipValidation
    }

    return $true
}

function Get-PlexTestRelease {
    <#
    .SYNOPSIS
    Discovers test releases from a Plex playlist by examining file paths.

    .DESCRIPTION
    Queries the specified Plex playlist and extracts scene release information
    from the original file paths on the Plex server. Returns release metadata
    that can be used to download SRRs from srrdb and run reconstruction tests.

    .PARAMETER PlaylistName
    Name of the Plex playlist containing test media.

    .OUTPUTS
    [PSCustomObject[]] Array of release objects with properties:
    - ReleaseName: Scene release name extracted from file path
    - RatingKey: Plex rating key for downloading
    - Title: Plex title
    - Type: Media type (movie/episode)
    - FilePath: Original file path on Plex server
    - FileName: Original file name
    - FileSize: File size in bytes
    - Container: File container (avi, mkv, etc.)
    - VideoCodec: Video codec
    - VideoResolution: Resolution (sd, 720, 1080, etc.)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PlaylistName
    )

    if (-not (Get-Module -Name PlexAutomationToolkit)) {
        Import-Module PlexAutomationToolkit -ErrorAction 'Stop'
    }

    # Get playlist items
    $playlist = Get-PatPlaylist -PlaylistName $PlaylistName -IncludeItems -ErrorAction 'Stop'
    if (-not $playlist -or -not $playlist.Items) {
        Write-Warning "Playlist '$PlaylistName' is empty or not found"
        return @()
    }

    $releases = @()
    foreach ($item in $playlist.Items) {
        try {
            # Get detailed media info including file path
            $mediaInfo = Get-PatMediaInfo -RatingKey $item.RatingKey -ErrorAction 'Stop'

            # Use first media version only (Sync-PatMedia downloads one file per playlist item)
            $media = $mediaInfo.Media | Select-Object -First 1
            if ($media) {
                $part = $media.Part | Select-Object -First 1

                if (-not $part.File) {
                    Write-Warning "No file path found for '$($item.Title)' (RatingKey: $($item.RatingKey))"
                    continue
                }

                # Extract release name from file path
                # Path format: /mnt/.../Release.Name-GROUP/filename.ext
                $releaseName = $null
                $pathParts = $part.File -split '[/\\]'
                foreach ($pathPart in $pathParts) {
                    # Scene release pattern: Name.With.Dots-GROUP or Name.With.Dots.INTERNAL-GROUP
                    if ($pathPart -match '^[A-Za-z0-9.]+-[A-Za-z0-9]+$' -or
                        $pathPart -match '\.(XviD|x264|x265|HEVC|BluRay|DVDRip|BDRip|WEBRip|HDTV)[\.-]') {
                        $releaseName = $pathPart
                        break
                    }
                }

                if (-not $releaseName) {
                    Write-Warning "Could not extract release name from path: $($part.File)"
                    continue
                }

                $releases += [PSCustomObject]@{
                    ReleaseName     = $releaseName
                    RatingKey       = $item.RatingKey
                    Title           = $mediaInfo.Title
                    Type            = $mediaInfo.Type
                    FilePath        = $part.File
                    FileName        = Split-Path -Leaf $part.File
                    FileSize        = $part.Size
                    Container       = $part.Container
                    VideoCodec      = $media.VideoCodec
                    VideoResolution = $media.VideoResolution
                }

                Write-Verbose "Found release: $releaseName ($($media.VideoCodec) $($media.VideoResolution))"
            }
        }
        catch {
            Write-Warning "Failed to get media info for '$($item.Title)': $_"
        }
    }

    return $releases
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Initialize-TestEnvironment'
    'Get-UnrarPath'
    'Invoke-UnrarExtract'
    'New-TestTempDirectory'
    'Remove-TestTempDirectory'
    'New-MinimalSrrFile'
    # Plex data source functions
    'Test-PlexAvailable'
    'Initialize-PlexForCI'
    'Get-PlexTestRelease'
)
