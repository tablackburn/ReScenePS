---
external help file: ReScenePS-help.xml
Module Name: ReScenePS
online version:
schema: 2.0.0
---

# Get-SrrBlock

## SYNOPSIS
Parse an SRR file and return all blocks.

## SYNTAX

```
Get-SrrBlock [-SrrFile] <String> [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Reads an SRR file and parses all block structures within it.
Returns an array of typed block objects (SrrHeaderBlock, SrrStoredFileBlock,
RarPackedFileBlock, etc.) that can be inspected or used for reconstruction.

## EXAMPLES

### EXAMPLE 1
```
Get-SrrBlock -SrrFile "release.srr"
```

Parses the SRR file and returns all blocks.

### EXAMPLE 2
```
Get-SrrBlock -SrrFile "release.srr" | Where-Object { $_ -is [RarPackedFileBlock] }
```

Returns only the RAR packed file blocks from the SRR.

## PARAMETERS

### -SrrFile
Path to the SRR file to parse.

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

### System.Object[]
### Array of block objects parsed from the SRR file.
## NOTES

## RELATED LINKS
