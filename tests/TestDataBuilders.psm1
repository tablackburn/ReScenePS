<#
.SYNOPSIS
    Test data builder functions for ReScenePS tests.

.DESCRIPTION
    Provides helper functions to generate synthetic MKV, SRS, and SRR files
    with specific characteristics for testing code paths that require
    complex binary file structures.
#>

function New-TestMkvWithLacing {
    <#
    .SYNOPSIS
        Create a minimal MKV file with a SimpleBlock using specified lacing type.

    .PARAMETER OutputPath
        Path where the MKV file will be created.

    .PARAMETER LacingType
        Lacing type: 0=None, 1=Xiph, 2=Fixed, 3=EBML

    .PARAMETER TrackNumber
        Track number to use in the SimpleBlock (default: 1)

    .PARAMETER FrameData
        Array of byte arrays, each representing a frame's data.
        For no lacing, only first frame is used.

    .OUTPUTS
        Returns the path to the created file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [ValidateRange(0, 3)]
        [int]$LacingType,

        [int]$TrackNumber = 1,

        [byte[][]]$FrameData = @(
            [byte[]]@(0x01, 0x02, 0x03, 0x04, 0x05),
            [byte[]]@(0x06, 0x07, 0x08, 0x09, 0x0A),
            [byte[]]@(0x0B, 0x0C, 0x0D, 0x0E, 0x0F)
        )
    )

    $ms = [System.IO.MemoryStream]::new()
    $bw = [System.IO.BinaryWriter]::new($ms)

    # EBML Header (ID: 0x1A45DFA3)
    $bw.Write([byte[]]@(0x1A, 0x45, 0xDF, 0xA3))
    $ebmlContent = [byte[]]@(
        0x42, 0x86, 0x81, 0x01,  # EBMLVersion = 1
        0x42, 0xF7, 0x81, 0x01,  # EBMLReadVersion = 1
        0x42, 0xF2, 0x81, 0x04,  # EBMLMaxIDLength = 4
        0x42, 0xF3, 0x81, 0x08   # EBMLMaxSizeLength = 8
    )
    $bw.Write([byte](0x80 -bor $ebmlContent.Length))
    $bw.Write($ebmlContent)

    # Segment (ID: 0x18538067) - use unknown size
    $bw.Write([byte[]]@(0x18, 0x53, 0x80, 0x67))
    $bw.Write([byte[]]@(0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))

    # Cluster (ID: 0x1F43B675)
    $bw.Write([byte[]]@(0x1F, 0x43, 0xB6, 0x75))

    # Build cluster content
    $clusterMs = [System.IO.MemoryStream]::new()
    $clusterBw = [System.IO.BinaryWriter]::new($clusterMs)

    # Timecode (ID: 0xE7)
    $clusterBw.Write([byte]0xE7)
    $clusterBw.Write([byte]0x81)  # size = 1
    $clusterBw.Write([byte]0x00)  # timecode = 0

    # SimpleBlock (ID: 0xA3)
    $clusterBw.Write([byte]0xA3)

    # Build SimpleBlock content
    $blockMs = [System.IO.MemoryStream]::new()
    $blockBw = [System.IO.BinaryWriter]::new($blockMs)

    # Track number (VINT encoded) - for track 1, it's 0x81
    $blockBw.Write([byte](0x80 -bor $TrackNumber))

    # Timecode (2 bytes, big-endian)
    $blockBw.Write([byte]0x00)
    $blockBw.Write([byte]0x00)

    # Flags byte: bits 1-2 are lacing type
    $flags = [byte](($LacingType -band 0x03) -shl 1)
    $blockBw.Write($flags)

    # Lacing data
    if ($LacingType -eq 0) {
        # No lacing - just write first frame
        $blockBw.Write($FrameData[0])
    }
    elseif ($LacingType -eq 1) {
        # Xiph lacing
        $frameCount = $FrameData.Count
        $blockBw.Write([byte]($frameCount - 1))  # Frame count - 1

        # Write frame sizes (except last)
        for ($i = 0; $i -lt ($frameCount - 1); $i++) {
            $size = $FrameData[$i].Length
            while ($size -ge 255) {
                $blockBw.Write([byte]255)
                $size -= 255
            }
            $blockBw.Write([byte]$size)
        }

        # Write all frame data
        foreach ($frame in $FrameData) {
            $blockBw.Write($frame)
        }
    }
    elseif ($LacingType -eq 2) {
        # Fixed-size lacing - all frames must be same size
        $frameCount = $FrameData.Count
        $blockBw.Write([byte]($frameCount - 1))

        # Write all frame data (sizes are implicit)
        foreach ($frame in $FrameData) {
            $blockBw.Write($frame)
        }
    }
    elseif ($LacingType -eq 3) {
        # EBML lacing
        $frameCount = $FrameData.Count
        $blockBw.Write([byte]($frameCount - 1))

        # First frame size as EBML VINT
        $firstSize = $FrameData[0].Length
        if ($firstSize -lt 127) {
            $blockBw.Write([byte](0x80 -bor $firstSize))
        }
        else {
            # 2-byte VINT for sizes 127-16383
            $blockBw.Write([byte](0x40 -bor ($firstSize -shr 8)))
            $blockBw.Write([byte]($firstSize -band 0xFF))
        }

        # Subsequent frame sizes as signed deltas
        $prevSize = $firstSize
        for ($i = 1; $i -lt ($frameCount - 1); $i++) {
            $delta = $FrameData[$i].Length - $prevSize
            # Encode as signed EBML VINT (simplified: use 1-byte with bias of 0x3F)
            $encoded = $delta + 0x3F
            if ($encoded -ge 0 -and $encoded -lt 0x7F) {
                $blockBw.Write([byte](0x80 -bor $encoded))
            }
            else {
                # 2-byte encoding
                $encoded = $delta + 0x1FFF
                $blockBw.Write([byte](0x40 -bor (($encoded -shr 8) -band 0x3F)))
                $blockBw.Write([byte]($encoded -band 0xFF))
            }
            $prevSize = $FrameData[$i].Length
        }

        # Write all frame data
        foreach ($frame in $FrameData) {
            $blockBw.Write($frame)
        }
    }

    $blockBw.Flush()
    $blockContent = $blockMs.ToArray()
    $blockBw.Dispose()
    $blockMs.Dispose()

    # Write SimpleBlock size and content
    if ($blockContent.Length -lt 127) {
        $clusterBw.Write([byte](0x80 -bor $blockContent.Length))
    }
    else {
        # 2-byte size
        $clusterBw.Write([byte](0x40 -bor ($blockContent.Length -shr 8)))
        $clusterBw.Write([byte]($blockContent.Length -band 0xFF))
    }
    $clusterBw.Write($blockContent)

    $clusterBw.Flush()
    $clusterContent = $clusterMs.ToArray()
    $clusterBw.Dispose()
    $clusterMs.Dispose()

    # Write cluster size and content
    if ($clusterContent.Length -lt 127) {
        $bw.Write([byte](0x80 -bor $clusterContent.Length))
    }
    else {
        # 2-byte size
        $bw.Write([byte](0x40 -bor ($clusterContent.Length -shr 8)))
        $bw.Write([byte]($clusterContent.Length -band 0xFF))
    }
    $bw.Write($clusterContent)

    $bw.Flush()
    [System.IO.File]::WriteAllBytes($OutputPath, $ms.ToArray())

    $bw.Dispose()
    $ms.Dispose()

    return $OutputPath
}

Export-ModuleMember -Function New-TestMkvWithLacing
