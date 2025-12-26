function Export-StoredFile {
    <#
    .SYNOPSIS
    Extract a stored file from SRR blocks to disk.

    .PARAMETER SrrFile
    Path to the SRR file

    .PARAMETER FileName
    Name of the stored file to extract (supports wildcards)

    .PARAMETER OutputPath
    Where to save the extracted file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SrrFile,

        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $reader = [BlockReader]::new($SrrFile)
    try {
        $blocks = $reader.ReadAllBlocks()

        $pattern = $FileName -replace '\*', '.*'
        $stored = $blocks | Where-Object {
            $_.HeadType -eq 0x6A -and $_.FileName -match "^$pattern$"
        } | Select-Object -First 1

        if (-not $stored) {
            throw "Stored file not found in SRR matching pattern: $FileName"
        }

        Write-Host "    Extracting: $($stored.FileName) ($($stored.FileSize) bytes)" -ForegroundColor Gray

        $fs = [System.IO.File]::OpenRead($SrrFile)
        try {
            $br = [System.IO.BinaryReader]::new($fs)

            $currentPos = 0
            foreach ($block in $blocks) {
                $blockSize = $block.HeadSize + $block.AddSize

                if ($block -eq $stored) {
                    $dataStart = $currentPos + $block.HeadSize
                    $fs.Seek($dataStart, [System.IO.SeekOrigin]::Begin) | Out-Null

                    $fileData = $br.ReadBytes($stored.FileSize)
                    [System.IO.File]::WriteAllBytes($OutputPath, $fileData)
                    return
                }

                $currentPos += $blockSize
            }

            throw "Could not find file data in stream"
        }
        finally {
            $br.Dispose()
            $fs.Close()
        }
    }
    finally {
        $reader.Close()
    }
}
