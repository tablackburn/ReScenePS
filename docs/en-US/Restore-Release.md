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
Restore-Release [[-Path] <String>] [-Recurse] [-SourcePath <String>] [-KeepSrr] [-KeepSources]
 [-SkipValidation] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
This is the main automation command for ReScenePS.
It performs:
- Detection of release names from directory names
- Querying srrDB for release metadata
- Downloading SRR files and any additional files (proofs, etc.) not stored in the SRR
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
Restore-Release -KeepSrr -KeepSources -WhatIf
```

Preview what would happen without making changes.

## PARAMETERS

### -Path
Directory to scan for releases.
Defaults to current directory.
In single mode (default), treats this directory as the release.
With -Recurse, treats each subdirectory as a separate release.

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

### -SourcePath
Directory containing source files for reconstruction.
Defaults to the release directory.
Can be set to a different location if source files are stored separately.

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

### -KeepSources
Keep source files (e.g., .mkv) after successful restoration.

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
