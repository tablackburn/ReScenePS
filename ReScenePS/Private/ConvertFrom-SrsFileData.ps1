function ConvertFrom-SrsFileData {
    <#
    .SYNOPSIS
    Parses FileData element (0xC1) from SRS.

    .DESCRIPTION
    FileData structure:
      - flags (2 bytes)
      - app_name_len (2 bytes)
      - app_name (variable)
      - file_name_len (2 bytes)
      - file_name (variable)
      - original_size (4 or 8 bytes depending on flags)
      - crc32 (4 bytes)

    .PARAMETER Data
    Byte array containing the FileData element

    .OUTPUTS
    [PSCustomObject] with Flags, AppName, FileName, OriginalSize, CRC32
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [byte[]]$Data
    )

    if ($Data.Length -lt 14) {
        throw "FileData too short: $($Data.Length) bytes"
    }

    $flags = [BitConverter]::ToUInt16($Data, 0)
    $appNameLen = [BitConverter]::ToUInt16($Data, 2)

    $offset = 4
    $appName = [System.Text.Encoding]::ASCII.GetString($Data, $offset, $appNameLen)
    $offset += $appNameLen

    $fileNameLen = [BitConverter]::ToUInt16($Data, $offset)
    $offset += 2

    $fileName = [System.Text.Encoding]::ASCII.GetString($Data, $offset, $fileNameLen)
    $offset += $fileNameLen

    $isBigFile = ($flags -band 0x0001) -ne 0

    if ($isBigFile) {
        $originalSize = [BitConverter]::ToUInt64($Data, $offset)
        $offset += 8
    }
    else {
        $originalSize = [BitConverter]::ToUInt32($Data, $offset)
        $offset += 4
    }

    $crc32 = [BitConverter]::ToUInt32($Data, $offset)

    return [PSCustomObject]@{
        Flags = $flags
        AppName = $appName
        FileName = $fileName
        OriginalSize = $originalSize
        CRC32 = $crc32
    }
}
