---
external help file: ReScenePS-help.xml
Module Name: ReScenePS
online version:
schema: 2.0.0
---

# Restore-SrsVideo

## SYNOPSIS
Reconstruct a sample video from an EBML SRS file and source MKV.

## SYNTAX

```
Restore-SrsVideo [-SrsFilePath] <String> [-SourceMkvPath] <String> [-OutputMkvPath] <String>
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
High-level function that orchestrates the reconstruction of a video sample from
an SRS file.
It performs the following steps:
1.
Verifies the SRS file is EBML format (MKV)
2.
Parses SRS metadata to get track information
3.
Extracts track data from the source MKV file
4.
Rebuilds the sample MKV by combining SRS structure with extracted track data

## EXAMPLES

### EXAMPLE 1
```
Restore-SrsVideo -SrsFilePath "sample.srs" -SourceMkvPath "movie.mkv" -OutputMkvPath "sample.mkv"
```

## PARAMETERS

### -SrsFilePath
Path to the extracted .srs file (EBML format).

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

### -SourceMkvPath
Path to the source MKV file (main movie).

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

### -OutputMkvPath
Path for the reconstructed sample MKV.

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
### Returns $true if reconstruction was successful, $false otherwise.
## NOTES
Uses match_offset from SRS metadata to extract ONLY the sample portion
from the main file, not the entire file.

## RELATED LINKS
