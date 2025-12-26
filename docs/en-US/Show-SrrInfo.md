---
external help file: ReScenePS-help.xml
Module Name: ReScenePS
online version:
schema: 2.0.0
---

# Show-SrrInfo

## SYNOPSIS
Display information about an SRR file.

## SYNTAX

```
Show-SrrInfo [-SrrFile] <String> [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Parses an SRR file and displays summary information including:
- Creating application name
- Stored files (NFO, SFV, etc.) with sizes
- RAR volume names
- Block type summary with counts

## EXAMPLES

### EXAMPLE 1
```
Show-SrrInfo -SrrFile "release.srr"
```

Displays formatted information about the SRR file contents.

## PARAMETERS

### -SrrFile
Path to the SRR file to analyze.

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

### None. Writes formatted output to the console.
## NOTES

## RELATED LINKS
