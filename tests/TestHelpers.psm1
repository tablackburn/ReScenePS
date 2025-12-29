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

#region Plex Data Source

function Test-PlexModuleAvailable {
    <#
    .SYNOPSIS
    Checks if PlexAutomationToolkit module is available.

    .OUTPUTS
    [bool] True if the module is available
    #>
    [CmdletBinding()]
    param()

    $null -ne (Get-Module -Name PlexAutomationToolkit -ListAvailable)
}

function Get-PlexConnectionInfo {
    <#
    .SYNOPSIS
    Gets Plex connection information from environment variables or stored config.

    .DESCRIPTION
    Checks for Plex credentials in the following order:
    1. Environment variables (PAT_SERVER_URI, PAT_TOKEN) - for CI/CD
    2. PlexAutomationToolkit stored config - for developer machines

    Requires PlexAutomationToolkit module to be installed for stored config.

    .OUTPUTS
    [hashtable] Contains ServerUri, Token, and Source, or $null if not available
    #>
    [CmdletBinding()]
    param()

    # Try environment variables first (CI/CD scenario)
    if ($env:PAT_SERVER_URI -and $env:PAT_TOKEN) {
        # Still need the module for API calls
        if (-not (Test-PlexModuleAvailable)) {
            Write-Verbose "PAT_SERVER_URI and PAT_TOKEN set but PlexAutomationToolkit not installed"
            return $null
        }

        # Ensure PAT configuration directory exists (required for CI runners)
        # PAT uses $env:OneDrive -> $env:USERPROFILE/Documents -> $env:LOCALAPPDATA
        # On Linux/macOS, these may not exist - set them to valid temp locations
        $tempBase = [System.IO.Path]::GetTempPath()
        if (-not $env:USERPROFILE) {
            $env:USERPROFILE = $tempBase
        }
        if (-not $env:LOCALAPPDATA) {
            $env:LOCALAPPDATA = Join-Path $tempBase 'LocalAppData'
        }
        # Pre-create PAT config directories in all fallback locations
        $patConfigDirs = @(
            (Join-Path $env:USERPROFILE 'Documents\PlexAutomationToolkit'),
            (Join-Path $env:LOCALAPPDATA 'PlexAutomationToolkit')
        )
        foreach ($dir in $patConfigDirs) {
            if (-not (Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
        }

        # Force reimport to pick up new environment variables
        Remove-Module PlexAutomationToolkit -ErrorAction SilentlyContinue
        Import-Module PlexAutomationToolkit -ErrorAction SilentlyContinue -Force

        # Configure PlexAutomationToolkit with env var credentials
        # On fresh CI runners, storage may not be initialized, so wrap in try-catch
        try {
            $existingServer = Get-PatStoredServer -Name 'CI-Plex' -ErrorAction SilentlyContinue
            if (-not $existingServer -or $existingServer.uri -ne $env:PAT_SERVER_URI) {
                Add-PatServer -Name 'CI-Plex' -ServerUri $env:PAT_SERVER_URI -Token $env:PAT_TOKEN -Default -Force -SkipValidation
            } else {
                Set-PatDefaultServer -Name 'CI-Plex' -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Storage not initialized - just add the server directly
            Add-PatServer -Name 'CI-Plex' -ServerUri $env:PAT_SERVER_URI -Token $env:PAT_TOKEN -Default -Force -SkipValidation
        }

        return @{
            ServerUri = $env:PAT_SERVER_URI
            Token     = $env:PAT_TOKEN
            Source    = 'Environment'
        }
    }

    # Try PlexAutomationToolkit stored config (developer scenario)
    if (-not (Test-PlexModuleAvailable)) {
        Write-Verbose "PlexAutomationToolkit module not installed"
        return $null
    }

    try {
        Import-Module PlexAutomationToolkit -ErrorAction Stop
        $server = Get-PatStoredServer -Default -ErrorAction Stop
        if ($server) {
            return @{
                ServerUri = $server.uri
                Token     = $server.token
                Source    = 'StoredConfig'
            }
        }
    }
    catch {
        Write-Verbose "Could not load PlexAutomationToolkit config: $_"
    }

    return $null
}

function Test-PlexConnectionAvailable {
    <#
    .SYNOPSIS
    Quick check if Plex connection is available.

    .OUTPUTS
    [bool] True if Plex connection info is available
    #>
    [CmdletBinding()]
    param()

    $info = Get-PlexConnectionInfo
    return $null -ne $info
}

function Get-PlexCachePath {
    <#
    .SYNOPSIS
    Returns the cache directory path for Plex-sourced test files.

    .PARAMETER CustomPath
    Optional custom cache path. If not specified, uses default temp location.

    .OUTPUTS
    [string] Path to the cache directory
    #>
    [CmdletBinding()]
    param(
        [string]$CustomPath
    )

    if ($CustomPath) {
        $cachePath = $CustomPath
    }
    elseif ($env:RUNNER_TEMP) {
        # GitHub Actions: use runner temp for consistent caching
        $cachePath = Join-Path $env:RUNNER_TEMP 'ReScenePS-PlexCache'
    }
    else {
        $cachePath = Join-Path ([System.IO.Path]::GetTempPath()) 'ReScenePS-PlexCache'
    }

    if (-not (Test-Path $cachePath)) {
        New-Item -Path $cachePath -ItemType Directory -Force | Out-Null
    }

    return $cachePath
}

function Get-CachedMediaFile {
    <#
    .SYNOPSIS
    Checks if a media file exists in the cache and is still fresh.

    .PARAMETER RatingKey
    The Plex rating key for the media item.

    .PARAMETER CachePath
    Path to the cache directory.

    .PARAMETER CacheTtlHours
    Cache time-to-live in hours. Use -1 for never expire.

    .OUTPUTS
    [string] Path to cached file if valid, or $null
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$RatingKey,

        [Parameter(Mandatory)]
        [string]$CachePath,

        [int]$CacheTtlHours = 168
    )

    $metadataPath = Join-Path $CachePath 'metadata.json'
    if (-not (Test-Path $metadataPath)) {
        return $null
    }

    try {
        $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
        $cacheKey = "rk_$RatingKey"

        if ($metadata.items.PSObject.Properties.Name -contains $cacheKey) {
            $entry = $metadata.items.$cacheKey

            if (Test-Path $entry.LocalPath) {
                # Check TTL
                if ($CacheTtlHours -lt 0) {
                    # Never expire
                    return $entry.LocalPath
                }

                $cachedTime = [datetime]::Parse($entry.CachedAt)
                $age = (Get-Date) - $cachedTime

                if ($age.TotalHours -lt $CacheTtlHours) {
                    return $entry.LocalPath
                }
            }
        }
    }
    catch {
        Write-Verbose "Error reading cache metadata: $_"
    }

    return $null
}

function Remove-CachedMediaFile {
    <#
    .SYNOPSIS
    Removes a specific cached media file by RatingKey.

    .DESCRIPTION
    Surgically removes a single cached file and updates metadata.
    Useful for freeing disk space in CI environments after processing.
    Returns silently if the cache entry doesn't exist (already cleaned up).

    .PARAMETER RatingKey
    The Plex rating key for the media item to remove.

    .PARAMETER CachePath
    Path to the cache directory.

    .OUTPUTS
    [bool] True if file was removed, false if not found or already cleaned
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$RatingKey,

        [Parameter(Mandatory)]
        [string]$CachePath
    )

    $metadataPath = Join-Path $CachePath 'metadata.json'
    if (-not (Test-Path $metadataPath)) {
        # No metadata file means nothing to clean up
        return $false
    }

    $cacheKey = "rk_$RatingKey"

    try {
        $metadata = Get-Content $metadataPath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable
    }
    catch {
        # Metadata file unreadable or invalid - nothing to clean up
        return $false
    }

    # Check if this RatingKey exists in cache
    if (-not $metadata.items -or -not $metadata.items.ContainsKey($cacheKey)) {
        # Entry doesn't exist - already cleaned up or never cached
        return $false
    }

    $entry = $metadata.items[$cacheKey]

    # Remove the actual file and its parent directory if they exist
    if ($entry.LocalPath) {
        $parentDir = Split-Path -Parent $entry.LocalPath
        if ($parentDir -and (Test-Path $parentDir)) {
            try {
                Remove-Item -Path $parentDir -Recurse -Force -ErrorAction Stop
                Write-Verbose "Removed cached directory: $parentDir"
            }
            catch {
                # Directory may have already been removed by another process
                Write-Verbose "Could not remove cached directory: $parentDir - $_"
            }
        }
    }

    # Update metadata to remove the entry
    try {
        $metadata.items.Remove($cacheKey)
        $metadata | ConvertTo-Json -Depth 10 | Set-Content $metadataPath -Encoding UTF8
    }
    catch {
        Write-Warning "Failed to update cache metadata after removing RatingKey $RatingKey`: $_"
        return $false
    }

    return $true
}

function Invoke-PlexMediaDownload {
    <#
    .SYNOPSIS
    Downloads a media file from Plex to the cache directory.

    .PARAMETER RatingKey
    The Plex rating key for the media item.

    .PARAMETER CachePath
    Path to the cache directory.

    .PARAMETER ServerUri
    Plex server URI.

    .PARAMETER Token
    Plex authentication token.

    .OUTPUTS
    [string] Path to the downloaded file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$RatingKey,

        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [string]$ServerUri,

        [Parameter(Mandatory)]
        [string]$Token
    )

    # Get media info from Plex
    $mediaInfo = Get-PatMediaInfo -RatingKey $RatingKey

    if (-not $mediaInfo -or -not $mediaInfo.Media) {
        throw "Could not get media info for RatingKey $RatingKey"
    }

    # Get the first media part (main file)
    $media = $mediaInfo.Media | Select-Object -First 1
    $part = $media.Part | Select-Object -First 1

    if (-not $part) {
        throw "No media parts found for RatingKey $RatingKey"
    }

    # Determine destination path
    $extension = $part.Container
    $safeTitle = $mediaInfo.Title -replace '[^\w\-\.]', '_'
    $destDir = Join-Path $CachePath $safeTitle
    $destPath = Join-Path $destDir "$safeTitle.$extension"

    if (-not (Test-Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }

    # Construct download URL
    $partKey = $part.Key
    $downloadUrl = "$ServerUri$partKey`?download=1&X-Plex-Token=$Token"

    Write-Verbose "Downloading from Plex: $($mediaInfo.Title) to $destPath"

    # Download the file
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $destPath -UseBasicParsing
    }
    catch {
        throw "Failed to download from Plex: $_"
    }

    # Update cache metadata
    $metadataPath = Join-Path $CachePath 'metadata.json'
    if (Test-Path $metadataPath) {
        $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json -AsHashtable
    }
    else {
        $metadata = @{ items = @{} }
    }

    $cacheKey = "rk_$RatingKey"
    $metadata.items[$cacheKey] = @{
        LocalPath = $destPath
        CachedAt  = (Get-Date).ToString('o')
        Size      = $part.Size
        Title     = $mediaInfo.Title
        RatingKey = $RatingKey
    }

    $metadata | ConvertTo-Json -Depth 10 | Set-Content $metadataPath -Encoding UTF8

    return $destPath
}

function Find-PlexItemByRelease {
    <#
    .SYNOPSIS
    Finds a Plex library item that matches a scene release.

    .PARAMETER ReleaseName
    The scene release name to search for.

    .PARAMETER Mapping
    Optional mapping hashtable with search criteria (Title, Year, RatingKey, etc.)

    .PARAMETER CollectionName
    Name of the Plex collection to search within.

    .PARAMETER LibraryName
    Name of the Plex library to search.

    .OUTPUTS
    [object] Plex media info object, or $null if not found
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ReleaseName,

        [hashtable]$Mapping,

        [string]$CollectionName,

        [string]$LibraryName = 'Movies'
    )

    # If we have a direct RatingKey, use it
    if ($Mapping -and $Mapping.RatingKey) {
        try {
            return Get-PatMediaInfo -RatingKey $Mapping.RatingKey
        }
        catch {
            Write-Warning "Could not get media info for RatingKey $($Mapping.RatingKey): $_"
        }
    }

    # Search within a collection
    if ($CollectionName) {
        try {
            $collection = Get-PatCollection -CollectionName $CollectionName -LibraryName $LibraryName -IncludeItems -ErrorAction Stop

            if ($collection -and $collection.Items) {
                foreach ($item in $collection.Items) {
                    $mediaInfo = Get-PatMediaInfo -RatingKey $item.RatingKey -ErrorAction SilentlyContinue

                    if (-not $mediaInfo) { continue }

                    # Check if the file path contains the release name
                    $filePath = $mediaInfo.Media[0].Part[0].File
                    if ($filePath -match [regex]::Escape($ReleaseName)) {
                        return $mediaInfo
                    }

                    # Match by title/year from mapping
                    if ($Mapping) {
                        if ($Mapping.Title -and $mediaInfo.Title -like "*$($Mapping.Title)*") {
                            if (-not $Mapping.Year -or $mediaInfo.Year -eq $Mapping.Year) {
                                return $mediaInfo
                            }
                        }
                    }
                }
            }
        }
        catch {
            Write-Verbose "Error searching collection: $_"
        }
    }

    return $null
}

function Get-PlexSourceFile {
    <#
    .SYNOPSIS
    Gets a source file from Plex, using cache if available.

    .DESCRIPTION
    High-level function that checks cache first, then downloads from Plex if needed.
    Includes retry logic for reliability.

    .PARAMETER ReleaseName
    The scene release name.

    .PARAMETER Mapping
    Mapping hashtable with search criteria.

    .PARAMETER CachePath
    Path to the cache directory.

    .PARAMETER CacheTtlHours
    Cache TTL in hours.

    .PARAMETER CollectionName
    Name of the Plex collection to search.

    .PARAMETER LibraryName
    Name of the Plex library.

    .PARAMETER MaxRetries
    Maximum download retry attempts.

    .OUTPUTS
    [string] Path to the source file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ReleaseName,

        [hashtable]$Mapping,

        [string]$CachePath,

        [int]$CacheTtlHours = 168,

        [string]$CollectionName,

        [string]$LibraryName = 'Movies',

        [int]$MaxRetries = 3
    )

    $plexInfo = Get-PlexConnectionInfo
    if (-not $plexInfo) {
        throw "Plex connection not available. Set PAT_SERVER_URI and PAT_TOKEN environment variables, or configure PlexAutomationToolkit."
    }

    if (-not $CachePath) {
        $CachePath = Get-PlexCachePath
    }

    # Check cache first if we have a RatingKey
    if ($Mapping -and $Mapping.RatingKey) {
        $cached = Get-CachedMediaFile -RatingKey $Mapping.RatingKey -CachePath $CachePath -CacheTtlHours $CacheTtlHours
        if ($cached) {
            Write-Verbose "Using cached file: $cached"
            return $cached
        }
    }

    # Find the item in Plex
    $mediaInfo = Find-PlexItemByRelease -ReleaseName $ReleaseName -Mapping $Mapping -CollectionName $CollectionName -LibraryName $LibraryName

    if (-not $mediaInfo) {
        throw "Could not find Plex item matching '$ReleaseName'"
    }

    # Check cache with the found RatingKey
    $cached = Get-CachedMediaFile -RatingKey $mediaInfo.RatingKey -CachePath $CachePath -CacheTtlHours $CacheTtlHours
    if ($cached) {
        Write-Verbose "Using cached file: $cached"
        return $cached
    }

    # Download with retries
    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            $result = Invoke-PlexMediaDownload `
                -RatingKey $mediaInfo.RatingKey `
                -CachePath $CachePath `
                -ServerUri $plexInfo.ServerUri `
                -Token $plexInfo.Token

            return $result
        }
        catch {
            $lastError = $_
            $delay = [math]::Pow(2, $attempt)
            Write-Warning "Download attempt $attempt failed: $_. Retrying in $delay seconds..."
            Start-Sleep -Seconds $delay
        }
    }

    throw "Failed to download after $MaxRetries attempts: $lastError"
}

function Clear-PlexTestCache {
    <#
    .SYNOPSIS
    Clears all cached Plex test files.

    .PARAMETER CachePath
    Optional custom cache path.
    #>
    [CmdletBinding()]
    param(
        [string]$CachePath
    )

    $path = Get-PlexCachePath -CustomPath $CachePath
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force
        Write-Verbose "Cleared Plex test cache at: $path"
    }
}

function Get-PlexTestCacheInfo {
    <#
    .SYNOPSIS
    Gets information about the Plex test cache.

    .PARAMETER CachePath
    Optional custom cache path.

    .OUTPUTS
    [hashtable] Cache statistics
    #>
    [CmdletBinding()]
    param(
        [string]$CachePath
    )

    $path = Get-PlexCachePath -CustomPath $CachePath
    if (-not (Test-Path $path)) {
        return @{
            Exists    = $false
            Path      = $path
            Size      = 0
            SizeGB    = 0
            ItemCount = 0
        }
    }

    $files = Get-ChildItem -Path $path -Recurse -File
    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum

    return @{
        Exists    = $true
        Path      = $path
        Size      = $totalSize
        SizeGB    = [math]::Round($totalSize / 1GB, 2)
        ItemCount = $files.Count
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
    # Plex data source functions
    'Test-PlexModuleAvailable'
    'Get-PlexConnectionInfo'
    'Test-PlexConnectionAvailable'
    'Get-PlexCachePath'
    'Get-CachedMediaFile'
    'Remove-CachedMediaFile'
    'Invoke-PlexMediaDownload'
    'Find-PlexItemByRelease'
    'Get-PlexSourceFile'
    'Clear-PlexTestCache'
    'Get-PlexTestCacheInfo'
)
