function Get-Crc32 {
    <#
    .SYNOPSIS
    Calculate CRC32 hash of a file or portion of a file.

    .DESCRIPTION
    Uses the CRC PowerShell Gallery module. Supports offset and length
    for validating chunks of multi-volume archives.

    .PARAMETER FilePath
    Path to the file to hash

    .PARAMETER Offset
    Optional: Start reading from this byte offset

    .PARAMETER Length
    Optional: Only hash N bytes from the offset

    .OUTPUTS
    [uint32] CRC32 value
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter()]
        [long]$Offset = 0,

        [Parameter()]
        [long]$Length = -1
    )

    if ($Offset -gt 0 -or $Length -gt 0) {
        $fs = [System.IO.File]::OpenRead($FilePath)
        try {
            if ($Offset -gt 0) {
                $fs.Seek($Offset, [System.IO.SeekOrigin]::Begin) | Out-Null
            }

            $tempFile = [System.IO.Path]::GetTempFileName()
            $tempFs = [System.IO.File]::Create($tempFile)
            try {
                $buffer = New-Object byte[] 65536
                $totalRead = [long]0
                $bytesRead = 0

                while (($bytesRead = $fs.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    if ($Length -gt 0) {
                        $remaining = $Length - $totalRead
                        if ($remaining -le 0) { break }
                        if ($bytesRead -gt $remaining) {
                            $bytesRead = [int]$remaining
                        }
                    }

                    $tempFs.Write($buffer, 0, $bytesRead)
                    $totalRead += $bytesRead
                }

                $tempFs.Close()
                $result = CRC\Get-CRC32 -Path $tempFile
                return [Convert]::ToUInt32($result.Hash, 16)
            }
            finally {
                if ($tempFs) { $tempFs.Dispose() }
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
        finally {
            $fs.Close()
        }
    }
    else {
        $result = CRC\Get-CRC32 -Path $FilePath
        return [Convert]::ToUInt32($result.Hash, 16)
    }
}
