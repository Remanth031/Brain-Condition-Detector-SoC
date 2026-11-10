// ==============================================================================
// Brain Condition Detector (BCD) SoC - VeeR EL2 Parameter Struct Definition
// ==============================================================================
`ifndef EL2_PDEF_VH
`define EL2_PDEF_VH

typedef struct packed {
    logic [3:0]  LSU_BUS_TAG;
    logic [2:0]  IFU_BUS_TAG;
    logic [0:0]  SB_BUS_TAG;
    logic [0:0]  DMA_BUS_TAG;
    logic [2:0]  DMA_BUF_DEPTH;
    logic [7:0]  PIC_TOTAL_INT;
    logic [4:0]  ICCM_BITS;
    logic [4:0]  DCCM_BITS;
    logic [5:0]  DCCM_FDATA_WIDTH;
    logic [1:0]  ICACHE_NUM_WAYS;
    logic [1:0]  ICACHE_BANKS_WAY;
} el2_param_t;

`endif // EL2_PDEF_VH
