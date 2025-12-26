---
external help file: ReScenePS-help.xml
Module Name: ReScenePS
online version:
schema: 2.0.0
---

# Build-SampleMkvFromSrs

## SYNOPSIS
Reconstruct sample MKV by hierarchically parsing SRS and injecting track data.

## SYNTAX

```
Build-SampleMkvFromSrs [-SrsFilePath] <String> [-TrackDataFiles] <Hashtable> [-OutputMkvPath] <String>
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Hierarchical EBML parsing approach:
1.
Read SRS file element-by-element using proper EBML VLQ decoding
2.
For container elements (Segment, Cluster, BlockGroup): write header, descend into children
3.
Skip ReSample container entirely (metadata only, not in final output)
4.
For Block/SimpleBlock elements: write header + block header + injected track data
5.
For all other elements: copy header + content directly

## EXAMPLES

### EXAMPLE 1
```
Build-SampleMkvFromSrs -SrsFilePath "sample.srs" -TrackDataFiles @{1="track1.dat"; 2="track2.dat"} -OutputMkvPath "sample.mkv"
```

## PARAMETERS

### -SrsFilePath
Path to the SRS file containing sample structure.

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

### -TrackDataFiles
Hashtable mapping track numbers to extracted track data file paths.

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -OutputMkvPath
Path for the output reconstructed MKV file.

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
