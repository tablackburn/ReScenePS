function Get-EbmlElementFromBuffer {
    <#
    .SYNOPSIS
    Reads a complete EBML element from a buffer (ID + size + data).

    .PARAMETER Buffer
    Byte array to read from

    .PARAMETER Offset
    Starting position in buffer

    .OUTPUTS
    [hashtable] @{ ElementID = [byte[]], DataSize = [uint64], ElementData = [byte[]], TotalLength = [int] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$Buffer,

        [Parameter(Mandatory=$true)]
        [int]$Offset
    )

    $idResult = Get-EbmlElementID -Buffer $Buffer -Offset $Offset
    $elementID = $idResult.ElementID
    $idLength = $idResult.Length

    $sizeOffset = $Offset + $idLength
    $firstByte = $Buffer[$sizeOffset]
    $sizeByteCount = Get-EbmlUIntLength -LengthDescriptor $firstByte
    $dataSize = Get-EbmlUInt -Buffer $Buffer -Offset $sizeOffset -ByteCount $sizeByteCount

    $dataOffset = $sizeOffset + $sizeByteCount
    $available = [Math]::Max(0, $Buffer.Length - $dataOffset)
    if ($dataSize -gt $available) {
        $dataSize = [uint64]$available
    }
    $elementData = New-Object byte[] $dataSize
    [System.Array]::Copy($Buffer, $dataOffset, $elementData, 0, [int]$dataSize)

    $totalLength = $idLength + $sizeByteCount + $dataSize

    return @{
        ElementID = $elementID
        DataSize = $dataSize
        ElementData = $elementData
        TotalLength = $totalLength
    }
}
