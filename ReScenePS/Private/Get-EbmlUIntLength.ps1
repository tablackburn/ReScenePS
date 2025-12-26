function Get-EbmlUIntLength {
    <#
    .SYNOPSIS
    Returns the number of bytes that will be consumed based on the first byte (Length Descriptor).

    .DESCRIPTION
    EBML uses a variable-length encoding where the first byte indicates how many bytes total
    will be consumed. The first byte's leading 1-bit position determines the byte count.

    .PARAMETER LengthDescriptor
    First byte read from EBML stream (0-255)

    .OUTPUTS
    [int] Number of bytes (1-8)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte]$LengthDescriptor
    )

    for ($i = 0; $i -lt 8; $i++) {
        $testBit = 0x80 -shr $i
        if (($LengthDescriptor -band $testBit) -ne 0) {
            return $i + 1
        }
    }
    return 0
}
