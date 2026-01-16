---
external help file: ReScenePS-help.xml
Module Name: ReScenePS
online version:
schema: 2.0.0
---

# Restore-Release

## SYNOPSIS
Scans directories for releases, downloads required files from srrDB, and rebuilds with original names.

## SYNTAX

```
Restore-Release [[-Path] <String>] [-Recurse] [-Depth <Int32>] [-SourcePath <String>] [-KeepSrr]
 [-DeleteSources] [-SkipValidation] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
This is the main automation command for ReScenePS.
It performs:
- Detection of release names from directory names
- Querying srrDB for release metadata
- Downloading SRR files and any additional files from srrDB (proof images, samples, etc. that are stored separately on srrDB rather than embedded in the SRR file)
- Calling Invoke-SrrRestore to rebuild the release with original names and structure

Requires the SrrDBAutomationToolkit module for srrDB API access.

## EXAMPLES

### EXAMPLE 1
```
Restore-Release
```

Scans current directory, downloads SRR from srrDB, and rebuilds the release.

### EXAMPLE 2
```
Restore-Release -Path "D:\Downloads\Movie.2024.1080p.BluRay-GROUP"
```

Processes a specific release directory.

### EXAMPLE 3
```
Restore-Release -Path "D:\Downloads" -Recurse
```

Processes all subdirectories as separate releases.

### EXAMPLE 4
```
Restore-Release -KeepSrr -WhatIf
```

Preview what would happen without making changes.

### EXAMPLE 5
```powershell
Restore-Release -DeleteSources
```

Restore and delete source files after successful restoration.

## PARAMETERS

### -Path
Directory to scan for releases.
Defaults to current directory.

In single mode (default), the function first checks if the specified directory
contains rebuildable content (video files \>= 100MB or .srr files). If so, it
processes that directory as a release. If not, it automatically scans immediate
subdirectories for rebuildable releases.

With -Recurse, treats each subdirectory as a separate release without checking
if the parent directory itself is rebuildable.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: .
Accept pipeline input: False
Accept wildcard characters: False
```

### -Recurse
Process each subdirectory as a separate release instead of the root directory.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Depth
Maximum depth to search for rebuildable releases when auto-detecting subdirectories.
Only applies in single mode (without -Recurse) when the specified directory itself
is not rebuildable.
Defaults to 1 (immediate subdirectories only).
Set to 0 to disable subdirectory scanning, or higher values to search deeper.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 1
Accept pipeline input: False
Accept wildcard characters: False
```

### -SourcePath
Directory containing source files for reconstruction (e.g., .mkv files).
Defaults to the release directory being processed.
Use this when source files are stored in a different location than the release folder.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -KeepSrr
Keep the SRR file after successful restoration.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -DeleteSources
Delete source files (e.g., .mkv) after successful restoration.
By default, source files are kept.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -SkipValidation
Skip CRC validation against embedded SFV.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
Specifies how the cmdlet responds to progress updates.

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

## RELATED LINKS
