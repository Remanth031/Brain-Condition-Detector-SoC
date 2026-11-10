#!/usr/bin/env bash
# ==============================================================================
# Brain Condition Detector (BCD) SoC - Verilog Simulation & Build Pipeline (Bash)
# ==============================================================================
# Usage:
#   ./scripts/build_sim.sh all       # Run all 3 testbenches
#   ./scripts/build_sim.sh full      # Run tb_bcd_soc_full_top
#   ./scripts/build_sim.sh axi       # Run tb_bcd_soc_axi
#   ./scripts/build_sim.sh veer      # Run tb_bcd_veer_core
#   ./scripts/build_sim.sh lint      # Static lint/syntax check
#   ./scripts/build_sim.sh clean     # Clean build artifacts
# ==============================================================================

set -e

TARGET="${1:-all}"
SIM="${SIM:-iverilog}"

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WORKSPACE_ROOT"

RTL_DIR="rtl"
TB_DIR="tb"
BUILD_DIR="sim_build"
LOG_DIR="$BUILD_DIR/logs"

mkdir -p "$LOG_DIR"

if [ "$TARGET" = "clean" ]; then
    echo "[CLEAN] Removing build artifacts and logs..."
    rm -rf "$BUILD_DIR" obj_dir *.vcd *.fst *.log *.jou *.pb *.wdb xsim.dir work transcript vsim.wlf
    echo "[CLEAN] Workspace cleaned."
    exit 0
fi

# Discover all 29 RTL sources with bcd_soc_pkg.vh placed first
PKG_SRC="$RTL_DIR/bcd_soc_pkg.vh"
RTL_SRCS="$PKG_SRC $(ls $RTL_DIR/*.v)"

echo "================================================================="
echo "   Brain Condition Detector (BCD) SoC Build Pipeline (Bash)      "
echo "================================================================="
echo "Target:    $TARGET"
echo "Simulator: $SIM"
echo "RTL Dir:   $RTL_DIR (Includes bcd_soc_pkg.vh properly)"
echo "-----------------------------------------------------------------"

run_test() {
    local test_name="$1"
    local tb_file="$2"
    local log_file="$LOG_DIR/$3"
    local pass_pattern="$4"

    echo "[BUILD] Compiling & Running $test_name..."

    if [ "$SIM" = "iverilog" ]; then
        iverilog -g2012 -I$RTL_DIR -Wall -o "$BUILD_DIR/$test_name.out" $RTL_SRCS "$TB_DIR/$tb_file"
        vvp "$BUILD_DIR/$test_name.out" | tee "$log_file"
    elif [ "$SIM" = "verilator" ]; then
        verilator --cc --exe --build -Wall -I$RTL_DIR --top-module "$test_name" \
            $RTL_SRCS "$TB_DIR/$tb_file" -o "$BUILD_DIR/$test_name.out"
        "$BUILD_DIR/$test_name.out" | tee "$log_file"
    elif [ "$SIM" = "xsim" ]; then
        xvlog -sv -i $RTL_DIR $RTL_SRCS "$TB_DIR/$tb_file"
        xelab -top "$test_name" -s "${test_name}_sim"
        xsim "${test_name}_sim" -R | tee "$log_file"
    else
        echo "Error: Unknown simulator $SIM"
        exit 1
    fi

    if grep -q "$pass_pattern" "$log_file"; then
        echo -e "\033[0;32m[PASS] $test_name passed\033[0m"
    else
        echo -e "\033[0;31m[FAIL] $test_name failed\033[0m"
        exit 1
    fi
}

if [ "$TARGET" = "all" ] || [ "$TARGET" = "full" ]; then
    run_test "tb_bcd_soc_full_top" "tb_bcd_soc_full_top.v" "sim_full.log" "ALL FULL-SYSTEM INTEGRATION TESTS PASSED"
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "axi" ]; then
    run_test "tb_bcd_soc_axi" "tb_bcd_soc_axi.v" "sim_axi.log" "Initial Verilog Sanity Complete. Passed:"
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "veer" ]; then
    run_test "tb_bcd_veer_core" "tb_bcd_veer_core.v" "sim_veer.log" "Failed: 0"
fi

if [ "$TARGET" = "lint" ]; then
    echo "[LINT] Validating RTL syntax..."
    if [ "$SIM" = "verilator" ]; then
        verilator --lint-only -Wall -I$RTL_DIR $RTL_SRCS "$TB_DIR/tb_bcd_soc_full_top.v"
    else
        iverilog -tnull -g2012 -I$RTL_DIR $RTL_SRCS "$TB_DIR/tb_bcd_soc_full_top.v"
    fi
    echo -e "\033[0;32m[PASS] Linting completed successfully.\033[0m"
fi

echo "================================================================="
echo " All requested simulation targets completed successfully!"
echo "================================================================="
