#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Performance tests for ReScenePS module.

.DESCRIPTION
    Benchmarks for critical operations to detect performance regressions.
    These tests measure execution time and ensure operations complete within
    acceptable thresholds.

.NOTES
    Performance tests are tagged with 'Performance' and can be run separately:
    Invoke-Pester -Path tests/Performance.tests.ps1 -Tag Performance
#>

BeforeAll {
    Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
    Initialize-TestEnvironment

    $script:tempDir = New-TestTempDirectory -Prefix 'PerfTest'

    # Performance thresholds (in milliseconds)
    # Note: CRC32 uses pure PowerShell implementation which is slower than compiled code
    # but more portable (no external dependencies)
    $script:Thresholds = @{
        ByteArrayCompare1KB    = 10      # 1KB array comparison
        ByteArrayCompare1MB    = 2000    # 1MB array comparison (increased for CI variance)
        EbmlParse1000Elements  = 500     # Parse 1000 EBML elements
        BlockReaderInit        = 50      # BlockReader initialization
        CRC32Calc1MB           = 5000    # CRC32 of 1MB file (pure PowerShell implementation)
    }
}

AfterAll {
    Remove-TestTempDirectory -Path $script:tempDir
}

Describe 'Performance Benchmarks' -Tag 'Performance' {

    Context 'Byte Array Operations' {
        It 'Compares 1KB byte arrays within threshold' {
            InModuleScope 'ReScenePS' -Parameters @{ threshold = $script:Thresholds.ByteArrayCompare1KB } {
                $size = 1024
                $a = [byte[]](0..255 * 4)
                $b = [byte[]](0..255 * 4)

                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                for ($i = 0; $i -lt 100; $i++) {
                    $null = Compare-ByteArray -Array1 $a -Array2 $b
                }
                $stopwatch.Stop()

                $avgMs = $stopwatch.ElapsedMilliseconds / 100
                $avgMs | Should -BeLessOrEqual $threshold -Because "Average compare time should be under ${threshold}ms"
            }
        }

        It 'Compares 1MB byte arrays within threshold' {
            InModuleScope 'ReScenePS' -Parameters @{ threshold = $script:Thresholds.ByteArrayCompare1MB } {
                $size = 1024 * 1024
                $a = [byte[]]::new($size)
                $b = [byte[]]::new($size)
                [System.Random]::new(42).NextBytes($a)
                [Array]::Copy($a, $b, $size)

                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $null = Compare-ByteArray -Array1 $a -Array2 $b
                $stopwatch.Stop()

                $stopwatch.ElapsedMilliseconds | Should -BeLessOrEqual $threshold -Because "1MB compare should complete under ${threshold}ms"
            }
        }
    }

    Context 'EBML Parsing Performance' {
        It 'Parses EBML variable integers efficiently' {
            InModuleScope 'ReScenePS' -Parameters @{ threshold = $script:Thresholds.EbmlParse1000Elements } {
                # Generate test data: 1000 2-byte EBML sizes
                $data = [byte[]]::new(2000)
                for ($i = 0; $i -lt 1000; $i++) {
                    $data[$i * 2] = 0x41     # 2-byte size marker
                    $data[$i * 2 + 1] = 0x00 # Value = 256
                }

                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                for ($i = 0; $i -lt 1000; $i++) {
                    $offset = $i * 2
                    $length = Get-EbmlUIntLength -LengthDescriptor $data[$offset]
                    $value = Get-EbmlUInt -Buffer $data -Offset $offset -ByteCount $length
                }
                $stopwatch.Stop()

                $stopwatch.ElapsedMilliseconds | Should -BeLessOrEqual $threshold -Because "1000 EBML parses should complete under ${threshold}ms"
            }
        }

        It 'Converts byte arrays to hex strings efficiently' {
            InModuleScope 'ReScenePS' {
                $data = [byte[]](0..255)

                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                for ($i = 0; $i -lt 1000; $i++) {
                    $null = ConvertTo-ByteString -Bytes $data
                }
                $stopwatch.Stop()

                # Should complete 1000 conversions in under 5 seconds
                # (PowerShell string operations are slower than native code)
                $stopwatch.ElapsedMilliseconds | Should -BeLessOrEqual 5000
            }
        }
    }

    Context 'File Operations Performance' {
        BeforeAll {
            # Create 1MB test file
            $script:testFile1MB = Join-Path $script:tempDir 'test1mb.bin'
            $data = [byte[]]::new(1024 * 1024)
            [System.Random]::new(42).NextBytes($data)
            [System.IO.File]::WriteAllBytes($script:testFile1MB, $data)
        }

        It 'Finds source file in directory efficiently' {
            InModuleScope 'ReScenePS' -Parameters @{ dir = $script:tempDir } {
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                for ($i = 0; $i -lt 100; $i++) {
                    $null = Find-SourceFile -FileName 'test1mb.bin' -SearchPath $dir
                }
                $stopwatch.Stop()

                # 100 lookups should complete in under 500ms
                $stopwatch.ElapsedMilliseconds | Should -BeLessOrEqual 500
            }
        }
    }

    Context 'CRC32 Performance' {
        BeforeAll {
            # Create test file for CRC benchmarks
            $script:crcTestFile = Join-Path $script:tempDir 'crctest.bin'
            $data = [byte[]]::new(1024 * 1024)  # 1MB
            [System.Random]::new(42).NextBytes($data)
            [System.IO.File]::WriteAllBytes($script:crcTestFile, $data)
        }

        It 'Calculates CRC32 of 1MB file within threshold' {
            InModuleScope 'ReScenePS' -Parameters @{ file = $script:crcTestFile; threshold = $script:Thresholds.CRC32Calc1MB } {
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $null = Get-Crc32 -FilePath $file
                $stopwatch.Stop()

                $stopwatch.ElapsedMilliseconds | Should -BeLessOrEqual $threshold -Because "1MB CRC32 should complete under ${threshold}ms"
            }
        }
    }

    Context 'Memory Usage' {
        It 'Does not leak memory during repeated byte operations' {
            InModuleScope 'ReScenePS' {
                [System.GC]::Collect()
                $startMemory = [System.GC]::GetTotalMemory($true)

                # Perform many operations
                for ($i = 0; $i -lt 1000; $i++) {
                    $a = [byte[]](1..100)
                    $b = [byte[]](1..100)
                    $null = Compare-ByteArray -Array1 $a -Array2 $b
                    $null = ConvertTo-ByteString -Bytes $a
                }

                [System.GC]::Collect()
                $endMemory = [System.GC]::GetTotalMemory($true)

                $memoryGrowth = $endMemory - $startMemory
                # Allow up to 10MB growth (generous to account for GC timing)
                $memoryGrowth | Should -BeLessOrEqual (10 * 1024 * 1024) -Because "Memory should not grow excessively"
            }
        }
    }
}

Describe 'Performance Regression Baseline' -Tag 'Performance', 'Baseline' {
    <#
    .NOTES
        This section documents baseline performance measurements.
        Update these when running on the reference machine.

        Reference Machine: (to be filled in)
        - CPU:
        - RAM:
        - Disk:
        - PowerShell Version:

        Baseline Measurements:
        - ByteArrayCompare1KB:   X ms
        - ByteArrayCompare1MB:   X ms
        - EbmlParse1000Elements: X ms
        - CRC32Calc1MB:          X ms
    #>

    It 'Records baseline measurements' {
        # This test generates baseline measurements for documentation
        $results = @{}

        InModuleScope 'ReScenePS' -Parameters @{ resultsRef = [ref]$results } {
            # 1KB compare
            $a = [byte[]](0..255 * 4)
            $b = [byte[]](0..255 * 4)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt 100; $i++) { $null = Compare-ByteArray -Array1 $a -Array2 $b }
            $sw.Stop()
            $resultsRef.Value['ByteArrayCompare1KB'] = $sw.ElapsedMilliseconds / 100

            # EBML parsing
            $data = [byte[]]::new(2000)
            for ($i = 0; $i -lt 1000; $i++) { $data[$i * 2] = 0x41; $data[$i * 2 + 1] = 0x00 }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt 1000; $i++) {
                $offset = $i * 2
                $length = Get-EbmlUIntLength -LengthDescriptor $data[$offset]
                $null = Get-EbmlUInt -Buffer $data -Offset $offset -ByteCount $length
            }
            $sw.Stop()
            $resultsRef.Value['EbmlParse1000Elements'] = $sw.ElapsedMilliseconds
        }

        Write-Host "`nPerformance Baseline:" -ForegroundColor Cyan
        $results.GetEnumerator() | ForEach-Object {
            Write-Host "  $($_.Key): $($_.Value) ms"
        }

        $true | Should -BeTrue
    }
}
