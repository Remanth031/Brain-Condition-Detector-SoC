# ==============================================================================
# Brain Condition Detector (BCD) SoC - Master Simulation & Build Makefile
# ==============================================================================
# Supported Simulators (override with SIM=<simulator>):
#   - iverilog   : Icarus Verilog (default open-source simulator)
#   - verilator  : Verilator C++ Fast Simulator / Linter
#   - xsim       : AMD/Xilinx Vivado Simulator
#   - vcs        : Synopsys VCS
#   - questa     : Siemens QuestaSim / ModelSim
#
# Usage Examples:
#   make all              # Compile and run all 3 testbenches (default: iverilog)
#   make sim_full         # Run top-level full SoC simulation
#   make sim_axi          # Run 6x6 AXI4 crossbar testbench
#   make sim_veer         # Run VeeR RISC-V core testbench
#   make lint             # Run static syntax and lint checks
#   make clean            # Remove build artifacts and logs
# ==============================================================================

SHELL := /bin/bash

# Simulator configuration
SIM ?= iverilog

# Directory definitions
RTL_DIR   := rtl
TB_DIR    := tb
SIM_DIR   := sim
BUILD_DIR := sim_build
LOG_DIR   := $(BUILD_DIR)/logs

# RTL Headers & Sources (Ensure bcd_soc_pkg.vh is included properly)
PKG_SRC   := $(RTL_DIR)/bcd_soc_pkg.vh
RTL_SRCS  := $(PKG_SRC) $(filter-out $(PKG_SRC), $(wildcard $(RTL_DIR)/*.v))

# Testbench definitions
TB_FULL_SRC := $(TB_DIR)/tb_bcd_soc_full_top.v
TB_AXI_SRC  := $(TB_DIR)/tb_bcd_soc_axi.v
TB_VEER_SRC := $(TB_DIR)/tb_bcd_veer_core.v

# Output executable names
FULL_BIN := $(BUILD_DIR)/tb_full.out
AXI_BIN  := $(BUILD_DIR)/tb_axi.out
VEER_BIN := $(BUILD_DIR)/tb_veer.out

# Log files
FULL_LOG := $(LOG_DIR)/sim_full.log
AXI_LOG  := $(LOG_DIR)/sim_axi.log
VEER_LOG := $(LOG_DIR)/sim_veer.log

# Simulator-specific flags
IV_FLAGS     := -g2012 -I$(RTL_DIR) -Wall
VL_FLAGS     := --lint-only -Wall -I$(RTL_DIR)
XSIM_FLAGS   := -sv -i $(RTL_DIR)
VCS_FLAGS    := -sverilog +incdir+$(RTL_DIR) -full64
QUESTA_FLAGS := -sv +incdir+$(RTL_DIR)

.PHONY: all help init sim_full sim_axi sim_veer lint clean report

# Default target
all: init sim_full sim_axi sim_veer report

# Initialize build directories
init:
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(LOG_DIR)

# ------------------------------------------------------------------------------
# Target: Full SoC Top-Level System Simulation (tb_bcd_soc_full_top)
# ------------------------------------------------------------------------------
sim_full: init
	@echo "================================================================="
	@echo "[SIM] Compiling & Running Full SoC Testbench (SIM=$(SIM))..."
	@echo "================================================================="
ifeq ($(SIM),iverilog)
	iverilog $(IV_FLAGS) -o $(FULL_BIN) $(RTL_SRCS) $(TB_FULL_SRC)
	vvp $(FULL_BIN) | tee $(FULL_LOG)
else ifeq ($(SIM),verilator)
	verilator --cc --exe --build -Wall -I$(RTL_DIR) --top-module tb_bcd_soc_full_top \
		$(RTL_SRCS) $(TB_FULL_SRC) -o $(FULL_BIN)
	$(FULL_BIN) | tee $(FULL_LOG)
else ifeq ($(SIM),xsim)
	xvlog $(XSIM_FLAGS) $(RTL_SRCS) $(TB_FULL_SRC)
	xelab -top tb_bcd_soc_full_top -s full_sim
	xsim full_sim -R | tee $(FULL_LOG)
else ifeq ($(SIM),vcs)
	vcs $(VCS_FLAGS) -o $(FULL_BIN) $(RTL_SRCS) $(TB_FULL_SRC)
	$(FULL_BIN) | tee $(FULL_LOG)
else ifeq ($(SIM),questa)
	vlib $(BUILD_DIR)/work
	vlog -work $(BUILD_DIR)/work $(QUESTA_FLAGS) $(RTL_SRCS) $(TB_FULL_SRC)
	vsim -c -do "run -all; quit -f" -lib $(BUILD_DIR)/work tb_bcd_soc_full_top | tee $(FULL_LOG)
endif
	@grep -q "ALL FULL-SYSTEM INTEGRATION TESTS PASSED SUCCESSFULLY!" $(FULL_LOG) && \
		echo -e "\033[0;32m[PASS] Full SoC Integration Test PASSED\033[0m" || \
		(echo -e "\033[0;31m[FAIL] Full SoC Integration Test FAILED\033[0m" && exit 1)

# ------------------------------------------------------------------------------
# Target: AXI4 Crossbar & Interconnect Simulation (tb_bcd_soc_axi)
# ------------------------------------------------------------------------------
sim_axi: init
	@echo "================================================================="
	@echo "[SIM] Compiling & Running AXI Interconnect Testbench (SIM=$(SIM))..."
	@echo "================================================================="
ifeq ($(SIM),iverilog)
	iverilog $(IV_FLAGS) -o $(AXI_BIN) $(RTL_SRCS) $(TB_AXI_SRC)
	vvp $(AXI_BIN) | tee $(AXI_LOG)
else ifeq ($(SIM),verilator)
	verilator --cc --exe --build -Wall -I$(RTL_DIR) --top-module tb_bcd_soc_axi \
		$(RTL_SRCS) $(TB_AXI_SRC) -o $(AXI_BIN)
	$(AXI_BIN) | tee $(AXI_LOG)
else ifeq ($(SIM),xsim)
	xvlog $(XSIM_FLAGS) $(RTL_SRCS) $(TB_AXI_SRC)
	xelab -top tb_bcd_soc_axi -s axi_sim
	xsim axi_sim -R | tee $(AXI_LOG)
else ifeq ($(SIM),vcs)
	vcs $(VCS_FLAGS) -o $(AXI_BIN) $(RTL_SRCS) $(TB_AXI_SRC)
	$(AXI_BIN) | tee $(AXI_LOG)
else ifeq ($(SIM),questa)
	vlib $(BUILD_DIR)/work
	vlog -work $(BUILD_DIR)/work $(QUESTA_FLAGS) $(RTL_SRCS) $(TB_AXI_SRC)
	vsim -c -do "run -all; quit -f" -lib $(BUILD_DIR)/work tb_bcd_soc_axi | tee $(AXI_LOG)
endif
	@grep -q "Failed: 0" $(AXI_LOG) && \
		echo -e "\033[0;32m[PASS] AXI Crossbar Test PASSED\033[0m" || \
		(echo -e "\033[0;31m[FAIL] AXI Crossbar Test FAILED\033[0m" && exit 1)

# ------------------------------------------------------------------------------
# Target: VeeR RISC-V Core Top Simulation (tb_bcd_veer_core)
# ------------------------------------------------------------------------------
sim_veer: init
	@echo "================================================================="
	@echo "[SIM] Compiling & Running VeeR Core Testbench (SIM=$(SIM))..."
	@echo "================================================================="
ifeq ($(SIM),iverilog)
	iverilog $(IV_FLAGS) -o $(VEER_BIN) $(RTL_SRCS) $(TB_VEER_SRC)
	vvp $(VEER_BIN) | tee $(VEER_LOG)
else ifeq ($(SIM),verilator)
	verilator --cc --exe --build -Wall -I$(RTL_DIR) --top-module tb_bcd_veer_core \
		$(RTL_SRCS) $(TB_VEER_SRC) -o $(VEER_BIN)
	$(VEER_BIN) | tee $(VEER_LOG)
else ifeq ($(SIM),xsim)
	xvlog $(XSIM_FLAGS) $(RTL_SRCS) $(TB_VEER_SRC)
	xelab -top tb_bcd_veer_core -s veer_sim
	xsim veer_sim -R | tee $(VEER_LOG)
else ifeq ($(SIM),vcs)
	vcs $(VCS_FLAGS) -o $(VEER_BIN) $(RTL_SRCS) $(TB_VEER_SRC)
	$(VEER_BIN) | tee $(VEER_LOG)
else ifeq ($(SIM),questa)
	vlib $(BUILD_DIR)/work
	vlog -work $(BUILD_DIR)/work $(QUESTA_FLAGS) $(RTL_SRCS) $(TB_VEER_SRC)
	vsim -c -do "run -all; quit -f" -lib $(BUILD_DIR)/work tb_bcd_veer_core | tee $(VEER_LOG)
endif
	@grep -q "Failed: 0" $(VEER_LOG) && \
		echo -e "\033[0;32m[PASS] VeeR Core Test PASSED\033[0m" || \
		(echo -e "\033[0;31m[FAIL] VeeR Core Test FAILED\033[0m" && exit 1)

# ------------------------------------------------------------------------------
# Target: Static Syntax & Lint Checking (Verilator / Icarus)
# ------------------------------------------------------------------------------
lint: init
	@echo "================================================================="
	@echo "[LINT] Running static syntax & lint check on all 29 RTL files..."
	@echo "================================================================="
ifeq ($(SIM),verilator)
	verilator $(VL_FLAGS) $(RTL_SRCS) $(TB_FULL_SRC)
else
	iverilog -tnull $(IV_FLAGS) $(RTL_SRCS) $(TB_FULL_SRC)
endif
	@echo -e "\033[0;32m[PASS] Lint and syntax validation successful.\033[0m"

# ------------------------------------------------------------------------------
# Target: Summary Report Table
# ------------------------------------------------------------------------------
report:
	@echo ""
	@echo "================================================================="
	@echo "            BCD SoC SIMULATION REGRESSION REPORT                 "
	@echo "================================================================="
	@echo " Simulator Engine : $(SIM)"
	@echo " Total Testbenches: 3 (Full SoC, AXI Crossbar, VeeR Core)"
	@echo " Logs Directory   : $(LOG_DIR)/"
	@echo "-----------------------------------------------------------------"
	@printf " %-30s | %-10s\n" "Testbench Suite" "Result"
	@echo "-----------------------------------------------------------------"
	@if [ -f $(FULL_LOG) ] && grep -q "ALL FULL-SYSTEM INTEGRATION TESTS PASSED SUCCESSFULLY!" $(FULL_LOG); then \
		printf " %-30s | \033[0;32m%-10s\033[0m\n" "tb_bcd_soc_full_top" "PASSED"; \
	else \
		printf " %-30s | \033[0;31m%-10s\033[0m\n" "tb_bcd_soc_full_top" "FAILED/NOT RUN"; \
	fi
	@if [ -f $(AXI_LOG) ] && grep -q "Failed: 0" $(AXI_LOG); then \
		printf " %-30s | \033[0;32m%-10s\033[0m\n" "tb_bcd_soc_axi" "PASSED"; \
	else \
		printf " %-30s | \033[0;31m%-10s\033[0m\n" "tb_bcd_soc_axi" "FAILED/NOT RUN"; \
	fi
	@if [ -f $(VEER_LOG) ] && grep -q "Failed: 0" $(VEER_LOG); then \
		printf " %-30s | \033[0;32m%-10s\033[0m\n" "tb_bcd_veer_core" "PASSED"; \
	else \
		printf " %-30s | \033[0;31m%-10s\033[0m\n" "tb_bcd_veer_core" "FAILED/NOT RUN"; \
	fi
	@echo "================================================================="

# ------------------------------------------------------------------------------
# Target: Clean
# ------------------------------------------------------------------------------
clean:
	@echo "[CLEAN] Removing simulation artifacts, waveforms, and logs..."
	@rm -rf $(BUILD_DIR) obj_dir *.vcd *.fst *.log *.jou *.pb *.wdb xsim.dir work transcript vsim.wlf
	@echo "[CLEAN] Workspace cleaned."

# ------------------------------------------------------------------------------
# Target: Help
# ------------------------------------------------------------------------------
help:
	@echo "================================================================="
	@echo " Brain Condition Detector (BCD) SoC Simulation Build System"
	@echo "================================================================="
	@echo " Available Targets:"
	@echo "   make all              - Run all 3 testbenches & generate report"
	@echo "   make sim_full         - Run tb_bcd_soc_full_top (all 29 RTL files)"
	@echo "   make sim_axi          - Run tb_bcd_soc_axi (6x6 crossbar & memory)"
	@echo "   make sim_veer         - Run tb_bcd_veer_core (VeeR EL2 core wrapper)"
	@echo "   make lint             - Static Verilog syntax & lint validation"
	@echo "   make clean            - Remove all output binaries and logs"
	@echo "   make help             - Display this help message"
	@echo ""
	@echo " Options:"
	@echo "   SIM=iverilog          - Use Icarus Verilog (default)"
	@echo "   SIM=verilator         - Use Verilator"
	@echo "   SIM=xsim              - Use AMD/Xilinx Vivado Simulator"
	@echo "   SIM=vcs               - Use Synopsys VCS"
	@echo "   SIM=questa            - Use Siemens QuestaSim"
	@echo "================================================================="
