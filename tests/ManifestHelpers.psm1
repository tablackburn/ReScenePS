<#
    This module provides helper functions for validating module dependency versions
    using Semantic Versioning (SemVer) conventions, including prerelease version support.
#>

function Split-SemVerString {
    <#
    .SYNOPSIS
    Splits a version string into version and prerelease components.

    .DESCRIPTION
    Parses a SemVer-formatted version string (e.g., "1.2.3-beta.1") into separate
    version and prerelease components. This enables proper comparison of prerelease
    versions using SemVer 2.0.0 specification rules.

    .PARAMETER VersionString
    The version string to parse. Can be in the format "1.2.3" or "1.2.3-prerelease".

    .OUTPUTS
    [hashtable]
    Returns a hashtable with two keys:
    - Version: The numeric version portion (e.g., "1.2.3")
    - Prerelease: The prerelease identifier (e.g., "beta.1") or $null if none

    .EXAMPLE
    Split-SemVerString -VersionString "1.2.3-beta.1"

    Returns: @{ Version = "1.2.3"; Prerelease = "beta.1" }

    .EXAMPLE
    Split-SemVerString -VersionString "2.0.0"

    Returns: @{ Version = "2.0.0"; Prerelease = $null }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VersionString
    )

    # Strip build metadata per SemVer 2.0.0 — it does not affect precedence and is
    # not valid for [System.Version], so it must be removed before further parsing.
    $coreVersion = ($VersionString -split '\+', 2)[0]
    $parts = $coreVersion -split '-', 2
    return @{
        Version = $parts[0]
        Prerelease = if ($parts.Length -gt 1) { $parts[1] } else { $null }
    }
}

function Compare-SemVerPrerelease {
    <#
    .SYNOPSIS
    Compares two SemVer prerelease identifiers according to SemVer 2.0.0 specification.

    .DESCRIPTION
    Implements SemVer 2.0.0 prerelease comparison rules (section 11.4):
    - Compares dot-separated identifiers from left to right
    - Numeric identifiers are compared as integers
    - Alphanumeric identifiers are compared lexically (ASCII sort)
    - Numeric identifiers always have lower precedence than alphanumeric
    - More identifiers > fewer identifiers (if all preceding are equal)

    .PARAMETER FirstPrerelease
    The first prerelease identifier (e.g., "alpha.1"). Must not be null.

    .PARAMETER SecondPrerelease
    The second prerelease identifier (e.g., "beta.2"). Must not be null.

    .OUTPUTS
    [int]
    Returns -1 if first < second, 0 if equal, 1 if first > second.

    .EXAMPLE
    Compare-SemVerPrerelease -FirstPrerelease "alpha.1" -SecondPrerelease "alpha.2"
    Returns: -1 (alpha.1 < alpha.2)

    .EXAMPLE
    Compare-SemVerPrerelease -FirstPrerelease "beta.11" -SecondPrerelease "beta.2"
    Returns: 1 (11 > 2 numerically)

    .EXAMPLE
    Compare-SemVerPrerelease -FirstPrerelease "1" -SecondPrerelease "alpha"
    Returns: -1 (numeric < alphanumeric)
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FirstPrerelease,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SecondPrerelease
    )

    $firstIdentifiers = $FirstPrerelease -split '\.'
    $secondIdentifiers = $SecondPrerelease -split '\.'

    $maxLength = [Math]::Max($firstIdentifiers.Length, $secondIdentifiers.Length)

    for ($i = 0; $i -lt $maxLength; $i++) {
        # If first has fewer identifiers, it has lower precedence
        if ($i -ge $firstIdentifiers.Length) {
            return -1
        }

        # If second has fewer identifiers, it has lower precedence
        if ($i -ge $secondIdentifiers.Length) {
            return 1
        }

        $firstId = $firstIdentifiers[$i]
        $secondId = $secondIdentifiers[$i]

        # Check if identifiers are numeric (consist only of digits)
        $firstIsNumeric = $firstId -match '^\d+$'
        $secondIsNumeric = $secondId -match '^\d+$'

        if ($firstIsNumeric -and $secondIsNumeric) {
            # SemVer 2.0.0 permits arbitrarily large numeric identifiers — use BigInteger
            # rather than [long] to avoid overflow. [bigint] is a PS 7+ accelerator only,
            # so spell out the full type for Windows PowerShell 5.1 compatibility.
            $firstNum = [System.Numerics.BigInteger]$firstId
            $secondNum = [System.Numerics.BigInteger]$secondId

            if ($firstNum -lt $secondNum) {
                return -1
            }
            elseif ($firstNum -gt $secondNum) {
                return 1
            }
            # Equal, continue to next identifier
        }
        elseif ($firstIsNumeric) {
            # First is numeric, second is alphanumeric: numeric < alphanumeric
            return -1
        }
        elseif ($secondIsNumeric) {
            # First is alphanumeric, second is numeric: alphanumeric > numeric
            return 1
        }
        else {
            # Both alphanumeric: compare lexically
            $comparison = [string]::Compare($firstId, $secondId, [System.StringComparison]::Ordinal)
            if ($comparison -ne 0) {
                return [Math]::Sign($comparison)
            }
            # Equal, continue to next identifier
        }
    }

    # All identifiers are equal
    return 0
}

function Test-VersionComparison {
    <#
    .SYNOPSIS
    Compares two SemVer versions according to SemVer 2.0.0 specification.

    .DESCRIPTION
    Compares two semantic versions, including their prerelease components, following
    SemVer 2.0.0 rules. Returns $true if the first version is newer than the second version.

    Comparison logic:
    1. Compare base versions (major.minor.patch) numerically
    2. If base versions equal, apply prerelease precedence rules:
        - Version without prerelease > version with prerelease
        - Compare prerelease identifiers using SemVer rules

    .PARAMETER FirstVersion
    The numeric version portion of the first version (e.g., "1.2.3").

    .PARAMETER FirstPrerelease
    The prerelease identifier of the first version (e.g., "beta.1") or $null if none.

    .PARAMETER SecondVersion
    The numeric version portion of the second version (e.g., "1.2.2").

    .PARAMETER SecondPrerelease
    The prerelease identifier of the second version (e.g., "alpha.5") or $null if none.

    .OUTPUTS
    [bool]
    Returns $true if the first version is newer than the second version, $false otherwise.

    .EXAMPLE
    Test-VersionComparison -FirstVersion "1.2.3" -FirstPrerelease "beta.1" -SecondVersion "1.2.3" -SecondPrerelease "alpha.1"

    Returns: $true (beta.1 is newer than alpha.1)

    .EXAMPLE
    Test-VersionComparison -FirstVersion "1.2.3" -FirstPrerelease $null -SecondVersion "1.2.2" -SecondPrerelease $null

    Returns: $true (1.2.3 is newer than 1.2.2)

    .EXAMPLE
    Test-VersionComparison -FirstVersion "1.2.3" -FirstPrerelease $null -SecondVersion "1.2.3" -SecondPrerelease "beta.1"

    Returns: $true (1.2.3 > 1.2.3-beta.1 per SemVer spec)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FirstVersion,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$FirstPrerelease,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SecondVersion,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$SecondPrerelease
    )

    # Normalize versions to ensure consistent component count (fixes .NET Version comparison quirks)
    # .NET treats "1.0.0" (Revision=-1) and "1.0.0.0" (Revision=0) as different, so normalize both to 4 components
    $normalizedFirst = $FirstVersion
    $firstComponents = $normalizedFirst.Split('.')
    if ($firstComponents.Count -gt 4) {
        throw "Version string '$FirstVersion' has too many components. .NET Version supports maximum 4 components (Major.Minor.Build.Revision)."
    }
    for ($c = $firstComponents.Count; $c -lt 4; $c++) { $normalizedFirst += '.0' }

    $normalizedSecond = $SecondVersion
    $secondComponents = $normalizedSecond.Split('.')
    if ($secondComponents.Count -gt 4) {
        throw "Version string '$SecondVersion' has too many components. .NET Version supports maximum 4 components (Major.Minor.Build.Revision)."
    }
    for ($c = $secondComponents.Count; $c -lt 4; $c++) { $normalizedSecond += '.0' }

    # Compare base versions using .NET Version type
    $firstVer = [version]$normalizedFirst
    $secondVer = [version]$normalizedSecond

    $versionComparison = $firstVer.CompareTo($secondVer)

    if ($versionComparison -ne 0) {
        # Base versions differ: return based on numeric comparison
        return $versionComparison -gt 0
    }

    # Base versions are equal, apply prerelease precedence rules
    $firstHasPrerelease = -not [string]::IsNullOrEmpty($FirstPrerelease)
    $secondHasPrerelease = -not [string]::IsNullOrEmpty($SecondPrerelease)

    if (-not $firstHasPrerelease -and -not $secondHasPrerelease) {
        # Both are release versions: equal
        return $false
    }

    if (-not $firstHasPrerelease) {
        # First is release, second is prerelease: release > prerelease
        return $true
    }

    if (-not $secondHasPrerelease) {
        # First is prerelease, second is release: prerelease < release
        return $false
    }

    # Both have prerelease: compare using SemVer prerelease rules
    $prereleaseComparison = Compare-SemVerPrerelease -FirstPrerelease $FirstPrerelease -SecondPrerelease $SecondPrerelease
    return $prereleaseComparison -gt 0
}

function Test-VersionConstraint {
    <#
    .SYNOPSIS
    Tests whether a manifest version satisfies a version constraint.

    .DESCRIPTION
    Validates that a module manifest version meets a specific constraint relative to
    a requirements version. Supports three constraint types:
    - Equal: Versions must be exactly the same (for RequiredVersion)
    - GreaterOrEqual: Manifest version must be >= requirements (for MaximumVersion)
    - LessOrEqual: Manifest version must be <= requirements (for ModuleVersion/minimum)

    .PARAMETER ManifestVersion
    The version from the module manifest (e.g., "1.2.3-beta.1").

    .PARAMETER RequirementsVersion
    The version from requirements.psd1 (e.g., "1.2.3").

    .PARAMETER Constraint
    The type of constraint to validate. Valid values are:
    - Equal: Versions must match exactly
    - GreaterOrEqual: ManifestVersion >= RequirementsVersion
    - LessOrEqual: ManifestVersion <= RequirementsVersion

    .OUTPUTS
    [bool]
    Returns $true if the constraint is satisfied, $false otherwise.

    .EXAMPLE
    Test-VersionConstraint -ManifestVersion "1.2.3" -RequirementsVersion "1.2.3" -Constraint "Equal"

    Returns: $true (versions match exactly)

    .EXAMPLE
    Test-VersionConstraint -ManifestVersion "2.0.0" -RequirementsVersion "1.5.0" -Constraint "GreaterOrEqual"

    Returns: $true (2.0.0 >= 1.5.0)

    .EXAMPLE
    Test-VersionConstraint -ManifestVersion "1.0.0" -RequirementsVersion "1.5.0" -Constraint "LessOrEqual"

    Returns: $true (1.0.0 <= 1.5.0)

    .EXAMPLE
    Test-VersionConstraint -ManifestVersion "1.2.3-beta.1" -RequirementsVersion "1.2.3-alpha.5" -Constraint "GreaterOrEqual"

    Returns: $true (beta.1 is newer than alpha.5)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ManifestVersion,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RequirementsVersion,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Equal', 'GreaterOrEqual', 'LessOrEqual')]
        [string]$Constraint
    )

    # Validate input versions are not empty
    if ([string]::IsNullOrWhiteSpace($ManifestVersion)) {
        throw 'ManifestVersion cannot be empty or whitespace'
    }
    if ([string]::IsNullOrWhiteSpace($RequirementsVersion)) {
        throw 'RequirementsVersion cannot be empty or whitespace'
    }

    $manifestParts = Split-SemVerString -VersionString $ManifestVersion
    $requirementsParts = Split-SemVerString -VersionString $RequirementsVersion

    $comparisonParameters = @{
        FirstVersion     = $requirementsParts.Version
        FirstPrerelease  = $requirementsParts.Prerelease
        SecondVersion    = $manifestParts.Version
        SecondPrerelease = $manifestParts.Prerelease
    }
    $requirementsIsNewer = Test-VersionComparison @comparisonParameters

    $reversedComparisonParameters = @{
        FirstVersion     = $manifestParts.Version
        FirstPrerelease  = $manifestParts.Prerelease
        SecondVersion    = $requirementsParts.Version
        SecondPrerelease = $requirementsParts.Prerelease
    }
    $manifestIsNewer = Test-VersionComparison @reversedComparisonParameters

    switch ($Constraint) {
        'Equal' {
            # RequiredVersion must exactly match (neither version is newer than the other)
            return (-not $requirementsIsNewer) -and (-not $manifestIsNewer)
        }
        'GreaterOrEqual' {
            # MaximumVersion must be >= requirements (requirements not newer, or equal)
            return (-not $requirementsIsNewer)
        }
        'LessOrEqual' {
            # ModuleVersion must be <= requirements (manifest not newer than requirements)
            return (-not $manifestIsNewer)
        }
        default {
            throw "Unsupported constraint: '$Constraint'"
        }
    }
}

Export-ModuleMember -Function 'Test-VersionConstraint'
