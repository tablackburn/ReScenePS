function Read-EbmlUIntStream {
    <#
    .SYNOPSIS
    Reads an EBML variable-length unsigned integer from a stream.

    .PARAMETER Stream
    Stream object with Read method

    .OUTPUTS
    System.Collections.Hashtable
    Hashtable with Value (uint64) and BytesConsumed (int) keys
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
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
