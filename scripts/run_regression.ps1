# ==============================================================================
# Brain Condition Detector (BCD) SoC - Automated Regression Runner
# ==============================================================================
Param(
    [string]$Suite = "all" # Options: all, uvm, soc, veer, ip
)

$ErrorActionPreference = "Stop"
$WorkspaceRoot = Split-Path -Parent $PSScriptRoot
$SimDir = Join-Path $WorkspaceRoot "sim"
$CscPath = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "      Brain Condition Detector (BCD) SoC Verification Suite      " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Root Directory: $WorkspaceRoot"
Write-Host "C# Compiler:   $CscPath"
Write-Host "Selected Suite: $Suite`n"

function Run-Suite([string[]]$csFiles, [string]$dllFile, [string]$entryClass, [string]$entryMethod, [string]$reportFile) {
    $csFullPaths = $csFiles | ForEach-Object { Join-Path $SimDir $_ }
    $dllFullPath = Join-Path $SimDir $dllFile
    $reportFullPath = Join-Path $SimDir $reportFile

    Write-Host "[BUILD] Compiling $($csFiles -join ', ') -> $dllFile..." -ForegroundColor Yellow
    & $CscPath /t:library /optimize+ /out:$dllFullPath $csFullPaths
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Compilation failed for $dllFile"
        return
    }

    Write-Host "[EXEC] Running $entryClass.$entryMethod()..." -ForegroundColor Green
    $bytes = [System.IO.File]::ReadAllBytes($dllFullPath)
    $assembly = [System.Reflection.Assembly]::Load($bytes)
    $type = $assembly.GetType($entryClass)
    $method = $type.GetMethod($entryMethod)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = $method.Invoke($null, @())
    $sw.Stop()

    Write-Host "[REPORT] Execution completed in $($sw.ElapsedMilliseconds) ms" -ForegroundColor Cyan
    if (Test-Path $reportFullPath) {
        Get-Content $reportFullPath | Select-Object -First 25 | Write-Host
    }
    Write-Host "-----------------------------------------------------------------`n"
}

$AllSources = @(
    "AxiSimVerification.cs",
    "VeerCoreSimVerification.cs",
    "AllIpBlocksSimVerification.cs",
    "FullSocSystemVerification.cs",
    "UvmComprehensiveVerification.cs"
)

if ($Suite -eq "all" -or $Suite -eq "soc") {
    Run-Suite @("AxiSimVerification.cs", "VeerCoreSimVerification.cs", "AllIpBlocksSimVerification.cs", "FullSocSystemVerification.cs") "FullSocSim.dll" "BcdFullSocVerification.FullSocTestHarness" "RunAllTests" "full_soc_verification_report.txt"
}

if ($Suite -eq "all" -or $Suite -eq "uvm") {
    Run-Suite $AllSources "UvmVerification.dll" "BcdUvmVerification.UvmTestHarness" "RunAllTests" "uvm_10k_verification_report.txt"
}

Write-Host "All requested test suites executed successfully!" -ForegroundColor Green
