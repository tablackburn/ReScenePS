---
external help file: ReScenePS-help.xml
Module Name: ReScenePS
online version:
schema: 2.0.0
---

# Export-SampleTrackData

## SYNOPSIS
Extract sample track data from main file using match_offset and data_length.

## SYNTAX

```
Export-SampleTrackData [-MainFilePath] <String> [-MatchOffset] <UInt64> [-DataLength] <UInt64>
 [-OutputPath] <String> [[-SignatureBytes] <Byte[]>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Reads data from a source file starting at the specified offset and
writes the specified number of bytes to an output file.
This is used
for extracting track data when reconstructing video samples.

NOTE: This is a legacy function - use Export-MkvTrackData for MKV files.

## EXAMPLES

### EXAMPLE 1
```
Export-SampleTrackData -MainFilePath "movie.mkv" -MatchOffset 12345678 -DataLength 5000000 -OutputPath "track1.dat"
```

Extracts 5MB of track data starting at the specified offset from the source MKV file.

## PARAMETERS

### -MainFilePath
Path to the main file to extract data from.

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

### -MatchOffset
Byte offset in the source file to start reading from.

```yaml
Type: UInt64
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -DataLength
Number of bytes to extract.

```yaml
Type: UInt64
Parameter Sets: (All)
Aliases:

Required: True
Position: 3
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -OutputPath
Path where the extracted data will be written.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -SignatureBytes
Optional signature bytes for validation.

```yaml
Type: Byte[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
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
### Returns $true if extraction was successful.
## NOTES

## RELATED LINKS
