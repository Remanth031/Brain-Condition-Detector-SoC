// ==============================================================================
// Brain Condition Detector (BCD) SoC - VeeR EL2 Static Parameter Values
// ==============================================================================
`ifndef EL2_PARAM_VH
`define EL2_PARAM_VH

parameter el2_param_t pt = '{
    LSU_BUS_TAG      : 4'd4,
    IFU_BUS_TAG      : 3'd3,
    SB_BUS_TAG       : 1'd1,
    DMA_BUS_TAG      : 1'd1,
    DMA_BUF_DEPTH    : 3'd4,
    PIC_TOTAL_INT    : 8'd8,
    ICCM_BITS        : 5'd16,
    DCCM_BITS        : 5'd16,
    DCCM_FDATA_WIDTH : 6'd39,
    ICACHE_NUM_WAYS  : 2'd2,
    ICACHE_BANKS_WAY : 2'd2
};

`endif // EL2_PARAM_VH
