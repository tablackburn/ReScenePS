function ConvertTo-ByteString {
    <#
    .SYNOPSIS
    Converts a byte array to a hex string for display.

    .PARAMETER Bytes
    Byte array to convert

    .OUTPUTS
    [string] Hex string representation
    #>
    param([byte[]]$Bytes)
    return ($Bytes | ForEach-Object { $_.ToString('X2') } | Join-String)
}
