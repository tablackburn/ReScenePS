[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'plexHealth',
    Justification = 'Variable used in Describe blocks'
)]
param()

# Preflight for the Plex-backed functional tests.
#
# This exists because a revoked PAT_TOKEN went unnoticed: the old availability check
# only asked whether credentials were present, so CI believed Plex was usable, then the
# first real call failed with 401 during discovery. A container that dies during
# discovery generates no tests, so CI reported green while an entire test file never
# ran. Nothing pointed at the token.
#
# One cheap probe, run before the expensive tests, so the failure names itself instead
# of arriving as twenty confusing downstream errors.
#
# Deliberately different outcomes per state:
#
#   NotConfigured - skip. A fork or a contributor with no Plex is not a fault.
#   Unreachable   - skip with a warning. Home infrastructure reboots, and failing every
#                   pull request over that trains people to ignore red builds. The
#                   scheduled canary (.github/workflows/plex-canary.yaml) chases this.
#   Unauthorized  - fail. The server answered and refused the credentials, which means
#                   a secret is wrong or revoked and somebody has to act.
BeforeDiscovery {
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
    $plexHealth = Get-PlexHealth

    if ($plexHealth.State -eq 'Unreachable') {
        Write-Warning "Plex is configured but unreachable: $($plexHealth.Detail). Plex-backed tests will be skipped."
    }
}

Describe 'Plex preflight' {
    BeforeAll {
        # No -Force here. Get-PlexHealth caches its result in module state, and
        # re-importing with -Force discards that cache and triggers a second network
        # probe. The -Skip: expressions below were evaluated during discovery against
        # the first probe, so a server that changed state in between would leave an
        # unskipped test asserting a different reality than the one it was scheduled
        # against. Importing without -Force is a no-op when already loaded and keeps
        # both phases on the same answer.
        Import-Module "$PSScriptRoot/TestHelpers.psm1"
        $script:health = Get-PlexHealth
    }

    It 'reports a recognised health state' {
        $script:health.State | Should -BeIn @('NotConfigured', 'Unreachable', 'Unauthorized', 'Healthy')
    }

    # Skipped when Plex is absent or the server is down; only a live rejection fails.
    It 'is authenticated by the configured Plex server' -Skip:($plexHealth.State -in @('NotConfigured', 'Unreachable')) {
        $because = 'PAT_TOKEN or the stored server token has been revoked or is wrong. ' +
            'Regenerate the token and update the PAT_TOKEN secret ' +
            '(gh secret set PAT_TOKEN --repo tablackburn/ReScenePS).'
        $script:health.State | Should -Be 'Healthy' -Because $because
    }
}
