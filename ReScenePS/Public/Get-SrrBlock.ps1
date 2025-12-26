function Get-SrrBlock {
    <#
    .SYNOPSIS
        Parse an SRR file and return all blocks.

    .DESCRIPTION
        Reads an SRR file and parses all block structures within it.
        Returns an array of typed block objects (SrrHeaderBlock, SrrStoredFileBlock,
        RarPackedFileBlock, etc.) that can be inspected or used for reconstruction.

    .PARAMETER SrrFile
        Path to the SRR file to parse.

    .EXAMPLE
        Get-SrrBlock -SrrFile "release.srr"

        Parses the SRR file and returns all blocks.

    .EXAMPLE
        Get-SrrBlock -SrrFile "release.srr" | Where-Object { $_ -is [RarPackedFileBlock] }

        Returns only the RAR packed file blocks from the SRR.

    .OUTPUTS
        System.Object[]
        Array of block objects parsed from the SRR file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$SrrFile
    )

    $reader = [BlockReader]::new($SrrFile)
    try {
        return $reader.ReadAllBlocks()
    }
    finally {
        $reader.Close()
    }
}
