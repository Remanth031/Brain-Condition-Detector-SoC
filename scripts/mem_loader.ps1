# ==============================================================================
# Brain Condition Detector (BCD) SoC - Memory Loader & Hex Inspector (PowerShell)
# ==============================================================================
# Usage:
#   .\scripts\mem_loader.ps1 -Inspect mem\boot.hex
#   .\scripts\mem_loader.ps1 -Inspect mem\nvm.hex
#   .\scripts\mem_loader.ps1 -Inspect mem\lpddr.hex
#   .\scripts\mem_loader.ps1 -GenerateSample
# ==============================================================================

Param(
    [string]$Inspect = "",
    [switch]$Validate,
    [switch]$GenerateSample
)

$WorkspaceRoot = Split-Path -Parent $PSScriptRoot
Set-Location $WorkspaceRoot

function Test-MemoryFiles() {
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host " Brain Condition Detector (BCD) Memory File Validation Suite" -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ("{0,-20} | {1,-10} | {2,-10} | {3,-10} | {4}" -f "File Name", "Words", "Size (Bytes)", "Magic Tag", "Status")
    Write-Host "-------------------------------------------------------------------------------------"

    $files = @(
        @{ Path = "mem\boot.hex";       ExpectedTag = "0x62636431"; TagName = "bcd1"; ExpectedSize = 28 },
        @{ Path = "mem\sram.mem";       ExpectedTag = "0x50415431"; TagName = "PAT1"; ExpectedSize = 20 },
        @{ Path = "mem\scratchpad.hex"; ExpectedTag = "0x53504144"; TagName = "SPAD"; ExpectedSize = 12 },
        @{ Path = "mem\nvm.hex";        ExpectedTag = "0x4545474E"; TagName = "EEGN"; ExpectedSize = 25 },
        @{ Path = "mem\lpddr.hex";      ExpectedTag = "0x5357494E"; TagName = "SWIN"; ExpectedSize = 21 }
    )

    $allPassed = $true
    foreach ($entry in $files) {
        $p = $entry.Path
        if (-not (Test-Path $p)) {
            Write-Host ("{0,-20} | {1,-10} | {2,-10} | {3,-10} | [MISSING]" -f $p, "0", "0", "N/A") -ForegroundColor Red
            $allPassed = $false
            continue
        }

        $lines = Get-Content $p
        $words = @()
        foreach ($line in $lines) {
            $t = $line.Trim()
            if ($t.Contains("//")) { $t = ($t -split "//", 2)[0].Trim() }
            if ([string]::IsNullOrWhiteSpace($t) -or $t.StartsWith("@")) { continue }
            $toks = $t -split "\s+"
            foreach ($tok in $toks) {
                if ($tok.Length -ge 8) {
                    try {
                        $w = [Convert]::ToUInt32($tok, 16)
                        $words += $w
                    } catch {}
                }
            }
        }

        $wordCount = $words.Count
        $byteSize = $wordCount * 4
        $firstWordHex = if ($words.Count -gt 0) { "0x{0:X8}" -f $words[0] } else { "N/A" }
        $tagOk = ($firstWordHex -eq $entry.ExpectedTag)
        $status = if ($tagOk) { "[PASSED]" } else { "[TAG MISMATCH]" }
        $color = if ($tagOk) { "Green" } else { "Red" }

        if (-not $tagOk) { $allPassed = $false }
        Write-Host ("{0,-20} | {1,-10} | {2,-10} | {3,-10} | {4}" -f (Split-Path -Leaf $p), $wordCount, $byteSize, $entry.TagName, $status) -ForegroundColor $color
    }

    Write-Host "=================================================================" -ForegroundColor Cyan
    if ($allPassed) {
        Write-Host ">>> ALL MEMORY INITIALIZATION FILES VALIDATED SUCCESSFULLY! <<<`n" -ForegroundColor Green
    } else {
        Write-Host ">>> MEMORY INITIALIZATION VALIDATION DETECTED ISSUES! <<<`n" -ForegroundColor Red
    }
}

function Show-HexInspection([string]$filePath) {
    if (-not (Test-Path $filePath)) {
        Write-Error "File not found: $filePath"
        return
    }

    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host " Memory Inspection: $filePath" -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ("{0,-12} | {1,-10} | {2}" -f "Address", "Hex Value", "Annotation / Assembly")
    Write-Host "-----------------------------------------------------------------"

    $lines = Get-Content $filePath
    $addr = 0

    foreach ($line in $lines) {
        $comment = ""
        if ($line.Contains("//")) {
            $parts = $line -split "//", 2
            $tokenStr = $parts[0].Trim()
            $comment = $parts[1].Trim()
        } else {
            $tokenStr = $line.Trim()
        }

        if ([string]::IsNullOrWhiteSpace($tokenStr)) { continue }

        $tokens = $tokenStr -split "\s+"
        foreach ($tok in $tokens) {
            if ($tok.StartsWith("@")) {
                $addr = [Convert]::ToInt32($tok.Substring(1), 16)
                continue
            }
            try {
                $val = [Convert]::ToUInt32($tok, 16)
                $byteAddr = $addr * 4
                $annotation = if ($comment -ne "") { $comment } else { "" }
                Write-Host ("0x{0:X8}   | 0x{1:X8} | {2}" -f $byteAddr, $val, $annotation)
                $addr++
            } catch {
                # Ignore non-hex token
            }
        }
    }
    Write-Host "=================================================================`n"
}

if ($Validate) {
    Test-MemoryFiles
} elseif ($Inspect -ne "") {
    Show-HexInspection $Inspect
} else {
    Write-Host "Inspecting default SoC memory load files..." -ForegroundColor Yellow
    Show-HexInspection "mem\boot.hex"
    Show-HexInspection "mem\sram.mem"
    Show-HexInspection "mem\nvm.hex"
    Show-HexInspection "mem\lpddr.hex"
}
