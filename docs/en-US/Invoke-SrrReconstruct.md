---
external help file: ReScenePS-help.xml
Module Name: ReScenePS
online version:
schema: 2.0.0
---

# Invoke-SrrReconstruct

## SYNOPSIS
Reconstruct RAR archive volumes from an SRR file and source files.

## SYNTAX

```
Invoke-SrrReconstruct [-SrrFile] <String> [-SourcePath] <String> [-OutputPath] <String> [-SkipValidation]
 [-ExtractStoredFiles] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Reads SRR metadata and rebuilds the original RAR archive files by:
1.
Parsing SRR for block structure
2.
Writing RAR headers from SRR metadata
3.
Copying file data from source files

## EXAMPLES

### EXAMPLE 1
```
Invoke-SrrReconstruct -SrrFile "release.srr" -SourcePath "." -OutputPath "./output"
```

Reconstructs RAR archives from the SRR file using source files in the current directory.

## PARAMETERS

### -SrrFile
Path to the SRR file.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -SourcePath
Directory containing source files.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -OutputPath
Directory for output RAR files.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -SkipValidation
Skip source file size validation.

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

### -ExtractStoredFiles
Also extract stored files (NFO, SFV, etc.) to output directory.

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
