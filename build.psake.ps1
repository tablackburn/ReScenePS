param()

# Allow end users to add their own custom psake tasks
$customPsakeFile = Join-Path -Path $PSScriptRoot -ChildPath 'custom.psake.ps1'
if (Test-Path -Path $customPsakeFile) {
    Include -FileNamePathToInclude $customPsakeFile
}

properties {
    # Set this to $true to create a module with a monolithic PSM1
    $PSBPreference.Build.CompileModule = $false
    $PSBPreference.Help.DefaultLocale = 'en-US'
    $PSBPreference.Test.OutputFile = 'out/testResults.xml'
    $PSBPreference.Test.OutputFormat = 'NUnitXml'
    $PSBPreference.Test.CodeCoverage.Enabled = $false  # Disabled until unit tests are added
    $PSBPreference.Test.CodeCoverage.Threshold = 0.70  # 70% minimum coverage
}

Task -Name 'Default' -Depends 'Test'

Task -Name 'Test' -FromModule 'PowerShellBuild' -MinimumVersion '0.7.3'
