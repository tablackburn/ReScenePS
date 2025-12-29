---
external help file: ReScenePS-help.xml
Module Name: ReScenePS
online version:
schema: 2.0.0
---

# Invoke-SrrRestore

## SYNOPSIS
Complete SRR restoration - extracts stored files, reconstructs archives, validates, and cleans up.

## SYNTAX

```
Invoke-SrrRestore [[-SrrFile] <String>] [[-SourcePath] <String>] [[-OutputPath] <String>] [-KeepSrr]
 [-KeepSources] [-SkipValidation] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
This is the main entry point for SRR restoration.
It performs:
- Auto-detection of SRR file if not specified
- Auto-detection of source files
- Extraction of all stored files (NFO, SFV, etc.)
- Reconstruction of RAR volumes
- CRC validation against SFV
- Cleanup of temporary and source files (with confirmation)

## EXAMPLES

### EXAMPLE 1
```
Invoke-SrrRestore
```

Auto-detects the SRR file and source files in the current directory and performs a complete restoration.

### EXAMPLE 2
```
Invoke-SrrRestore -SrrFile "Release.srr" -KeepSrr
```

Specifies the SRR file explicitly and preserves it after successful restoration.

## PARAMETERS

### -SrrFile
Path to SRR file.
If not specified, searches current directory for a single .srr file.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -SourcePath
Directory containing source files.
Defaults to current directory.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: .
Accept pipeline input: False
Accept wildcard characters: False
```

### -OutputPath
Directory for reconstructed release.
Defaults to current directory.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: .
Accept pipeline input: False
Accept wildcard characters: False
```

### -KeepSrr
If specified, do not delete SRR file after successful restoration.

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
If specified, do not delete source files (e.g., .mkv) after successful restoration.

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
Skip CRC validation against embedded SFV. Use when source files differ from original
scene release (e.g., when using Plex or other media server sources for testing).

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
{{ Fill ProgressAction Description }}

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
