function Compare-ByteArray {
    <#
    .SYNOPSIS
    Compares two byte arrays for equality.

    .PARAMETER Array1
    First byte array

    .PARAMETER Array2
    Second byte array

    .OUTPUTS
    [bool] True if arrays are equal, false otherwise
    #>
    param(
        [byte[]]$Array1,
        [byte[]]$Array2
    )

    if ($Array1.Length -ne $Array2.Length) {
        return $false
    }

    for ($i = 0; $i -lt $Array1.Length; $i++) {
        if ($Array1[$i] -ne $Array2[$i]) {
            return $false
        }
    }

    return $true
}
