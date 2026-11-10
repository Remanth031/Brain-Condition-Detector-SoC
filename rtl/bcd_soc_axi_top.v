// =============================================================================
// Brain Condition Detector (BCD) SoC - Top-Level AXI Interconnection Fabric
// Integrates 6 AXI4 Masters, 6x6 AXI4 Crossbar, AXI Firewall, AXI4-Lite Bridge,
// Boot ROM, SRAM, Scratchpads, CSR Cluster (with RTL Threshold Engine), NVM, and LPDDR.
// =============================================================================

`include "bcd_soc_pkg.vh"

module bcd_soc_axi_top #(
    parameter ADDR_WIDTH          = 32,
    parameter DATA_WIDTH          = 32,
    parameter STRB_WIDTH          = (DATA_WIDTH / 8),
    parameter ID_WIDTH            = 4,
    parameter BOOT_HEX_FILE       = "",
    parameter SRAM_MEM_FILE       = "",
    parameter SCRATCHPAD_HEX_FILE = "",
    parameter NVM_HEX_FILE        = "",
    parameter LPDDR_HEX_FILE      = ""
)(
    input  wire                   aclk,
    input  wire                   aresetn,

    // Firewall & Mode Controls
    input  wire                   firewall_en,
    input  wire                   production_mode,

    // -------------------------------------------------------------------------
    // Master Trigger Command Ports (for TB / CPU / System Simulation)
    // -------------------------------------------------------------------------
    // M0: RISC-V Management Core
    input  wire                   m0_cmd_start,
    input  wire                   m0_cmd_is_write,
    input  wire [ADDR_WIDTH-1:0]  m0_cmd_addr,
    input  wire [7:0]             m0_cmd_len,
    input  wire [3:0]             m0_cmd_qos,
    input  wire [DATA_WIDTH-1:0]  m0_cmd_wdata,
    input  wire [STRB_WIDTH-1:0]  m0_cmd_wstrb,
    output wire                   m0_cmd_done,
    output wire [1:0]             m0_cmd_resp,
    output wire [DATA_WIDTH-1:0]  m0_cmd_rdata,

    // M1: AXI DMA (S2MM / MM2S)
    input  wire                   m1_cmd_start,
    input  wire                   m1_cmd_is_write,
    input  wire [ADDR_WIDTH-1:0]  m1_cmd_addr,
    input  wire [7:0]             m1_cmd_len,
    input  wire [3:0]             m1_cmd_qos,
    input  wire [DATA_WIDTH-1:0]  m1_cmd_wdata,
    input  wire [STRB_WIDTH-1:0]  m1_cmd_wstrb,
    output wire                   m1_cmd_done,
    output wire [1:0]             m1_cmd_resp,
    output wire [DATA_WIDTH-1:0]  m1_cmd_rdata,

    // M2: Edge-AI NPU DMA
    input  wire                   m2_cmd_start,
    input  wire                   m2_cmd_is_write,
    input  wire [ADDR_WIDTH-1:0]  m2_cmd_addr,
    input  wire [7:0]             m2_cmd_len,
    input  wire [3:0]             m2_cmd_qos,
    input  wire [DATA_WIDTH-1:0]  m2_cmd_wdata,
    input  wire [STRB_WIDTH-1:0]  m2_cmd_wstrb,
    output wire                   m2_cmd_done,
    output wire [1:0]             m2_cmd_resp,
    output wire [DATA_WIDTH-1:0]  m2_cmd_rdata,

    // M3: Swin Accelerator DMA
    input  wire                   m3_cmd_start,
    input  wire                   m3_cmd_is_write,
    input  wire [ADDR_WIDTH-1:0]  m3_cmd_addr,
    input  wire [7:0]             m3_cmd_len,
    input  wire [3:0]             m3_cmd_qos,
    input  wire [DATA_WIDTH-1:0]  m3_cmd_wdata,
    input  wire [STRB_WIDTH-1:0]  m3_cmd_wstrb,
    output wire                   m3_cmd_done,
    output wire [1:0]             m3_cmd_resp,
    output wire [DATA_WIDTH-1:0]  m3_cmd_rdata,

    // M4: Output / Display DMA
    input  wire                   m4_cmd_start,
    input  wire                   m4_cmd_is_write,
    input  wire [ADDR_WIDTH-1:0]  m4_cmd_addr,
    input  wire [7:0]             m4_cmd_len,
    input  wire [3:0]             m4_cmd_qos,
    input  wire [DATA_WIDTH-1:0]  m4_cmd_wdata,
    input  wire [STRB_WIDTH-1:0]  m4_cmd_wstrb,
    output wire                   m4_cmd_done,
    output wire [1:0]             m4_cmd_resp,
    output wire [DATA_WIDTH-1:0]  m4_cmd_rdata,

    // M5: JTAG-to-AXI Debug
    input  wire                   m5_cmd_start,
    input  wire                   m5_cmd_is_write,
    input  wire [ADDR_WIDTH-1:0]  m5_cmd_addr,
    input  wire [7:0]             m5_cmd_len,
    input  wire [3:0]             m5_cmd_qos,
    input  wire [DATA_WIDTH-1:0]  m5_cmd_wdata,
    input  wire [STRB_WIDTH-1:0]  m5_cmd_wstrb,
    output wire                   m5_cmd_done,
    output wire [1:0]             m5_cmd_resp,
    output wire [DATA_WIDTH-1:0]  m5_cmd_rdata,

    // System Status & Interrupt Outputs
    output wire                   threshold_abnormal_irq,
    output wire [2:0]            threshold_wake_target,
    output wire                   firewall_violation_irq
);

    // Crossbar Signals - Master Side (6 Masters)
    wire [6*ID_WIDTH-1:0]    xb_s_awid;
    wire [6*ADDR_WIDTH-1:0]  xb_s_awaddr;
    wire [6*8-1:0]           xb_s_awlen;
    wire [6*3-1:0]           xb_s_awsize;
    wire [6*2-1:0]           xb_s_awburst;
    wire [6*4-1:0]           xb_s_awqos;
    wire [5:0]               xb_s_awvalid;
    wire [5:0]               xb_s_awready;

    wire [6*DATA_WIDTH-1:0]  xb_s_wdata;
    wire [6*STRB_WIDTH-1:0]  xb_s_wstrb;
    wire [5:0]               xb_s_wlast;
    wire [5:0]               xb_s_wvalid;
    wire [5:0]               xb_s_wready;

    wire [6*ID_WIDTH-1:0]    xb_s_bid;
    wire [6*2-1:0]           xb_s_bresp;
    wire [5:0]               xb_s_bvalid;
    wire [5:0]               xb_s_bready;

    wire [6*ID_WIDTH-1:0]    xb_s_arid;
    wire [6*ADDR_WIDTH-1:0]  xb_s_araddr;
    wire [6*8-1:0]           xb_s_arlen;
    wire [6*3-1:0]           xb_s_arsize;
    wire [6*2-1:0]           xb_s_arburst;
    wire [6*4-1:0]           xb_s_arqos;
    wire [5:0]               xb_s_arvalid;
    wire [5:0]               xb_s_arready;

    wire [6*ID_WIDTH-1:0]    xb_s_rid;
    wire [6*DATA_WIDTH-1:0]  xb_s_rdata;
    wire [6*2-1:0]           xb_s_rresp;
    wire [5:0]               xb_s_rlast;
    wire [5:0]               xb_s_rvalid;
    wire [5:0]               xb_s_rready;

    // Crossbar Signals - Slave Side (6 Slaves)
    wire [6*ID_WIDTH-1:0]    xb_m_awid;
    wire [6*ADDR_WIDTH-1:0]  xb_m_awaddr;
    wire [6*8-1:0]           xb_m_awlen;
    wire [6*3-1:0]           xb_m_awsize;
    wire [6*2-1:0]           xb_m_awburst;
    wire [5:0]               xb_m_awvalid;
    wire [5:0]               xb_m_awready;

    wire [6*DATA_WIDTH-1:0]  xb_m_wdata;
    wire [6*STRB_WIDTH-1:0]  xb_m_wstrb;
    wire [5:0]               xb_m_wlast;
    wire [5:0]               xb_m_wvalid;
    wire [5:0]               xb_m_wready;

    wire [6*ID_WIDTH-1:0]    xb_m_bid;
    wire [6*2-1:0]           xb_m_bresp;
    wire [5:0]               xb_m_bvalid;
    wire [5:0]               xb_m_bready;

    wire [6*ID_WIDTH-1:0]    xb_m_arid;
    wire [6*ADDR_WIDTH-1:0]  xb_m_araddr;
    wire [6*8-1:0]           xb_m_arlen;
    wire [6*3-1:0]           xb_m_arsize;
    wire [6*2-1:0]           xb_m_arburst;
    wire [5:0]               xb_m_arvalid;
    wire [5:0]               xb_m_arready;

    wire [6*ID_WIDTH-1:0]    xb_m_rid;
    wire [6*DATA_WIDTH-1:0]  xb_m_rdata;
    wire [6*2-1:0]           xb_m_rresp;
    wire [5:0]               xb_m_rlast;
    wire [5:0]               xb_m_rvalid;
    wire [5:0]               xb_m_rready;

    // -------------------------------------------------------------------------
    // Instantiate 6 Masters
    // -------------------------------------------------------------------------
    // M0: RISC-V Management Core
    axi_master_agent #(.MASTER_ID_VAL(`MASTER_M0_RISCV), .DEFAULT_QOS(4'd4)) u_master_m0 (
        .aclk(aclk), .aresetn(aresetn),
        .cmd_start(m0_cmd_start), .cmd_is_write(m0_cmd_is_write), .cmd_addr(m0_cmd_addr),
        .cmd_len(m0_cmd_len), .cmd_size(3'b010), .cmd_burst(`AXI_BURST_INCR), .cmd_qos(m0_cmd_qos),
        .cmd_wdata(m0_cmd_wdata), .cmd_wstrb(m0_cmd_wstrb), .cmd_done(m0_cmd_done),
        .cmd_resp(m0_cmd_resp), .cmd_rdata(m0_cmd_rdata),
        .m_axi_awid(xb_s_awid[0*ID_WIDTH +: ID_WIDTH]), .m_axi_awaddr(xb_s_awaddr[0*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_awlen(xb_s_awlen[0*8 +: 8]), .m_axi_awsize(xb_s_awsize[0*3 +: 3]),
        .m_axi_awburst(xb_s_awburst[0*2 +: 2]), .m_axi_awqos(xb_s_awqos[0*4 +: 4]),
        .m_axi_awvalid(xb_s_awvalid[0]), .m_axi_awready(xb_s_awready[0]),
        .m_axi_wdata(xb_s_wdata[0*DATA_WIDTH +: DATA_WIDTH]), .m_axi_wstrb(xb_s_wstrb[0*STRB_WIDTH +: STRB_WIDTH]),
        .m_axi_wlast(xb_s_wlast[0]), .m_axi_wvalid(xb_s_wvalid[0]), .m_axi_wready(xb_s_wready[0]),
        .m_axi_bid(xb_s_bid[0*ID_WIDTH +: ID_WIDTH]), .m_axi_bresp(xb_s_bresp[0*2 +: 2]),
        .m_axi_bvalid(xb_s_bvalid[0]), .m_axi_bready(xb_s_bready[0]),
        .m_axi_arid(xb_s_arid[0*ID_WIDTH +: ID_WIDTH]), .m_axi_araddr(xb_s_araddr[0*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_arlen(xb_s_arlen[0*8 +: 8]), .m_axi_arsize(xb_s_arsize[0*3 +: 3]),
        .m_axi_arburst(xb_s_arburst[0*2 +: 2]), .m_axi_arqos(xb_s_arqos[0*4 +: 4]),
        .m_axi_arvalid(xb_s_arvalid[0]), .m_axi_arready(xb_s_arready[0]),
        .m_axi_rid(xb_s_rid[0*ID_WIDTH +: ID_WIDTH]), .m_axi_rdata(xb_s_rdata[0*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_rresp(xb_s_rresp[0*2 +: 2]), .m_axi_rlast(xb_s_rlast[0]),
        .m_axi_rvalid(xb_s_rvalid[0]), .m_axi_rready(xb_s_rready[0])
    );

    // M1: AXI DMA (High QoS Priority)
    axi_master_agent #(.MASTER_ID_VAL(`MASTER_M1_DMA), .DEFAULT_QOS(4'd12)) u_master_m1 (
        .aclk(aclk), .aresetn(aresetn),
        .cmd_start(m1_cmd_start), .cmd_is_write(m1_cmd_is_write), .cmd_addr(m1_cmd_addr),
        .cmd_len(m1_cmd_len), .cmd_size(3'b010), .cmd_burst(`AXI_BURST_INCR), .cmd_qos(m1_cmd_qos),
        .cmd_wdata(m1_cmd_wdata), .cmd_wstrb(m1_cmd_wstrb), .cmd_done(m1_cmd_done),
        .cmd_resp(m1_cmd_resp), .cmd_rdata(m1_cmd_rdata),
        .m_axi_awid(xb_s_awid[1*ID_WIDTH +: ID_WIDTH]), .m_axi_awaddr(xb_s_awaddr[1*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_awlen(xb_s_awlen[1*8 +: 8]), .m_axi_awsize(xb_s_awsize[1*3 +: 3]),
        .m_axi_awburst(xb_s_awburst[1*2 +: 2]), .m_axi_awqos(xb_s_awqos[1*4 +: 4]),
        .m_axi_awvalid(xb_s_awvalid[1]), .m_axi_awready(xb_s_awready[1]),
        .m_axi_wdata(xb_s_wdata[1*DATA_WIDTH +: DATA_WIDTH]), .m_axi_wstrb(xb_s_wstrb[1*STRB_WIDTH +: STRB_WIDTH]),
        .m_axi_wlast(xb_s_wlast[1]), .m_axi_wvalid(xb_s_wvalid[1]), .m_axi_wready(xb_s_wready[1]),
        .m_axi_bid(xb_s_bid[1*ID_WIDTH +: ID_WIDTH]), .m_axi_bresp(xb_s_bresp[1*2 +: 2]),
        .m_axi_bvalid(xb_s_bvalid[1]), .m_axi_bready(xb_s_bready[1]),
        .m_axi_arid(xb_s_arid[1*ID_WIDTH +: ID_WIDTH]), .m_axi_araddr(xb_s_araddr[1*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_arlen(xb_s_arlen[1*8 +: 8]), .m_axi_arsize(xb_s_arsize[1*3 +: 3]),
        .m_axi_arburst(xb_s_arburst[1*2 +: 2]), .m_axi_arqos(xb_s_arqos[1*4 +: 4]),
        .m_axi_arvalid(xb_s_arvalid[1]), .m_axi_arready(xb_s_arready[1]),
        .m_axi_rid(xb_s_rid[1*ID_WIDTH +: ID_WIDTH]), .m_axi_rdata(xb_s_rdata[1*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_rresp(xb_s_rresp[1*2 +: 2]), .m_axi_rlast(xb_s_rlast[1]),
        .m_axi_rvalid(xb_s_rvalid[1]), .m_axi_rready(xb_s_rready[1])
    );

    // M2: Edge-AI NPU DMA
    axi_master_agent #(.MASTER_ID_VAL(`MASTER_M2_NPU), .DEFAULT_QOS(4'd8)) u_master_m2 (
        .aclk(aclk), .aresetn(aresetn),
        .cmd_start(m2_cmd_start), .cmd_is_write(m2_cmd_is_write), .cmd_addr(m2_cmd_addr),
        .cmd_len(m2_cmd_len), .cmd_size(3'b010), .cmd_burst(`AXI_BURST_INCR), .cmd_qos(m2_cmd_qos),
        .cmd_wdata(m2_cmd_wdata), .cmd_wstrb(m2_cmd_wstrb), .cmd_done(m2_cmd_done),
        .cmd_resp(m2_cmd_resp), .cmd_rdata(m2_cmd_rdata),
        .m_axi_awid(xb_s_awid[2*ID_WIDTH +: ID_WIDTH]), .m_axi_awaddr(xb_s_awaddr[2*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_awlen(xb_s_awlen[2*8 +: 8]), .m_axi_awsize(xb_s_awsize[2*3 +: 3]),
        .m_axi_awburst(xb_s_awburst[2*2 +: 2]), .m_axi_awqos(xb_s_awqos[2*4 +: 4]),
        .m_axi_awvalid(xb_s_awvalid[2]), .m_axi_awready(xb_s_awready[2]),
        .m_axi_wdata(xb_s_wdata[2*DATA_WIDTH +: DATA_WIDTH]), .m_axi_wstrb(xb_s_wstrb[2*STRB_WIDTH +: STRB_WIDTH]),
        .m_axi_wlast(xb_s_wlast[2]), .m_axi_wvalid(xb_s_wvalid[2]), .m_axi_wready(xb_s_wready[2]),
        .m_axi_bid(xb_s_bid[2*ID_WIDTH +: ID_WIDTH]), .m_axi_bresp(xb_s_bresp[2*2 +: 2]),
        .m_axi_bvalid(xb_s_bvalid[2]), .m_axi_bready(xb_s_bready[2]),
        .m_axi_arid(xb_s_arid[2*ID_WIDTH +: ID_WIDTH]), .m_axi_araddr(xb_s_araddr[2*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_arlen(xb_s_arlen[2*8 +: 8]), .m_axi_arsize(xb_s_arsize[2*3 +: 3]),
        .m_axi_arburst(xb_s_arburst[2*2 +: 2]), .m_axi_arqos(xb_s_arqos[2*4 +: 4]),
        .m_axi_arvalid(xb_s_arvalid[2]), .m_axi_arready(xb_s_arready[2]),
        .m_axi_rid(xb_s_rid[2*ID_WIDTH +: ID_WIDTH]), .m_axi_rdata(xb_s_rdata[2*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_rresp(xb_s_rresp[2*2 +: 2]), .m_axi_rlast(xb_s_rlast[2]),
        .m_axi_rvalid(xb_s_rvalid[2]), .m_axi_rready(xb_s_rready[2])
    );

    // M3: Swin Accelerator DMA (Highest QoS Priority)
    axi_master_agent #(.MASTER_ID_VAL(`MASTER_M3_SWIN), .DEFAULT_QOS(4'd15)) u_master_m3 (
        .aclk(aclk), .aresetn(aresetn),
        .cmd_start(m3_cmd_start), .cmd_is_write(m3_cmd_is_write), .cmd_addr(m3_cmd_addr),
        .cmd_len(m3_cmd_len), .cmd_size(3'b010), .cmd_burst(`AXI_BURST_INCR), .cmd_qos(m3_cmd_qos),
        .cmd_wdata(m3_cmd_wdata), .cmd_wstrb(m3_cmd_wstrb), .cmd_done(m3_cmd_done),
        .cmd_resp(m3_cmd_resp), .cmd_rdata(m3_cmd_rdata),
        .m_axi_awid(xb_s_awid[3*ID_WIDTH +: ID_WIDTH]), .m_axi_awaddr(xb_s_awaddr[3*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_awlen(xb_s_awlen[3*8 +: 8]), .m_axi_awsize(xb_s_awsize[3*3 +: 3]),
        .m_axi_awburst(xb_s_awburst[3*2 +: 2]), .m_axi_awqos(xb_s_awqos[3*4 +: 4]),
        .m_axi_awvalid(xb_s_awvalid[3]), .m_axi_awready(xb_s_awready[3]),
        .m_axi_wdata(xb_s_wdata[3*DATA_WIDTH +: DATA_WIDTH]), .m_axi_wstrb(xb_s_wstrb[3*STRB_WIDTH +: STRB_WIDTH]),
        .m_axi_wlast(xb_s_wlast[3]), .m_axi_wvalid(xb_s_wvalid[3]), .m_axi_wready(xb_s_wready[3]),
        .m_axi_bid(xb_s_bid[3*ID_WIDTH +: ID_WIDTH]), .m_axi_bresp(xb_s_bresp[3*2 +: 2]),
        .m_axi_bvalid(xb_s_bvalid[3]), .m_axi_bready(xb_s_bready[3]),
        .m_axi_arid(xb_s_arid[3*ID_WIDTH +: ID_WIDTH]), .m_axi_araddr(xb_s_araddr[3*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_arlen(xb_s_arlen[3*8 +: 8]), .m_axi_arsize(xb_s_arsize[3*3 +: 3]),
        .m_axi_arburst(xb_s_arburst[3*2 +: 2]), .m_axi_arqos(xb_s_arqos[3*4 +: 4]),
        .m_axi_arvalid(xb_s_arvalid[3]), .m_axi_arready(xb_s_arready[3]),
        .m_axi_rid(xb_s_rid[3*ID_WIDTH +: ID_WIDTH]), .m_axi_rdata(xb_s_rdata[3*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_rresp(xb_s_rresp[3*2 +: 2]), .m_axi_rlast(xb_s_rlast[3]),
        .m_axi_rvalid(xb_s_rvalid[3]), .m_axi_rready(xb_s_rready[3])
    );

    // M4: Output / Display DMA
    axi_master_agent #(.MASTER_ID_VAL(`MASTER_M4_DISPLAY), .DEFAULT_QOS(4'd10)) u_master_m4 (
        .aclk(aclk), .aresetn(aresetn),
        .cmd_start(m4_cmd_start), .cmd_is_write(m4_cmd_is_write), .cmd_addr(m4_cmd_addr),
        .cmd_len(m4_cmd_len), .cmd_size(3'b010), .cmd_burst(`AXI_BURST_INCR), .cmd_qos(m4_cmd_qos),
        .cmd_wdata(m4_cmd_wdata), .cmd_wstrb(m4_cmd_wstrb), .cmd_done(m4_cmd_done),
        .cmd_resp(m4_cmd_resp), .cmd_rdata(m4_cmd_rdata),
        .m_axi_awid(xb_s_awid[4*ID_WIDTH +: ID_WIDTH]), .m_axi_awaddr(xb_s_awaddr[4*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_awlen(xb_s_awlen[4*8 +: 8]), .m_axi_awsize(xb_s_awsize[4*3 +: 3]),
        .m_axi_awburst(xb_s_awburst[4*2 +: 2]), .m_axi_awqos(xb_s_awqos[4*4 +: 4]),
        .m_axi_awvalid(xb_s_awvalid[4]), .m_axi_awready(xb_s_awready[4]),
        .m_axi_wdata(xb_s_wdata[4*DATA_WIDTH +: DATA_WIDTH]), .m_axi_wstrb(xb_s_wstrb[4*STRB_WIDTH +: STRB_WIDTH]),
        .m_axi_wlast(xb_s_wlast[4]), .m_axi_wvalid(xb_s_wvalid[4]), .m_axi_wready(xb_s_wready[4]),
        .m_axi_bid(xb_s_bid[4*ID_WIDTH +: ID_WIDTH]), .m_axi_bresp(xb_s_bresp[4*2 +: 2]),
        .m_axi_bvalid(xb_s_bvalid[4]), .m_axi_bready(xb_s_bready[4]),
        .m_axi_arid(xb_s_arid[4*ID_WIDTH +: ID_WIDTH]), .m_axi_araddr(xb_s_araddr[4*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_arlen(xb_s_arlen[4*8 +: 8]), .m_axi_arsize(xb_s_arsize[4*3 +: 3]),
        .m_axi_arburst(xb_s_arburst[4*2 +: 2]), .m_axi_arqos(xb_s_arqos[4*4 +: 4]),
        .m_axi_arvalid(xb_s_arvalid[4]), .m_axi_arready(xb_s_arready[4]),
        .m_axi_rid(xb_s_rid[4*ID_WIDTH +: ID_WIDTH]), .m_axi_rdata(xb_s_rdata[4*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_rresp(xb_s_rresp[4*2 +: 2]), .m_axi_rlast(xb_s_rlast[4]),
        .m_axi_rvalid(xb_s_rvalid[4]), .m_axi_rready(xb_s_rready[4])
    );

    // M5: JTAG-to-AXI Debug Master
    axi_master_agent #(.MASTER_ID_VAL(`MASTER_M5_JTAG), .DEFAULT_QOS(4'd1)) u_master_m5 (
        .aclk(aclk), .aresetn(aresetn),
        .cmd_start(m5_cmd_start), .cmd_is_write(m5_cmd_is_write), .cmd_addr(m5_cmd_addr),
        .cmd_len(m5_cmd_len), .cmd_size(3'b010), .cmd_burst(`AXI_BURST_INCR), .cmd_qos(m5_cmd_qos),
        .cmd_wdata(m5_cmd_wdata), .cmd_wstrb(m5_cmd_wstrb), .cmd_done(m5_cmd_done),
        .cmd_resp(m5_cmd_resp), .cmd_rdata(m5_cmd_rdata),
        .m_axi_awid(xb_s_awid[5*ID_WIDTH +: ID_WIDTH]), .m_axi_awaddr(xb_s_awaddr[5*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_awlen(xb_s_awlen[5*8 +: 8]), .m_axi_awsize(xb_s_awsize[5*3 +: 3]),
        .m_axi_awburst(xb_s_awburst[5*2 +: 2]), .m_axi_awqos(xb_s_awqos[5*4 +: 4]),
        .m_axi_awvalid(xb_s_awvalid[5]), .m_axi_awready(xb_s_awready[5]),
        .m_axi_wdata(xb_s_wdata[5*DATA_WIDTH +: DATA_WIDTH]), .m_axi_wstrb(xb_s_wstrb[5*STRB_WIDTH +: STRB_WIDTH]),
        .m_axi_wlast(xb_s_wlast[5]), .m_axi_wvalid(xb_s_wvalid[5]), .m_axi_wready(xb_s_wready[5]),
        .m_axi_bid(xb_s_bid[5*ID_WIDTH +: ID_WIDTH]), .m_axi_bresp(xb_s_bresp[5*2 +: 2]),
        .m_axi_bvalid(xb_s_bvalid[5]), .m_axi_bready(xb_s_bready[5]),
        .m_axi_arid(xb_s_arid[5*ID_WIDTH +: ID_WIDTH]), .m_axi_araddr(xb_s_araddr[5*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_arlen(xb_s_arlen[5*8 +: 8]), .m_axi_arsize(xb_s_arsize[5*3 +: 3]),
        .m_axi_arburst(xb_s_arburst[5*2 +: 2]), .m_axi_arqos(xb_s_arqos[5*4 +: 4]),
        .m_axi_arvalid(xb_s_arvalid[5]), .m_axi_arready(xb_s_arready[5]),
        .m_axi_rid(xb_s_rid[5*ID_WIDTH +: ID_WIDTH]), .m_axi_rdata(xb_s_rdata[5*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_rresp(xb_s_rresp[5*2 +: 2]), .m_axi_rlast(xb_s_rlast[5]),
        .m_axi_rvalid(xb_s_rvalid[5]), .m_axi_rready(xb_s_rready[5])
    );

    // -------------------------------------------------------------------------
    // AXI Firewall Check
    // -------------------------------------------------------------------------
    axi_firewall #(.ADDR_WIDTH(ADDR_WIDTH), .ID_WIDTH(ID_WIDTH)) u_firewall (
        .aclk(aclk),
        .aresetn(aresetn),
        .firewall_en(firewall_en),
        .production_mode(production_mode),
        .master_id(xb_s_awvalid[4] ? `MASTER_M4_DISPLAY : (xb_s_awvalid[5] ? `MASTER_M5_JTAG : `MASTER_M0_RISCV)),
        .access_addr(xb_s_awvalid[4] ? xb_s_awaddr[4*ADDR_WIDTH +: ADDR_WIDTH] : xb_s_awaddr[0*ADDR_WIDTH +: ADDR_WIDTH]),
        .is_write(xb_s_awvalid[4] || xb_s_awvalid[5]),
        .access_allowed(),
        .violation_irq(firewall_violation_irq)
    );

    // -------------------------------------------------------------------------
    // Instantiate 6x6 Interconnect Crossbar
    // -------------------------------------------------------------------------
    axi_crossbar_6x6 #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .NUM_MASTERS(6),
        .NUM_SLAVES(6)
    ) u_crossbar (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awid(xb_s_awid), .s_axi_awaddr(xb_s_awaddr), .s_axi_awlen(xb_s_awlen),
        .s_axi_awsize(xb_s_awsize), .s_axi_awburst(xb_s_awburst), .s_axi_awqos(xb_s_awqos),
        .s_axi_awvalid(xb_s_awvalid), .s_axi_awready(xb_s_awready),
        .s_axi_wdata(xb_s_wdata), .s_axi_wstrb(xb_s_wstrb), .s_axi_wlast(xb_s_wlast),
        .s_axi_wvalid(xb_s_wvalid), .s_axi_wready(xb_s_wready),
        .s_axi_bid(xb_s_bid), .s_axi_bresp(xb_s_bresp), .s_axi_bvalid(xb_s_bvalid),
        .s_axi_bready(xb_s_bready),
        .s_axi_arid(xb_s_arid), .s_axi_araddr(xb_s_araddr), .s_axi_arlen(xb_s_arlen),
        .s_axi_arsize(xb_s_arsize), .s_axi_arburst(xb_s_arburst), .s_axi_arqos(xb_s_arqos),
        .s_axi_arvalid(xb_s_arvalid), .s_axi_arready(xb_s_arready),
        .s_axi_rid(xb_s_rid), .s_axi_rdata(xb_s_rdata), .s_axi_rresp(xb_s_rresp),
        .s_axi_rlast(xb_s_rlast), .s_axi_rvalid(xb_s_rvalid), .s_axi_rready(xb_s_rready),

        .m_axi_awid(xb_m_awid), .m_axi_awaddr(xb_m_awaddr), .m_axi_awlen(xb_m_awlen),
        .m_axi_awsize(xb_m_awsize), .m_axi_awburst(xb_m_awburst),
        .m_axi_awvalid(xb_m_awvalid), .m_axi_awready(xb_m_awready),
        .m_axi_wdata(xb_m_wdata), .m_axi_wstrb(xb_m_wstrb), .m_axi_wlast(xb_m_wlast),
        .m_axi_wvalid(xb_m_wvalid), .m_axi_wready(xb_m_wready),
        .m_axi_bid(xb_m_bid), .m_axi_bresp(xb_m_bresp), .m_axi_bvalid(xb_m_bvalid),
        .m_axi_bready(xb_m_bready),
        .m_axi_arid(xb_m_arid), .m_axi_araddr(xb_m_araddr), .m_axi_arlen(xb_m_arlen),
        .m_axi_arsize(xb_m_arsize), .m_axi_arburst(xb_m_arburst),
        .m_axi_arvalid(xb_m_arvalid), .m_axi_arready(xb_m_arready),
        .m_axi_rid(xb_m_rid), .m_axi_rdata(xb_m_rdata), .m_axi_rresp(xb_m_rresp),
        .m_axi_rlast(xb_m_rlast), .m_axi_rvalid(xb_m_rvalid), .m_axi_rready(xb_m_rready)
    );

    // -------------------------------------------------------------------------
    // S0: Boot ROM (0x0000_0000)
    // -------------------------------------------------------------------------
    axi_slave_rom #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .INIT_FILE(BOOT_HEX_FILE)
    ) u_slave_rom (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awid(xb_m_awid[0*ID_WIDTH +: ID_WIDTH]), .s_axi_awaddr(xb_m_awaddr[0*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_awlen(xb_m_awlen[0*8 +: 8]), .s_axi_awsize(xb_m_awsize[0*3 +: 3]),
        .s_axi_awburst(xb_m_awburst[0*2 +: 2]), .s_axi_awvalid(xb_m_awvalid[0]),
        .s_axi_awready(xb_m_awready[0]),
        .s_axi_wdata(xb_m_wdata[0*DATA_WIDTH +: DATA_WIDTH]), .s_axi_wstrb(xb_m_wstrb[0*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(xb_m_wlast[0]), .s_axi_wvalid(xb_m_wvalid[0]), .s_axi_wready(xb_m_wready[0]),
        .s_axi_bid(xb_m_bid[0*ID_WIDTH +: ID_WIDTH]), .s_axi_bresp(xb_m_bresp[0*2 +: 2]),
        .s_axi_bvalid(xb_m_bvalid[0]), .s_axi_bready(xb_m_bready[0]),
        .s_axi_arid(xb_m_arid[0*ID_WIDTH +: ID_WIDTH]), .s_axi_araddr(xb_m_araddr[0*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_arlen(xb_m_arlen[0*8 +: 8]), .s_axi_arsize(xb_m_arsize[0*3 +: 3]),
        .s_axi_arburst(xb_m_arburst[0*2 +: 2]), .s_axi_arvalid(xb_m_arvalid[0]),
        .s_axi_arready(xb_m_arready[0]),
        .s_axi_rid(xb_m_rid[0*ID_WIDTH +: ID_WIDTH]), .s_axi_rdata(xb_m_rdata[0*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(xb_m_rresp[0*2 +: 2]), .s_axi_rlast(xb_m_rlast[0]),
        .s_axi_rvalid(xb_m_rvalid[0]), .s_axi_rready(xb_m_rready[0])
    );

    // -------------------------------------------------------------------------
    // S1: On-chip SRAM (0x1000_0000)
    // -------------------------------------------------------------------------
    axi_slave_sram #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .INIT_FILE(SRAM_MEM_FILE)
    ) u_slave_sram (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awid(xb_m_awid[1*ID_WIDTH +: ID_WIDTH]), .s_axi_awaddr(xb_m_awaddr[1*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_awlen(xb_m_awlen[1*8 +: 8]), .s_axi_awsize(xb_m_awsize[1*3 +: 3]),
        .s_axi_awburst(xb_m_awburst[1*2 +: 2]), .s_axi_awvalid(xb_m_awvalid[1]),
        .s_axi_awready(xb_m_awready[1]),
        .s_axi_wdata(xb_m_wdata[1*DATA_WIDTH +: DATA_WIDTH]), .s_axi_wstrb(xb_m_wstrb[1*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(xb_m_wlast[1]), .s_axi_wvalid(xb_m_wvalid[1]), .s_axi_wready(xb_m_wready[1]),
        .s_axi_bid(xb_m_bid[1*ID_WIDTH +: ID_WIDTH]), .s_axi_bresp(xb_m_bresp[1*2 +: 2]),
        .s_axi_bvalid(xb_m_bvalid[1]), .s_axi_bready(xb_m_bready[1]),
        .s_axi_arid(xb_m_arid[1*ID_WIDTH +: ID_WIDTH]), .s_axi_araddr(xb_m_araddr[1*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_arlen(xb_m_arlen[1*8 +: 8]), .s_axi_arsize(xb_m_arsize[1*3 +: 3]),
        .s_axi_arburst(xb_m_arburst[1*2 +: 2]), .s_axi_arvalid(xb_m_arvalid[1]),
        .s_axi_arready(xb_m_arready[1]),
        .s_axi_rid(xb_m_rid[1*ID_WIDTH +: ID_WIDTH]), .s_axi_rdata(xb_m_rdata[1*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(xb_m_rresp[1*2 +: 2]), .s_axi_rlast(xb_m_rlast[1]),
        .s_axi_rvalid(xb_m_rvalid[1]), .s_axi_rready(xb_m_rready[1])
    );

    // -------------------------------------------------------------------------
    // S2: Accelerator Scratchpads (0x1100_0000)
    // -------------------------------------------------------------------------
    axi_slave_scratchpad #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .INIT_FILE(SCRATCHPAD_HEX_FILE)
    ) u_slave_scratchpad (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awid(xb_m_awid[2*ID_WIDTH +: ID_WIDTH]), .s_axi_awaddr(xb_m_awaddr[2*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_awlen(xb_m_awlen[2*8 +: 8]), .s_axi_awsize(xb_m_awsize[2*3 +: 3]),
        .s_axi_awburst(xb_m_awburst[2*2 +: 2]), .s_axi_awvalid(xb_m_awvalid[2]),
        .s_axi_awready(xb_m_awready[2]),
        .s_axi_wdata(xb_m_wdata[2*DATA_WIDTH +: DATA_WIDTH]), .s_axi_wstrb(xb_m_wstrb[2*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(xb_m_wlast[2]), .s_axi_wvalid(xb_m_wvalid[2]), .s_axi_wready(xb_m_wready[2]),
        .s_axi_bid(xb_m_bid[2*ID_WIDTH +: ID_WIDTH]), .s_axi_bresp(xb_m_bresp[2*2 +: 2]),
        .s_axi_bvalid(xb_m_bvalid[2]), .s_axi_bready(xb_m_bready[2]),
        .s_axi_arid(xb_m_arid[2*ID_WIDTH +: ID_WIDTH]), .s_axi_araddr(xb_m_araddr[2*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_arlen(xb_m_arlen[2*8 +: 8]), .s_axi_arsize(xb_m_arsize[2*3 +: 3]),
        .s_axi_arburst(xb_m_arburst[2*2 +: 2]), .s_axi_arvalid(xb_m_arvalid[2]),
        .s_axi_arready(xb_m_arready[2]),
        .s_axi_rid(xb_m_rid[2*ID_WIDTH +: ID_WIDTH]), .s_axi_rdata(xb_m_rdata[2*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(xb_m_rresp[2*2 +: 2]), .s_axi_rlast(xb_m_rlast[2]),
        .s_axi_rvalid(xb_m_rvalid[2]), .s_axi_rready(xb_m_rready[2])
    );

    // -------------------------------------------------------------------------
    // S3: AXI4-Lite Bridge & CSR Cluster (0x4000_0000)
    // -------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0]  axil_awaddr, axil_araddr;
    wire [2:0]             axil_awprot, axil_arprot;
    wire                   axil_awvalid, axil_awready;
    wire [DATA_WIDTH-1:0]  axil_wdata, axil_rdata;
    wire [STRB_WIDTH-1:0]  axil_wstrb;
    wire                   axil_wvalid, axil_wready;
    wire [1:0]             axil_bresp, axil_rresp;
    wire                   axil_bvalid, axil_bready;
    wire                   axil_arvalid, axil_arready;
    wire                   axil_rvalid, axil_rready;

    axi_to_axilite_bridge u_axilite_bridge (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awid(xb_m_awid[3*ID_WIDTH +: ID_WIDTH]), .s_axi_awaddr(xb_m_awaddr[3*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_awlen(xb_m_awlen[3*8 +: 8]), .s_axi_awsize(xb_m_awsize[3*3 +: 3]),
        .s_axi_awburst(xb_m_awburst[3*2 +: 2]), .s_axi_awvalid(xb_m_awvalid[3]),
        .s_axi_awready(xb_m_awready[3]),
        .s_axi_wdata(xb_m_wdata[3*DATA_WIDTH +: DATA_WIDTH]), .s_axi_wstrb(xb_m_wstrb[3*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(xb_m_wlast[3]), .s_axi_wvalid(xb_m_wvalid[3]), .s_axi_wready(xb_m_wready[3]),
        .s_axi_bid(xb_m_bid[3*ID_WIDTH +: ID_WIDTH]), .s_axi_bresp(xb_m_bresp[3*2 +: 2]),
        .s_axi_bvalid(xb_m_bvalid[3]), .s_axi_bready(xb_m_bready[3]),
        .s_axi_arid(xb_m_arid[3*ID_WIDTH +: ID_WIDTH]), .s_axi_araddr(xb_m_araddr[3*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_arlen(xb_m_arlen[3*8 +: 8]), .s_axi_arsize(xb_m_arsize[3*3 +: 3]),
        .s_axi_arburst(xb_m_arburst[3*2 +: 2]), .s_axi_arvalid(xb_m_arvalid[3]),
        .s_axi_arready(xb_m_arready[3]),
        .s_axi_rid(xb_m_rid[3*ID_WIDTH +: ID_WIDTH]), .s_axi_rdata(xb_m_rdata[3*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(xb_m_rresp[3*2 +: 2]), .s_axi_rlast(xb_m_rlast[3]),
        .s_axi_rvalid(xb_m_rvalid[3]), .s_axi_rready(xb_m_rready[3]),

        .m_axil_awaddr(axil_awaddr), .m_axil_awprot(axil_awprot), .m_axil_awvalid(axil_awvalid),
        .m_axil_awready(axil_awready),
        .m_axil_wdata(axil_wdata), .m_axil_wstrb(axil_wstrb), .m_axil_wvalid(axil_wvalid),
        .m_axil_wready(axil_wready),
        .m_axil_bresp(axil_bresp), .m_axil_bvalid(axil_bvalid), .m_axil_bready(axil_bready),
        .m_axil_araddr(axil_araddr), .m_axil_arprot(axil_arprot), .m_axil_arvalid(axil_arvalid),
        .m_axil_arready(axil_arready),
        .m_axil_rdata(axil_rdata), .m_axil_rresp(axil_rresp), .m_axil_rvalid(axil_rvalid),
        .m_axil_rready(axil_rready)
    );

    axilite_csr_cluster u_csr_cluster (
        .aclk(aclk), .aresetn(aresetn),
        .s_axil_awaddr(axil_awaddr), .s_axil_awprot(axil_awprot), .s_axil_awvalid(axil_awvalid),
        .s_axil_awready(axil_awready),
        .s_axil_wdata(axil_wdata), .s_axil_wstrb(axil_wstrb), .s_axil_wvalid(axil_wvalid),
        .s_axil_wready(axil_wready),
        .s_axil_bresp(axil_bresp), .s_axil_bvalid(axil_bvalid), .s_axil_bready(axil_bready),
        .s_axil_araddr(axil_araddr), .s_axil_arprot(axil_arprot), .s_axil_arvalid(axil_arvalid),
        .s_axil_arready(axil_arready),
        .s_axil_rdata(axil_rdata), .s_axil_rresp(axil_rresp), .s_axil_rvalid(axil_rvalid),
        .s_axil_rready(axil_rready),
        .threshold_irq(threshold_abnormal_irq),
        .wake_target(threshold_wake_target)
    );

    // -------------------------------------------------------------------------
    // S4: QSPI NVM / MRAM (0x6000_0000)
    // -------------------------------------------------------------------------
    axi_slave_nvm #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .INIT_FILE(NVM_HEX_FILE)
    ) u_slave_nvm (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awid(xb_m_awid[4*ID_WIDTH +: ID_WIDTH]), .s_axi_awaddr(xb_m_awaddr[4*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_awlen(xb_m_awlen[4*8 +: 8]), .s_axi_awsize(xb_m_awsize[4*3 +: 3]),
        .s_axi_awburst(xb_m_awburst[4*2 +: 2]), .s_axi_awvalid(xb_m_awvalid[4]),
        .s_axi_awready(xb_m_awready[4]),
        .s_axi_wdata(xb_m_wdata[4*DATA_WIDTH +: DATA_WIDTH]), .s_axi_wstrb(xb_m_wstrb[4*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(xb_m_wlast[4]), .s_axi_wvalid(xb_m_wvalid[4]), .s_axi_wready(xb_m_wready[4]),
        .s_axi_bid(xb_m_bid[4*ID_WIDTH +: ID_WIDTH]), .s_axi_bresp(xb_m_bresp[4*2 +: 2]),
        .s_axi_bvalid(xb_m_bvalid[4]), .s_axi_bready(xb_m_bready[4]),
        .s_axi_arid(xb_m_arid[4*ID_WIDTH +: ID_WIDTH]), .s_axi_araddr(xb_m_araddr[4*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_arlen(xb_m_arlen[4*8 +: 8]), .s_axi_arsize(xb_m_arsize[4*3 +: 3]),
        .s_axi_arburst(xb_m_arburst[4*2 +: 2]), .s_axi_arvalid(xb_m_arvalid[4]),
        .s_axi_arready(xb_m_arready[4]),
        .s_axi_rid(xb_m_rid[4*ID_WIDTH +: ID_WIDTH]), .s_axi_rdata(xb_m_rdata[4*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(xb_m_rresp[4*2 +: 2]), .s_axi_rlast(xb_m_rlast[4]),
        .s_axi_rvalid(xb_m_rvalid[4]), .s_axi_rready(xb_m_rready[4])
    );

    // -------------------------------------------------------------------------
    // S5: LPDDR Controller (0x8000_0000)
    // -------------------------------------------------------------------------
    axi_slave_lpddr #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .INIT_FILE(LPDDR_HEX_FILE)
    ) u_slave_lpddr (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awid(xb_m_awid[5*ID_WIDTH +: ID_WIDTH]), .s_axi_awaddr(xb_m_awaddr[5*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_awlen(xb_m_awlen[5*8 +: 8]), .s_axi_awsize(xb_m_awsize[5*3 +: 3]),
        .s_axi_awburst(xb_m_awburst[5*2 +: 2]), .s_axi_awvalid(xb_m_awvalid[5]),
        .s_axi_awready(xb_m_awready[5]),
        .s_axi_wdata(xb_m_wdata[5*DATA_WIDTH +: DATA_WIDTH]), .s_axi_wstrb(xb_m_wstrb[5*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(xb_m_wlast[5]), .s_axi_wvalid(xb_m_wvalid[5]), .s_axi_wready(xb_m_wready[5]),
        .s_axi_bid(xb_m_bid[5*ID_WIDTH +: ID_WIDTH]), .s_axi_bresp(xb_m_bresp[5*2 +: 2]),
        .s_axi_bvalid(xb_m_bvalid[5]), .s_axi_bready(xb_m_bready[5]),
        .s_axi_arid(xb_m_arid[5*ID_WIDTH +: ID_WIDTH]), .s_axi_araddr(xb_m_araddr[5*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_arlen(xb_m_arlen[5*8 +: 8]), .s_axi_arsize(xb_m_arsize[5*3 +: 3]),
        .s_axi_arburst(xb_m_arburst[5*2 +: 2]), .s_axi_arvalid(xb_m_arvalid[5]),
        .s_axi_arready(xb_m_arready[5]),
        .s_axi_rid(xb_m_rid[5*ID_WIDTH +: ID_WIDTH]), .s_axi_rdata(xb_m_rdata[5*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(xb_m_rresp[5*2 +: 2]), .s_axi_rlast(xb_m_rlast[5]),
        .s_axi_rvalid(xb_m_rvalid[5]), .s_axi_rready(xb_m_rready[5])
    );

endmodule
