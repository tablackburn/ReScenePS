function ConvertFrom-SrsFile {
    <#
    .SYNOPSIS
    Parses an SRS file and extracts metadata and track information.

    .PARAMETER FilePath
    Path to the SRS file

    .OUTPUTS
    [PSCustomObject] containing FileMetadata, Tracks, RawBytes, SegmentDataOffset
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        throw "SRS file not found: $FilePath"
    }

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    Write-Verbose "Read SRS file: $($bytes.Length) bytes"

    $offset = 0
    $element = Get-EbmlElementFromBuffer -Buffer $bytes -Offset $offset
    Write-Verbose "Element at 0: $(ConvertTo-ByteString -Bytes $element.ElementID) ($($element.DataSize) bytes)"

    $offset += $element.TotalLength

    $element = Get-EbmlElementFromBuffer -Buffer $bytes -Offset $offset
    Write-Verbose "Element at ${offset}: $(ConvertTo-ByteString -Bytes $element.ElementID) ($($element.DataSize) bytes)"

    $segment = $element
    $segmentDataOffset = $offset + $element.ElementID.Length

    $tracks = @()
    $fileData = $null

    $contentOffset = 0
    while ($contentOffset -lt $segment.DataSize) {
        try {
            $currentOffset = $segmentDataOffset + $contentOffset
            if ($currentOffset + 2 -gt $bytes.Length) {
                break
            }

            $elem = Get-EbmlElementFromBuffer -Buffer $bytes -Offset $currentOffset
            $elemIdHex = ConvertTo-ByteString -Bytes $elem.ElementID

            Write-Verbose "  Element at +${contentOffset}: ${elemIdHex} ($($elem.DataSize) bytes)"

            if ($elem.ElementID.Length -eq 1 -and $elem.ElementID[0] -eq 0xC1) {
                Write-Verbose "    -> ReSampleFile found"
                $fileData = ConvertFrom-SrsFileData -Data $elem.ElementData
            }
            elseif ($elem.ElementID.Length -eq 1 -and $elem.ElementID[0] -eq 0xC2) {
                Write-Verbose "    -> ReSampleTrack found"
                $trackData = ConvertFrom-SrsTrackData -Data $elem.ElementData
                $tracks += $trackData
            }

            $contentOffset += $elem.TotalLength
        }
        catch {
            Write-Verbose "Error parsing element at offset $($segmentDataOffset + $contentOffset): $_"
            break
        }
    }

    return [PSCustomObject]@{
        FileMetadata = $fileData
        Tracks = $tracks
        RawBytes = $bytes
        SegmentDataOffset = $segmentDataOffset
    }
}
