# CRC32 implementation using Add-Type with C#
# Uses IEEE 802.3 polynomial (same as ZIP, PNG, etc.)

if (-not ('ReScenePS.Crc32' -as [type])) {
    Add-Type -TypeDefinition @'
namespace ReScenePS
{
    using System.IO;

    public static class Crc32
    {
        private const uint Polynomial = 0xEDB88320;
        private const uint Seed = 0xFFFFFFFF;
        private static readonly uint[] Table = BuildTable();

        private static uint[] BuildTable()
        {
            var table = new uint[256];
            for (uint i = 0; i < 256; i++)
            {
                var crc = i;
                for (var j = 0; j < 8; j++)
                    crc = (crc & 1) == 1 ? (crc >> 1) ^ Polynomial : crc >> 1;
                table[i] = crc;
            }
            return table;
        }

        public static uint Compute(string filePath)
        {
            var crc = Seed;
            var buffer = new byte[81920]; // 80KB chunks
            using (var stream = File.OpenRead(filePath))
            {
                int bytesRead;
                while ((bytesRead = stream.Read(buffer, 0, buffer.Length)) > 0)
                {
                    for (var i = 0; i < bytesRead; i++)
                        crc = (crc >> 8) ^ Table[(crc ^ buffer[i]) & 0xFF];
                }
            }
            return crc ^ Seed;
        }
    }
}
'@
}

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
