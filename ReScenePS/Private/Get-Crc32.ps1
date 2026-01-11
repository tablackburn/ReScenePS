function Get-Crc32 {
    <#
    .SYNOPSIS
        Calculate CRC32 checksum of a file.

    .DESCRIPTION
        Computes the CRC32 checksum using the IEEE 802.3 polynomial,
        compatible with ZIP, PNG, and SFV file formats.

    .PARAMETER FilePath
        Path to the file to checksum.

    .OUTPUTS
        System.UInt32
        The CRC32 checksum value.

    .EXAMPLE
        Get-Crc32 -FilePath 'C:\archive.rar'
        Returns the CRC32 checksum as an unsigned 32-bit integer.
    #>
    [CmdletBinding()]
    [OutputType([uint32])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Path', 'FullName')]
        [string]$FilePath
    )

    process {
        [ReScenePS.Crc32]::Compute($FilePath)
    }
}
