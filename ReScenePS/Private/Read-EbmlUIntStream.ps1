function Read-EbmlUIntStream {
    <#
    .SYNOPSIS
    Reads an EBML variable-length unsigned integer from a stream.

    .PARAMETER Stream
    Stream object with Read method

    .OUTPUTS
    [hashtable] @{ Value = [uint64], BytesConsumed = [int] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Stream
    )

    $firstByteArray = New-Object byte[] 1
    $Stream.Read($firstByteArray, 0, 1) | Out-Null
    $firstByte = $firstByteArray[0]

    $bytesConsumed = Get-EbmlUIntLength -LengthDescriptor $firstByte

    [uint64]$mask = 0xFF -shr $bytesConsumed
    [uint64]$size = [uint64]($firstByte -band $mask)

    for ($i = 1; $i -lt $bytesConsumed; $i++) {
        $byteArray = New-Object byte[] 1
        $Stream.Read($byteArray, 0, 1) | Out-Null
        $size = ($size -shl 8) + [uint64]$byteArray[0]
    }

    return @{
        Value = $size
        BytesConsumed = $bytesConsumed
    }
}
