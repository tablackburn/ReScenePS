function Get-SrsInfo {
    <#
    .SYNOPSIS
    Identify basic SRS type from magic bytes and return info.

    .PARAMETER FilePath
    Path to the .srs file to inspect

    .OUTPUTS
    [PSCustomObject] with Path, Size, Type properties
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        throw "SRS file not found: $FilePath"
    }

    $type = "Unknown"
    $len = (Get-Item $FilePath).Length

    $fs = [System.IO.File]::OpenRead($FilePath)
    try {
        $br = [System.IO.BinaryReader]::new($fs)
        $magic = $br.ReadBytes(4)

        $asAscii = [System.Text.Encoding]::ASCII.GetString($magic)

        if ($magic.Length -eq 4) {
            switch -Regex ($asAscii) {
                '^RIFF$' { $type = 'RIFF (AVI/WMV/MP3 containers)'; break }
                '^fLaC$' { $type = 'FLAC'; break }
                '^STRM$' { $type = 'Stream (Generic)'; break }
                '^M2TS$' { $type = 'M2TS Stream'; break }
                default {
                    if ($magic[0] -eq 0x1A -and $magic[1] -eq 0x45 -and $magic[2] -eq 0xDF -and $magic[3] -eq 0xA3) {
                        $type = 'EBML (MKV)'
                    }
                }
            }
        }
    }
    finally {
        if ($br) { $br.Dispose() }
        $fs.Close()
    }

    [PSCustomObject]@{
        Path = (Resolve-Path $FilePath).Path
        Size = $len
        Type = $type
    }
}
