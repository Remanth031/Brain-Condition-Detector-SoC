// =============================================================================
// Brain Condition Detector (BCD) SoC - System Constants & Parameters
// Architecture, AMBA AXI4 IP Integration and Biosensor Specification
// =============================================================================

`ifndef BCD_SOC_PKG_VH
`define BCD_SOC_PKG_VH

// Global Bus Parameters
`define AXI_ADDR_WIDTH      32
`define AXI_DATA_WIDTH      32
`define AXI_STRB_WIDTH      (`AXI_DATA_WIDTH / 8)
`define AXI_ID_WIDTH        4
`define AXI_USER_WIDTH      1

// Master IDs
`define MASTER_M0_RISCV     4'd0
`define MASTER_M1_DMA       4'd1
`define MASTER_M2_NPU       4'd2
`define MASTER_M3_SWIN      4'd3
`define MASTER_M4_DISPLAY   4'd4
`define MASTER_M5_JTAG      4'd5

// Slave IDs
`define SLAVE_S_ROM         3'd0
`define SLAVE_S0_SRAM       3'd1
`define SLAVE_S1_LPDDR      3'd2
`define SLAVE_S2_NVM        3'd3
`define SLAVE_S3_SCRATCHPAD 3'd4
`define SLAVE_S4_CSR_BRIDGE 3'd5
`define SLAVE_DECERR        3'd6

// Base Addresses according to Section 4.3 Address Map
`define ADDR_BASE_ROM         32'h0000_0000
`define ADDR_MASK_ROM         32'hFFFF_0000 // 64 KiB
`define ADDR_SIZE_ROM         32'h0001_0000

`define ADDR_BASE_SRAM        32'h1000_0000
`define ADDR_MASK_SRAM        32'hFFF0_0000 // 1 MiB
`define ADDR_SIZE_SRAM        32'h0010_0000

`define ADDR_BASE_SCRATCHPAD  32'h1100_0000
`define ADDR_MASK_SCRATCHPAD  32'hFFE0_0000 // 2 MiB
`define ADDR_SIZE_SCRATCHPAD  32'h0020_0000

`define ADDR_BASE_CSR_BRIDGE  32'h4000_0000
`define ADDR_MASK_CSR_BRIDGE  32'hFFF0_0000 // 1 MiB region covering all CSRs
`define ADDR_SIZE_CSR_BRIDGE  32'h0010_0000

`define ADDR_BASE_NVM         32'h6000_0000
`define ADDR_MASK_NVM         32'hF800_0000 // 128 MiB
`define ADDR_SIZE_NVM         32'h0800_0000

`define ADDR_BASE_LPDDR       32'h8000_0000
`define ADDR_MASK_LPDDR       32'hC000_0000 // up to 1 GiB
`define ADDR_SIZE_LPDDR       32'h4000_0000

// Sub-CSR Cluster Addresses (Section 4.3)
`define CSR_BASE_AFE          32'h4000_0000
`define CSR_BASE_FILTER       32'h4001_0000
`define CSR_BASE_THRESHOLD    32'h4002_0000
`define CSR_BASE_PMU          32'h4003_0000
`define CSR_BASE_DMA          32'h4004_0000
`define CSR_BASE_NPU          32'h4005_0000
`define CSR_BASE_SWIN         32'h4006_0000
`define CSR_BASE_OUTPUT       32'h4007_0000
`define CSR_BASE_SECURITY     32'h4008_0000
`define CSR_BASE_PERIPH       32'h4009_0000

// RTL Threshold Engine Register Offsets (Section 4.4)
`define THRESH_REG_CTRL         8'h00
`define THRESH_REG_STATUS       8'h04
`define THRESH_REG_CH_MASK      8'h08
`define THRESH_REG_LL_THR       8'h0C
`define THRESH_REG_BP_RATIO_THR 8'h10
`define THRESH_REG_ENT_THR      8'h14
`define THRESH_REG_VOTE_NM      8'h18
`define THRESH_REG_HYST_HOLD    8'h1C
`define THRESH_REG_PRETRIG_LEN  8'h20
`define THRESH_REG_IRQ_EN       8'h24
`define THRESH_REG_IRQ_STATUS   8'h28
`define THRESH_REG_WAKE_TARGET  8'h2C

// Edge-AI NPU Register Offsets (Section 4.3 Base 0x4005_0000)
`define NPU_REG_CTRL            8'h00
`define NPU_REG_STATUS          8'h04
`define NPU_REG_WEIGHT_ADDR     8'h08
`define NPU_REG_SCRATCH_ADDR    8'h0C
`define NPU_REG_RESULT_CLASS    8'h10
`define NPU_REG_CONFIDENCE      8'h14
`define NPU_REG_CYCLE_COUNT     8'h18
`define NPU_REG_IRQ_EN          8'h1C

// Swin Transformer Accelerator Register Offsets (Section 4.3 Base 0x4006_0000)
`define SWIN_REG_CTRL           8'h00
`define SWIN_REG_STATUS         8'h04
`define SWIN_REG_WEIGHT_ADDR    8'h08
`define SWIN_REG_TOKEN_ADDR     8'h0C
`define SWIN_REG_SALIENCY_ADDR  8'h10
`define SWIN_REG_RESULT_CLASS   8'h14
`define SWIN_REG_CONFIDENCE     8'h18
`define SWIN_REG_CYCLE_COUNT    8'h1C
`define SWIN_REG_IRQ_EN         8'h20

// PIC / PLIC Interrupt Source Mapping (Section 3.4 & 4.1)
`define IRQ_SRC_RESERVED        3'd0
`define IRQ_SRC_THRESHOLD       3'd1
`define IRQ_SRC_DMA_DONE        3'd2
`define IRQ_SRC_PMU_EVENT       3'd3
`define IRQ_SRC_FIREWALL        3'd4
`define IRQ_SRC_NPU_DONE        3'd5
`define IRQ_SRC_SWIN_DONE       3'd6
`define IRQ_SRC_REPORT_READY    3'd7

// AXI Response Codes
`define AXI_RESP_OKAY   2'b00
`define AXI_RESP_EXOKAY 2'b01
`define AXI_RESP_SLVERR 2'b10
`define AXI_RESP_DECERR 2'b11

// AXI Burst Types
`define AXI_BURST_FIXED 2'b00
`define AXI_BURST_INCR  2'b01
`define AXI_BURST_WRAP  2'b10

`endif // BCD_SOC_PKG_VH
