function ConvertTo-EbmlElementString {
    <#
    .SYNOPSIS
    Converts EBML element ID to hex string for display/comparison.

    .PARAMETER ElementID
    Byte array containing the element ID

    .OUTPUTS
    [string] Hex string representation (e.g., "0x1A45DFA3")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$ElementID
    )

    return ('0x{0}' -f ($ElementID | ForEach-Object { $_.ToString('X2') } | Join-String))
}
