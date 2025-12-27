---
external help file: ReScenePS-help.xml
Module Name: ReScenePS
online version:
schema: 2.0.0
---

# Build-SampleAviFromSrs

## SYNOPSIS
Reconstructs an AVI sample file from an SRS file and source video.

## SYNTAX

```
Build-SampleAviFromSrs [-SrsData] <Byte[]> [-SourcePath] <String> [-OutputPath] <String>
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
AVI SRS files store the structure of the original sample (frame headers
and their sizes) without the actual frame data.
This function:
1.
Parses the SRS to get track metadata (match offsets in source)
2.
Copies the AVI structure from the SRS
3.
Injects frame data from the source file at the correct offsets

## EXAMPLES

### EXAMPLE 1
```
Build-SampleAviFromSrs -SrsData $srsBytes -SourcePath "movie.avi" -OutputPath "sample.avi"
```

## PARAMETERS

### -SrsData
Raw bytes of the SRS file.

```yaml
Type: Byte[]
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -SourcePath
Path to the source AVI file containing the full movie.

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
Path for the reconstructed sample AVI file.

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

### System.Boolean
### Returns $true if reconstruction was successful.
## NOTES

## RELATED LINKS
