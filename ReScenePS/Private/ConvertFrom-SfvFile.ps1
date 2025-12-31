function ConvertFrom-SfvFile {
    <#
    .SYNOPSIS
    Parse an SFV file and return a hash table of filename -> CRC.

    .PARAMETER FilePath
    Path to the SFV file

    .OUTPUTS
    System.Collections.Hashtable
    Filename to CRC32 mapping
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $sfvData = @{}
    $content = Get-Content -Path $FilePath -ErrorAction Stop

    foreach ($line in $content) {
        $line = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(';')) {
            continue
        }

        $match = [regex]::Match($line, '^(.+?)\s+([0-9A-Fa-f]{8})$')
        if ($match.Success) {
            $fileName = $match.Groups[1].Value
            $crc = $match.Groups[2].Value
            $sfvData[$fileName] = [Convert]::ToUInt32($crc, 16)
        }
    }

    return $sfvData
}
