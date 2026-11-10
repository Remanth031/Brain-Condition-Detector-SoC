# Brain Condition Detector (BCD) SoC - FPGA & ASIC Implementation Flow

This guide details the complete physical implementation, timing closure, and bitstream programming flow for the **Brain Condition Detector (BCD) SoC** targeting AMD/Xilinx FPGAs and standard ASIC fabrication processes.

---

## 🎯 Target Platforms & Specifications

### 1. Recommended FPGA Prototyping Platform
* **Device**: AMD / Xilinx Zynq-7000 SoC (`XC7Z020-CLG400-1`)
* **Reference Development Boards**: 
  * Digilent / TUL PYNQ-Z2
  * Avnet ZedBoard
  * Xilinx ZC702
* **Alternative High-Capacity Target**: 
  * AMD Kria KV260 Vision AI Starter Kit (`xck26-sfvc784-2LV-c`)
  * Xilinx ZCU102 UltraScale+ (`xczu9eg-ffvb1156-2-e`)

### 2. Estimated Resource Utilization Budget (`XC7Z020`)
| Resource Type | Available on XC7Z020 | BCD SoC Estimated | Utilization (%) |
| :--- | :---: | :---: | :---: |
| **LUT (Logic)** | 53,200 | ~32,400 | 60.9% |
| **FF (Flip-Flops)** | 106,400 | ~41,800 | 39.3% |
| **BRAM (36Kb Blocks)** | 140 | 56 | 40.0% |
| **DSP48E1 Slices** | 220 | 88 | 40.0% |
| **BUFG (Clock Buffers)** | 32 | 4 | 12.5% |

### 3. ASIC Manufacturing Target (Pre-Silicon Tapeout)
* **Process Node**: TSMC 28nm HPC+ / GlobalFoundries 22FDX / SkyWater 130nm (Efabless Open MPW)
* **Standard Cell Library**: 9-track Ultra-Low Leakage (ULL) Multi-Vt
* **Die Area Estimate**: 3.2 mm² @ 28nm (core logic + SRAM macros + dual AI accelerators)
* **Power Budget**: 
  * **Active Monitoring Mode**: < 45 mW
  * **Standby / Sleep Mode**: < 380 µW

---

## 🛠️ Required Toolchain

* **FPGA Synthesis & Bitstream**: 
  * AMD Vivado ML Standard or Enterprise (v2020.2 through v2024.1+)
* **ASIC Synthesis & PnR**: 
  * Synopsys Design Compiler (DC-NXT) / IC Compiler II (ICC2)
  * Cadence Genus Synthesis / Innovus Implementation
  * OpenLane / Yosys / OpenROAD (Open-source SkyWater 130nm)
* **Hardware Programming**:
  * Vivado Hardware Manager + Digilent JTAG-HS2 / HS3 Cable

---

## ⚡ Clock Tree & Timing Architecture

```mermaid
flowchart LR
    OSC["100 MHz Oscillator"] --> MMCM["FPGA MMCM / PLL"]
    MMCM -->|100 MHz (10.0 ns)| CLK_AO["clk_ao (Always-On Core & AI Accelerators)"]
    MMCM -->|4.096 MHz (244.1 ns)| CLK_ADC["clk_adc (Biopotential AFE Sampling)"]

    subgraph CDC_FIFO["Clock Domain Crossing (CDC)"]
        CLK_ADC --> FIFO_WR["ip_dsp_async_fifo (Write Domain)"]
        CLK_AO --> FIFO_RD["ip_dsp_async_fifo (Read Domain)"]
    end
```

* **Always-On Core Clock (`clk_ao`)**: 100 MHz (Period: 10.000 ns, 50% duty cycle) drives the VeeR RISC-V core, 6x6 AXI4 Crossbar, Edge-AI NPU, and Swin Transformer Engine.
* **Biopotential Sensor Clock (`clk_adc`)**: 4.096 MHz (Period: 244.140 ns) drives the 24-bit 64-channel deserializer and deframer.
* **CDC Boundary**: Synchronized using Gray-code dual-clock asynchronous pointers inside [`rtl/ip_dsp_async_fifo.v`](file:///c:/Users/budha/OneDrive/Documents/brain_project/rtl/ip_dsp_async_fifo.v).

---

## 📌 Pinout & Physical Mapping (Zynq-7000 / PYNQ-Z2)

| Port Name | Direction | Width | Pin Location | I/O Standard | Description |
| :--- | :---: | :---: | :---: | :---: | :--- |
| `clk_ao` | Input | 1 | `H16` | LVCMOS33 | 100 MHz Global Oscillator Clock |
| `clk_adc` | Input | 1 | `K17` | LVCMOS33 | 4.096 MHz Medical ADC Clock |
| `rst_ao_n` | Input | 1 | `D19` | LVCMOS33 | Active-Low Reset (Button 0) |
| `rst_adc_n` | Input | 1 | `D20` | LVCMOS33 | Active-Low Reset (Button 1) |
| `firewall_en` | Input | 1 | `M20` | LVCMOS33 | Security Firewall Enable (Switch 0) |
| `production_mode` | Input | 1 | `M19` | LVCMOS33 | JTAG Lockdown Mode (Switch 1) |
| `cpu_halt_req` | Input | 1 | `L19` | LVCMOS33 | PMU Core Halt Request (Button 2) |
| `cpu_run_req` | Input | 1 | `R19` | LVCMOS33 | PMU Core Run Request (Button 3) |
| `system_alarm_irq` | Output | 1 | `R14` | LVCMOS33 | Hardware Emergency Alarm (Red LED 0) |
| `clinical_event_label[0]` | Output | 1 | `M14` | LVCMOS33 | Diagnostic Code Bit 0 (LED 1) |
| `clinical_event_label[1]` | Output | 1 | `M15` | LVCMOS33 | Diagnostic Code Bit 1 (LED 2) |
| `clinical_event_label[2]` | Output | 1 | `G14` | LVCMOS33 | Diagnostic Code Bit 2 (LED 3) |
| `clinical_event_label[3]` | Output | 1 | `D18` | LVCMOS33 | Diagnostic Code Bit 3 (LED 4) |
| `compressed_valid` | Output | 1 | `P14` | LVCMOS33 | Rice Compressed Word Ready (LED 5) |
| `host_pixel_ready` | Output | 1 | `N16` | LVCMOS33 | Imaging Ingest Backpressure Flag |
| `jtag_cmd_done` | Output | 1 | `L15` | LVCMOS33 | JTAG Transaction Done Acknowledge |

---

## 🚀 Execution Instructions

### Step 1: Run Vivado Batch Synthesis & Bitstream Generation
From the project root directory, run:
```bash
# Using default Zynq-7000 XC7Z020:
vivado -mode batch -source synth.tcl

# Or targeting a different FPGA (e.g. Artix-7 or Kria KV260):
vivado -mode batch -source synth.tcl -tclargs xc7a100tcsg324-1
vivado -mode batch -source synth.tcl -tclargs xck26-sfvc784-2LV-c
```

### Step 2: Memory File Association in Vivado
For FPGA BRAM initialization:
* In Vivado, `$readmemh` targets (`mem/boot.hex`, `mem/sram.mem`, `mem/nvm.hex`, `mem/lpddr.hex`, `mem/scratchpad.hex`) are automatically synthesized into block RAM (`RAMB36E1`/`RAMB18E1`) initial states (`INIT_xx` attributes) during logic elaboration.
* Memory initialization files can also be inspected and validated prior to synthesis:
  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts\mem_loader.ps1 -Validate
  ```

### Step 3: Review Generated Reports
The script automatically generates implementation reports in `reports/`:
* `reports/timing_summary.rpt`: Timing closure sign-off (setup/hold slack).
* `reports/utilization.rpt`: Hierarchical logic and memory breakdown.
* `reports/power.rpt`: Estimated dynamic and static thermal dissipation.
* `reports/drc.rpt`: Design Rule Checks.

### Step 4: Program Bitstream to FPGA Board
1. Power on your development board and connect the USB-JTAG cable.
2. Launch Vivado Hardware Manager:
   ```bash
   vivado -mode tcl
   ```
3. Execute the programming commands:
   ```tcl
   open_hw_manager
   connect_hw_server
   open_hw_target
   set_property PROGRAM.FILE {build_synth/bcd_soc_full_top.bit} [current_hw_device]
   program_hw_devices [current_hw_device]
   puts "FPGA successfully programmed with BCD SoC Bitstream!"
   ```

---

## 🏭 ASIC Flow (Synopsys / OpenLane)
For ASIC gate-level synthesis:
* Pass the standard SDC constraints file: [`fpga/constraints/bcd_soc_asic.sdc`](file:///c:/Users/budha/OneDrive/Documents/brain_project/fpga/constraints/bcd_soc_asic.sdc)
* In Synopsys Design Compiler:
  ```tcl
  read_file -format verilog {rtl/filelist.f}
  current_design bcd_soc_full_top
  source fpga/constraints/bcd_soc_asic.sdc
  compile_ultra -gate_clock -no_autoungroup
  report_timing -significant_digits 3 > reports/asic_timing.rpt
  report_area -hierarchy > reports/asic_area.rpt
  write_file -format verilog -hierarchy -output netlist/bcd_soc_netlist.v
  ```
