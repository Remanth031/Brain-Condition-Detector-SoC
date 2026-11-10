# ==============================================================================
# Brain Condition Detector (BCD) SoC - Firmware Build Script (PowerShell)
# ==============================================================================

Param(
    [string]$ToolchainPrefix = "riscv64-unknown-elf-",
    [switch]$Install
)

$FirmwareDir = $PSScriptRoot
Set-Location $FirmwareDir

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "      BCD SoC RISC-V Firmware Compilation Toolchain             " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

$gcc = "${ToolchainPrefix}gcc"
$objcopy = "${ToolchainPrefix}objcopy"
$objdump = "${ToolchainPrefix}objdump"

# Check for 32-bit prefix fallback
if (-not (Get-Command $gcc -ErrorAction SilentlyContinue)) {
    if (Get-Command "riscv32-unknown-elf-gcc" -ErrorAction SilentlyContinue) {
        $ToolchainPrefix = "riscv32-unknown-elf-"
        $gcc = "${ToolchainPrefix}gcc"
        $objcopy = "${ToolchainPrefix}objcopy"
        $objdump = "${ToolchainPrefix}objdump"
    }
}

if (-not (Get-Command $gcc -ErrorAction SilentlyContinue)) {
    Write-Host "[NOTE] RISC-V GCC toolchain ($gcc) not found in system PATH." -ForegroundColor Yellow
    Write-Host "To install a pre-built RISC-V toolchain on Windows:" -ForegroundColor Yellow
    Write-Host "  1. Download xPack GNU RISC-V Embedded GCC: https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack"
    Write-Host "  2. Or install via Scoop / Chocolatey: 'scoop install riscv-none-elf-gcc'"
    Write-Host "`nThe pre-assembled verification firmware image is maintained at 'mem/boot.hex'." -ForegroundColor Green
    exit 0
}

Write-Host "Using compiler: $gcc" -ForegroundColor Green

# 1. Compile Assembly startup
& $gcc -march=rv32imc -mabi=ilp32 -O2 -ffreestanding -nostdlib -c boot.S -o boot.o
if ($LASTEXITCODE -ne 0) { Write-Error "Assembly compilation failed"; exit 1 }

# 2. Compile C main
& $gcc -march=rv32imc -mabi=ilp32 -O2 -Wall -ffreestanding -nostdlib -I. -c main.c -o main.o
if ($LASTEXITCODE -ne 0) { Write-Error "C compilation failed"; exit 1 }

# 3. Link with link.ld
& $gcc -march=rv32imc -mabi=ilp32 -T link.ld -nostartfiles "-Wl,--gc-sections" boot.o main.o -o boot.elf
if ($LASTEXITCODE -ne 0) { Write-Error "Linking failed"; exit 1 }

# 4. Generate Binary & Disassembly
& $objcopy -O binary boot.elf boot.bin
& $objdump -d -S boot.elf > boot.dump

# 5. Convert binary to Verilog readmemh format
$bytes = [System.IO.File]::ReadAllBytes("$FirmwareDir\boot.bin")
$lines = @()
for ($i = 0; $i -lt $bytes.Length; $i += 4) {
    $word = [System.BitConverter]::ToUInt32($bytes, $i)
    $lines += ("{0:x8}" -f $word)
}
$lines | Out-File -FilePath "$FirmwareDir\boot.hex" -Encoding ASCII

Write-Host "[SUCCESS] Firmware compiled: boot.elf, boot.bin, boot.hex, boot.dump" -ForegroundColor Green

if ($Install) {
    Copy-Item "$FirmwareDir\boot.hex" "..\mem\boot.hex" -Force
    Write-Host "[INSTALLED] Copied firmware to ..\mem\boot.hex" -ForegroundColor Green
}
