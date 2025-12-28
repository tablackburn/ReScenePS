---
external help file: ReScenePS-help.xml
Module Name: ReScenePS
online version:
schema: 2.0.0
---

# ConvertFrom-SrsFileMetadata

## SYNOPSIS
Parse EBML SRS file to extract track metadata and match offsets.

## SYNTAX

```
ConvertFrom-SrsFileMetadata [-SrsFilePath] <String> [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Reads SRS file structure to extract:
- FileData: original file size, CRC32, filename
- TrackData: match_offset, data_length, signature_bytes for each track

This metadata is used to know WHERE and HOW MUCH to extract from the main file.

## EXAMPLES

### EXAMPLE 1
```
$metadata = ConvertFrom-SrsFileMetadata -SrsFilePath "sample.srs"
$metadata.Tracks | ForEach-Object { "Track $($_.TrackNumber): offset $($_.MatchOffset)" }
```

Parses the SRS file and displays the match offset for each track.

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

### Hashtable with keys: FileData, Tracks (array), SrsSize
## NOTES

## RELATED LINKS
