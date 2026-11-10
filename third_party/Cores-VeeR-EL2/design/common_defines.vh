// ==============================================================================
// Brain Condition Detector (BCD) SoC - VeeR EL2 RISC-V Configuration Defines
// Target Configuration: AXI4 Bus Master, RV32IMC, Reset Vector 0x0000_0000 (Boot ROM)
// ==============================================================================
`ifndef COMMON_DEFINES_VH
`define COMMON_DEFINES_VH

`define RV_BUILD_AXI4 1
`define RV_RESET_VEC 32'h0000_0000
`define RV_NMI_VEC 32'h0000_0100
`define RV_XLEN 32
`define RV_PIC_TOTAL_INT 8

// AXI Bus ID and Tag Widths
`define RV_LSU_BUS_TAG 4
`define RV_IFU_BUS_TAG 3
`define RV_SB_BUS_TAG 1
`define RV_DMA_BUS_TAG 1
`define RV_DMA_BUF_DEPTH 4

// Tightly Coupled Memories (TCM)
`define RV_ICCM_ENABLE 1
`define RV_ICCM_BITS 16
`define RV_ICCM_NUM_BANKS 4
`define RV_ICCM_SIZE 64
`define RV_ICCM_SADR 32'h2000_0000

`define RV_DCCM_ENABLE 1
`define RV_DCCM_BITS 16
`define RV_DCCM_NUM_BANKS 4
`define RV_DCCM_SIZE 64
`define RV_DCCM_SADR 32'h2001_0000
`define RV_DCCM_FDATA_WIDTH 39

// Instruction Cache
`define RV_ICACHE_ENABLE 1
`define RV_ICACHE_NUM_WAYS 2
`define RV_ICACHE_BANKS_WAY 2
`define RV_ICACHE_SIZE 16

// Branch Predictor
`define RV_BTB_ENABLE 1
`define RV_BTB_SIZE 32
`define RV_BHT_ENABLE 1
`define RV_BHT_SIZE 256
`define RV_RET_STACK_SIZE 4

`endif // COMMON_DEFINES_VH
