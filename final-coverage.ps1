Import-Module './Output/ReScenePS/0.2.1/ReScenePS.psd1' -Force

$coverageFiles = @(
    (Get-ChildItem './Output/ReScenePS/0.2.1/Public/*.ps1'),
    (Get-ChildItem './Output/ReScenePS/0.2.1/Private/*.ps1'),
    (Get-ChildItem './Output/ReScenePS/0.2.1/Classes/*.ps1')
) | ForEach-Object { $_.FullName }

$config = New-PesterConfiguration
$config.Run.Path = './tests'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = $coverageFiles
$config.Output.Verbosity = 'None'
$config.Run.PassThru = $true

$result = Invoke-Pester -Configuration $config

$executed = $result.CodeCoverage.CommandsExecutedCount
$missed = $result.CodeCoverage.CommandsMissedCount
$total = $executed + $missed
$pct = if ($total -gt 0) { [math]::Round(($executed / $total) * 100, 2) } else { 0 }

Write-Host ''
Write-Host '=== FINAL Coverage Summary ==='
Write-Host "Commands Executed: $executed"
Write-Host "Commands Missed: $missed"
Write-Host "Total Commands: $total"
Write-Host "Coverage: $pct%"
Write-Host ''

if ($pct -ge 90) {
    Write-Host "SUCCESS: Coverage target of 90% REACHED!" -ForegroundColor Green
} else {
    Write-Host "Need $(90 - $pct)% more coverage to reach 90%" -ForegroundColor Yellow
    Write-Host ''
    Write-Host '=== Files with Lowest Coverage ==='
    $result.CodeCoverage.CommandsMissed |
        Group-Object File |
        Select-Object @{N='File';E={Split-Path $_.Name -Leaf}}, Count |
        Sort-Object Count -Descending |
        Select-Object -First 10 |
        Format-Table -AutoSize
}
