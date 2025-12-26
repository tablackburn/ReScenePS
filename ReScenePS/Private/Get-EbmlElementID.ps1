function Get-EbmlElementID {
    <#
    .SYNOPSIS
    Reads an EBML Element ID (1-4 bytes) from a byte stream.

    .PARAMETER Buffer
    Byte array to read from

    .PARAMETER Offset
    Starting position in buffer

    .OUTPUTS
    [hashtable] @{ ElementID = [byte[]], Length = [int] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$Buffer,

        [Parameter(Mandatory=$true)]
        [int]$Offset
    )

    $firstByte = $Buffer[$Offset]
    $elementLength = Get-EbmlUIntLength -LengthDescriptor $firstByte

    $elementID = New-Object byte[] $elementLength
    [System.Array]::Copy($Buffer, $Offset, $elementID, 0, $elementLength)

    return @{
        ElementID = $elementID
        Length = $elementLength
    }
}
