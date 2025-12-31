function Get-EbmlUInt {
    <#
    .SYNOPSIS
    Reads an EBML variable-length unsigned integer from a buffer.

    .DESCRIPTION
    Decodes an EBML variable-length unsigned integer. The first byte contains
    the length descriptor bits which must be masked out before interpreting the value.

    .PARAMETER Buffer
    Byte array to read from

    .PARAMETER Offset
    Starting position in buffer

    .PARAMETER ByteCount
    Number of bytes to consume (from length descriptor)

    .OUTPUTS
    System.UInt64
    The decoded integer value
    #>
    [CmdletBinding()]
    [OutputType([uint64])]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$Buffer,

        [Parameter(Mandatory=$true)]
        [int]$Offset,

        [Parameter(Mandatory=$true)]
        [int]$ByteCount
    )

    [uint64]$mask = 0xFF -shr $ByteCount
    [uint64]$size = [uint64]($Buffer[$Offset] -band $mask)

    for ($i = 1; $i -lt $ByteCount; $i++) {
        $size = ($size -shl 8) + [uint64]$Buffer[$Offset + $i]
    }

    return $size
}
