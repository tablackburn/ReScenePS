# CRC32 lookup table (generated from polynomial 0xEDB88320)
$script:Crc32Table = $null

function Initialize-Crc32Table {
    if ($null -ne $script:Crc32Table) { return }

    $script:Crc32Table = New-Object uint32[] 256
    # 0xEDB88320 = 3988292384 in decimal (standard CRC32 polynomial)
    $polynomial = 3988292384

    for ($i = 0; $i -lt 256; $i++) {
        $crc = [uint32]$i
        for ($j = 0; $j -lt 8; $j++) {
            if (($crc -band 1) -eq 1) {
                $crc = [uint32](($crc -shr 1) -bxor $polynomial)
            }
            else {
                $crc = [uint32]($crc -shr 1)
            }
        }
        $script:Crc32Table[$i] = $crc
    }
}

function Get-Crc32 {
    <#
    .SYNOPSIS
    Calculate CRC32 hash of a file or portion of a file.

    .DESCRIPTION
    Native PowerShell CRC32 implementation using the standard IEEE polynomial.
    Supports offset and length for validating chunks of multi-volume archives.

    .PARAMETER FilePath
    Path to the file to hash

    .PARAMETER Offset
    Optional: Start reading from this byte offset

    .PARAMETER Length
    Optional: Only hash N bytes from the offset

    .OUTPUTS
    System.UInt32
    CRC32 value
    #>
    [CmdletBinding()]
    [OutputType([uint32])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter()]
        [long]$Offset = 0,

        [Parameter()]
        [long]$Length = -1
    )

    Initialize-Crc32Table

    $fs = [System.IO.File]::OpenRead($FilePath)
    try {
        if ($Offset -gt 0) {
            $fs.Seek($Offset, [System.IO.SeekOrigin]::Begin) | Out-Null
        }

        # 0xFFFFFFFF = 4294967295 in decimal
        $crc = [uint32]4294967295
        $buffer = New-Object byte[] 65536
        $totalRead = [long]0

        while (($bytesRead = $fs.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $processCount = $bytesRead

            if ($Length -gt 0) {
                $remaining = $Length - $totalRead
                if ($remaining -le 0) { break }
                if ($processCount -gt $remaining) {
                    $processCount = [int]$remaining
                }
            }

            for ($i = 0; $i -lt $processCount; $i++) {
                $tableIndex = [int](($crc -bxor $buffer[$i]) -band 255)
                $crc = [uint32](($crc -shr 8) -bxor $script:Crc32Table[$tableIndex])
            }

            $totalRead += $processCount

            if ($Length -gt 0 -and $totalRead -ge $Length) { break }
        }

        return [uint32]($crc -bxor 4294967295)
    }
    finally {
        $fs.Close()
    }
}
