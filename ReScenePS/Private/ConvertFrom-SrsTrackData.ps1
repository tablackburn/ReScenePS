function ConvertFrom-SrsTrackData {
    <#
    .SYNOPSIS
    Parses TrackData element (0xC2) from SRS.

    .DESCRIPTION
    TrackData structure:
      - flags (2 bytes)
      - track_number (2 or 4 bytes)
      - data_length (4 or 8 bytes)
      - match_offset (8 bytes)
      - sig_length (2 bytes)
      - signature_bytes (variable)

    .PARAMETER Data
    Byte array containing the TrackData element

    .OUTPUTS
    [PSCustomObject] with Flags, TrackNumber, DataLength, MatchOffset, SignatureLength, SignatureBytes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$Data
    )

    if ($Data.Length -lt 18) {
        throw "TrackData too short: $($Data.Length) bytes"
    }

    $flags = [BitConverter]::ToUInt16($Data, 0)
    $offset = 2

    $isLargeTrackNum = ($flags -band 0x0008) -ne 0

    if ($isLargeTrackNum) {
        $trackNumber = [BitConverter]::ToUInt32($Data, $offset)
        $offset += 4
    }
    else {
        $trackNumber = [BitConverter]::ToUInt16($Data, $offset)
        $offset += 2
    }

    $isBigFile = ($flags -band 0x0004) -ne 0

    if ($isBigFile) {
        $dataLength = [BitConverter]::ToUInt64($Data, $offset)
        $offset += 8
    }
    else {
        $dataLength = [BitConverter]::ToUInt32($Data, $offset)
        $offset += 4
    }

    $matchOffset = [BitConverter]::ToUInt64($Data, $offset)
    $offset += 8

    $sigLength = [BitConverter]::ToUInt16($Data, $offset)
    $offset += 2

    $signatureBytes = New-Object byte[] $sigLength
    if ($sigLength -gt 0) {
        [System.Array]::Copy($Data, $offset, $signatureBytes, 0, $sigLength)
    }

    return [PSCustomObject]@{
        Flags = $flags
        TrackNumber = $trackNumber
        DataLength = $dataLength
        MatchOffset = $matchOffset
        SignatureLength = $sigLength
        SignatureBytes = $signatureBytes
    }
}
