# CRC32 type definition using Add-Type with C#
# Uses IEEE 802.3 polynomial (same as ZIP, PNG, SFV)

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
