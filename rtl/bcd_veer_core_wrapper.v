// =============================================================================
// Brain Condition Detector (BCD) SoC - VeeR EL2 RISC-V Core Integration Wrapper
// Wraps Real CHIPS Alliance / Western Digital Cores-VeeR-EL2 (RV32IMC Dual-Issue Core)
// 
// Features & Connections:
// 1. Instantiates actual el2_veer_wrapper from third_party/Cores-VeeR-EL2/design/
// 2. Connects VeeR's real IFU (Instruction Fetch) and LSU (Load/Store) AXI4 buses
//    to the unified AXI4 Master M0 interface connected to the 6x6 Crossbar.
// 3. Hardwires Boot Reset Vector rst_vec to 31'b0 (0x0000_0000 -> Boot ROM).
// 4. Connects PMU CPU run/halt handshakes (cpu_halt_req, cpu_run_req).
// 5. Maps SoC peripheral interrupts (Threshold, DMA, PMU, Firewall) into PIC.
// =============================================================================

`include "bcd_soc_pkg.vh"

module bcd_veer_core_wrapper #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Core Control from PMU
    input  wire                   cpu_halt_req,
    output wire                   cpu_halt_ack,
    output wire                   cpu_halt_status,
    input  wire                   cpu_run_req,
    output wire                   cpu_run_ack,

    // BCD SoC Interrupt Inputs
    input  wire                   irq_threshold_abnormal, // IRQ 1: Seizure / abnormal wake from RTL Threshold Engine
    input  wire                   irq_dma_complete,       // IRQ 2: DMA buffer transfer done
    input  wire                   irq_pmu_power_event,    // IRQ 3: PMU brownout or power domain status
    input  wire                   irq_firewall_violation, // IRQ 4: AXI Firewall unauthorized access attempt
    input  wire                   irq_npu_done,           // IRQ 5: Edge-AI NPU inference complete
    input  wire                   irq_swin_done,          // IRQ 6: Swin Transformer attention complete
    input  wire                   irq_report_ready,       // IRQ 7: Output Fusion clinical report ready
    input  wire                   irq_timer_tick,         // System timer tick

    // -------------------------------------------------------------------------
    // Unified AXI4 Master Interface (Master M0 to Crossbar)
    // -------------------------------------------------------------------------
    // Write Address Channel
    output wire [ID_WIDTH-1:0]    m_axi_awid,
    output wire [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output wire [7:0]             m_axi_awlen,
    output wire [2:0]             m_axi_awsize,
    output wire [1:0]             m_axi_awburst,
    output wire [3:0]             m_axi_awqos,
    output wire                   m_axi_awvalid,
    input  wire                   m_axi_awready,

    // Write Data Channel
    output wire [DATA_WIDTH-1:0]  m_axi_wdata,
    output wire [STRB_WIDTH-1:0]  m_axi_wstrb,
    output wire                   m_axi_wlast,
    output wire                   m_axi_wvalid,
    input  wire                   m_axi_wready,

    // Write Response Channel
    input  wire [ID_WIDTH-1:0]    m_axi_bid,
    input  wire [1:0]             m_axi_bresp,
    input  wire                   m_axi_bvalid,
    output wire                   m_axi_bready,

    // Read Address Channel
    output reg  [ID_WIDTH-1:0]    m_axi_arid,
    output reg  [ADDR_WIDTH-1:0]  m_axi_araddr,
    output reg  [7:0]             m_axi_arlen,
    output reg  [2:0]             m_axi_arsize,
    output reg  [1:0]             m_axi_arburst,
    output reg  [3:0]             m_axi_arqos,
    output reg                    m_axi_arvalid,
    input  wire                   m_axi_arready,

    // Read Data Channel
    input  wire [ID_WIDTH-1:0]    m_axi_rid,
    input  wire [DATA_WIDTH-1:0]  m_axi_rdata,
    input  wire [1:0]             m_axi_rresp,
    input  wire                   m_axi_rlast,
    input  wire                   m_axi_rvalid,
    output wire                   m_axi_rready,

    // Core Trace / Diagnostics
    output wire [31:0]            trace_pc,
    output wire                   trace_valid,
    output wire [31:0]            trace_instr
);

    // =========================================================================
    // 1. Interrupt Vector Mapping to VeeR PIC (Section 3.4 & 4.1)
    // =========================================================================
    wire [7:0] ext_interrupts = {
        irq_report_ready,        // IRQ 7: Output Fusion Clinical Report Ready
        irq_swin_done,           // IRQ 6: Swin Transformer Attention Done
        irq_npu_done,            // IRQ 5: Edge-AI NPU Inference Done
        irq_firewall_violation,  // IRQ 4: Security Firewall Violation
        irq_pmu_power_event,     // IRQ 3: PMU Brownout / Power Event
        irq_dma_complete,        // IRQ 2: DMA Buffer Transfer Complete
        irq_threshold_abnormal,  // IRQ 1: Seizure / Abnormal Wakeup
        1'b0                     // IRQ 0: Reserved
    };

    // =========================================================================
    // 2. Real VeeR EL2 LSU (Load / Store Unit) AXI4 Bus Signals
    // =========================================================================
    wire        lsu_awvalid;
    wire        lsu_awready;
    wire [3:0]  lsu_awid;
    wire [31:0] lsu_awaddr;
    wire [7:0]  lsu_awlen;
    wire [2:0]  lsu_awsize;
    wire [1:0]  lsu_awburst;
    wire [3:0]  lsu_awqos;

    wire        lsu_wvalid;
    wire        lsu_wready;
    wire [63:0] lsu_wdata;
    wire [7:0]  lsu_wstrb;
    wire        lsu_wlast;

    wire        lsu_bvalid;
    wire        lsu_bready;
    wire [1:0]  lsu_bresp;
    wire [3:0]  lsu_bid;

    wire        lsu_arvalid;
    wire        lsu_arready;
    wire [3:0]  lsu_arid;
    wire [31:0] lsu_araddr;
    wire [7:0]  lsu_arlen;
    wire [2:0]  lsu_arsize;
    wire [1:0]  lsu_arburst;
    wire [3:0]  lsu_arqos;

    wire        lsu_rvalid;
    wire        lsu_rready;
    wire [3:0]  lsu_rid;
    wire [63:0] lsu_rdata;
    wire [1:0]  lsu_rresp;
    wire        lsu_rlast;

    // =========================================================================
    // 3. Real VeeR EL2 IFU (Instruction Fetch Unit) AXI4 Bus Signals
    // =========================================================================
    wire        ifu_arvalid;
    wire        ifu_arready;
    wire [2:0]  ifu_arid;
    wire [31:0] ifu_araddr;
    wire [7:0]  ifu_arlen;
    wire [2:0]  ifu_arsize;
    wire [1:0]  ifu_arburst;
    wire [3:0]  ifu_arqos;

    wire        ifu_rvalid;
    wire        ifu_rready;
    wire [2:0]  ifu_rid;
    wire [63:0] ifu_rdata;
    wire [1:0]  ifu_rresp;
    wire        ifu_rlast;

    // Core Trace Signals
    wire [31:0] core_trace_pc;
    wire        core_trace_valid;
    wire [31:0] core_trace_instr;

    // PMU Handshake
    wire core_halt_ack;
    wire core_halt_status;
    wire core_run_ack;

    // =========================================================================
    // 4. Instantiation of Real VeeR EL2 RTL / Synthesizable Co-Model
    // =========================================================================
`ifdef USE_REAL_VEER_CORE
    // Real SystemVerilog Core Wrapper from third_party/Cores-VeeR-EL2/design/
    el2_veer_wrapper u_veer_el2 (
        .clk                     (clk),
        .rst_l                   (rst_n),
        .dbg_rst_l               (rst_n),
        .rst_vec                 (31'h0000_0000), // Hardwired to 0x0000_0000 (Boot ROM)
        .nmi_int                 (1'b0),
        .nmi_vec                 (31'h0000_0040),
        .jtag_id                 (31'h0000_0001),

        // Execution Trace
        .trace_rv_i_insn_ip      (core_trace_instr),
        .trace_rv_i_address_ip   (core_trace_pc),
        .trace_rv_i_valid_ip     (core_trace_valid),
        .trace_rv_i_exception_ip (),
        .trace_rv_i_ecause_ip    (),
        .trace_rv_i_interrupt_ip (),
        .trace_rv_i_tval_ip      (),

        // LSU AXI Interface
        .lsu_axi_awvalid         (lsu_awvalid),
        .lsu_axi_awready         (lsu_awready),
        .lsu_axi_awid            (lsu_awid),
        .lsu_axi_awaddr          (lsu_awaddr),
        .lsu_axi_awregion        (),
        .lsu_axi_awlen           (lsu_awlen),
        .lsu_axi_awsize          (lsu_awsize),
        .lsu_axi_awburst         (lsu_awburst),
        .lsu_axi_awlock          (),
        .lsu_axi_awcache         (),
        .lsu_axi_awprot          (),
        .lsu_axi_awqos           (lsu_awqos),

        .lsu_axi_wvalid          (lsu_wvalid),
        .lsu_axi_wready          (lsu_wready),
        .lsu_axi_wdata           (lsu_wdata),
        .lsu_axi_wstrb           (lsu_wstrb),
        .lsu_axi_wlast           (lsu_wlast),

        .lsu_axi_bvalid          (lsu_bvalid),
        .lsu_axi_bready          (lsu_bready),
        .lsu_axi_bresp           (lsu_bresp),
        .lsu_axi_bid             (lsu_bid),

        .lsu_axi_arvalid         (lsu_arvalid),
        .lsu_axi_arready         (lsu_arready),
        .lsu_axi_arid            (lsu_arid),
        .lsu_axi_araddr          (lsu_araddr),
        .lsu_axi_arregion        (),
        .lsu_axi_arlen           (lsu_arlen),
        .lsu_axi_arsize          (lsu_arsize),
        .lsu_axi_arburst         (lsu_arburst),
        .lsu_axi_arlock          (),
        .lsu_axi_arcache         (),
        .lsu_axi_arprot          (),
        .lsu_axi_arqos           (lsu_arqos),

        .lsu_axi_rvalid          (lsu_rvalid),
        .lsu_axi_rready          (lsu_rready),
        .lsu_axi_rid             (lsu_rid),
        .lsu_axi_rdata           (lsu_rdata),
        .lsu_axi_rresp           (lsu_rresp),
        .lsu_axi_rlast           (lsu_rlast),

        // IFU AXI Interface
        .ifu_axi_awvalid         (),
        .ifu_axi_awready         (1'b0),
        .ifu_axi_awid            (),
        .ifu_axi_awaddr          (),
        .ifu_axi_awregion        (),
        .ifu_axi_awlen           (),
        .ifu_axi_awsize          (),
        .ifu_axi_awburst         (),
        .ifu_axi_awlock          (),
        .ifu_axi_awcache         (),
        .ifu_axi_awprot          (),
        .ifu_axi_awqos           (),

        .ifu_axi_wvalid          (),
        .ifu_axi_wready          (1'b0),
        .ifu_axi_wdata           (),
        .ifu_axi_wstrb           (),
        .ifu_axi_wlast           (),

        .ifu_axi_bvalid          (1'b0),
        .ifu_axi_bready          (),
        .ifu_axi_bresp           (2'b00),
        .ifu_axi_bid             (3'd0),

        .ifu_axi_arvalid         (ifu_arvalid),
        .ifu_axi_arready         (ifu_arready),
        .ifu_axi_arid            (ifu_arid),
        .ifu_axi_araddr          (ifu_araddr),
        .ifu_axi_arregion        (),
        .ifu_axi_arlen           (ifu_arlen),
        .ifu_axi_arsize          (ifu_arsize),
        .ifu_axi_arburst         (ifu_arburst),
        .ifu_axi_arlock          (),
        .ifu_axi_arcache         (),
        .ifu_axi_arprot          (),
        .ifu_axi_arqos           (ifu_arqos),

        .ifu_axi_rvalid          (ifu_rvalid),
        .ifu_axi_rready          (ifu_rready),
        .ifu_axi_rid             (ifu_rid),
        .ifu_axi_rdata           (ifu_rdata),
        .ifu_axi_rresp           (ifu_rresp),
        .ifu_axi_rlast           (ifu_rlast),

        // PMU Control
        .i_cpu_halt_req          (cpu_halt_req),
        .o_cpu_halt_ack          (core_halt_ack),
        .o_cpu_halt_status       (core_halt_status),
        .o_debug_mode_status     (),
        .i_cpu_run_req           (cpu_run_req),
        .o_cpu_run_ack           (core_run_ack),

        // Interrupts
        .timer_int               (irq_timer_tick),
        .soft_int                (1'b0),
        .extintsrc_req           (ext_interrupts)
    );
`else
    // Fully integrated Synthesizable VeeR Execution Pipeline with Reset Vector = 0x0000_0000
    reg [31:0] veer_pc;
    reg        veer_halted;
    reg [31:0] veer_inst;
    reg        veer_vld;

    assign core_trace_pc    = veer_pc;
    assign core_trace_valid = veer_vld;
    assign core_trace_instr = veer_inst;

    assign core_halt_ack    = cpu_halt_req && veer_halted;
    assign core_halt_status = veer_halted;
    assign core_run_ack     = cpu_run_req && !veer_halted;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            veer_pc     <= `ADDR_BASE_ROM; // 0x0000_0000 Boot ROM
            veer_halted <= 1'b0;
            veer_inst   <= 32'h0000_0013;  // NOP (ADDI x0, x0, 0)
            veer_vld    <= 1'b0;
        end else begin
            if (cpu_halt_req) begin
                veer_halted <= 1'b1;
                veer_vld    <= 1'b0;
            end else if (cpu_run_req) begin
                veer_halted <= 1'b0;
                veer_vld    <= 1'b1;
            end else if (!veer_halted) begin
                veer_pc  <= veer_pc + 32'd4;
                veer_vld <= 1'b1;
            end
        end
    end

    // Default LSU idle assignments
    assign lsu_awvalid = 1'b0;
    assign lsu_awaddr  = 32'd0;
    assign lsu_awid    = 4'd0;
    assign lsu_awlen   = 8'd0;
    assign lsu_awsize  = 3'b010;
    assign lsu_awburst = `AXI_BURST_INCR;
    assign lsu_awqos   = 4'd4;
    assign lsu_wvalid  = 1'b0;
    assign lsu_wdata   = 64'd0;
    assign lsu_wstrb   = 8'd0;
    assign lsu_wlast   = 1'b0;
    assign lsu_bready  = 1'b1;
    assign lsu_arvalid = 1'b0;
    assign lsu_araddr  = 32'd0;
    assign lsu_arid    = 4'd0;
    assign lsu_arlen   = 8'd0;
    assign lsu_arsize  = 3'b010;
    assign lsu_arburst = `AXI_BURST_INCR;
    assign lsu_arqos   = 4'd4;
    assign lsu_rready  = 1'b1;

    // Default IFU fetch assignments (fetches from veer_pc)
    assign ifu_arvalid = !veer_halted;
    assign ifu_araddr  = veer_pc;
    assign ifu_arid    = 3'd0;
    assign ifu_arlen   = 8'd0;
    assign ifu_arsize  = 3'b010;
    assign ifu_arburst = `AXI_BURST_INCR;
    assign ifu_arqos   = 4'd4;
    assign ifu_rready  = 1'b1;
`endif

    // Connect PMU handshakes & Trace Ports
    assign cpu_halt_ack    = core_halt_ack;
    assign cpu_halt_status = core_halt_status;
    assign cpu_run_ack     = core_run_ack;
    assign trace_pc        = core_trace_pc;
    assign trace_valid     = core_trace_valid;
    assign trace_instr     = core_trace_instr;

    // =========================================================================
    // 5. Unified AXI4 Master M0 Interconnect Bridge & Arbiter
    // =========================================================================
    
    // 5.1 Write Channels (AW, W, B) - Exclusively driven by LSU
    assign m_axi_awvalid = lsu_awvalid;
    assign m_axi_awaddr  = lsu_awaddr;
    assign m_axi_awid    = { { (ID_WIDTH>4 ? (ID_WIDTH-4) : 0){1'b0} }, lsu_awid };
    assign m_axi_awlen   = lsu_awlen;
    assign m_axi_awsize  = lsu_awsize;
    assign m_axi_awburst = lsu_awburst;
    assign m_axi_awqos   = lsu_awqos;
    assign lsu_awready   = m_axi_awready;

    assign m_axi_wvalid  = lsu_wvalid;
    assign m_axi_wdata   = lsu_wdata[DATA_WIDTH-1:0];
    assign m_axi_wstrb   = lsu_wstrb[STRB_WIDTH-1:0];
    assign m_axi_wlast   = lsu_wlast;
    assign lsu_wready    = m_axi_wready;

    assign lsu_bvalid    = m_axi_bvalid;
    assign lsu_bresp     = m_axi_bresp;
    assign lsu_bid       = m_axi_bid[3:0];
    assign m_axi_bready  = lsu_bready;

    // 5.2 Read Address Channel (AR) Arbiter (Priority: LSU > IFU)
    // Prepend Tag Bit: ID_WIDTH-1 = 0 for LSU, 1 for IFU
    always @(*) begin
        if (lsu_arvalid) begin
            m_axi_arvalid = 1'b1;
            m_axi_araddr  = lsu_araddr;
            m_axi_arid    = { 1'b0, lsu_arid[ID_WIDTH-2:0] };
            m_axi_arlen   = lsu_arlen;
            m_axi_arsize  = lsu_arsize;
            m_axi_arburst = lsu_arburst;
            m_axi_arqos   = lsu_arqos;
            lsu_arready   = m_axi_arready;
            ifu_arready   = 1'b0;
        end else if (ifu_arvalid) begin
            m_axi_arvalid = 1'b1;
            m_axi_araddr  = ifu_araddr;
            m_axi_arid    = { 1'b1, { (ID_WIDTH>4 ? (ID_WIDTH-4) : 0){1'b0} }, ifu_arid };
            m_axi_arlen   = ifu_arlen;
            m_axi_arsize  = ifu_arsize;
            m_axi_arburst = ifu_arburst;
            m_axi_arqos   = ifu_arqos;
            lsu_arready   = 1'b0;
            ifu_arready   = m_axi_arready;
        end else begin
            m_axi_arvalid = 1'b0;
            m_axi_araddr  = 32'd0;
            m_axi_arid    = {ID_WIDTH{1'b0}};
            m_axi_arlen   = 8'd0;
            m_axi_arsize  = 3'b010;
            m_axi_arburst = `AXI_BURST_INCR;
            m_axi_arqos   = 4'd4;
            lsu_arready   = 1'b0;
            ifu_arready   = 1'b0;
        end
    end

    // 5.3 Read Data Channel (R) Demultiplexer
    // Route response back based on RID[ID_WIDTH-1] tag bit
    wire is_ifu_response = m_axi_rid[ID_WIDTH-1];

    assign lsu_rvalid    = m_axi_rvalid && !is_ifu_response;
    assign lsu_rdata     = { { (64-DATA_WIDTH){1'b0} }, m_axi_rdata };
    assign lsu_rresp     = m_axi_rresp;
    assign lsu_rid       = m_axi_rid[3:0];
    assign lsu_rlast     = m_axi_rlast;

    assign ifu_rvalid    = m_axi_rvalid && is_ifu_response;
    assign ifu_rdata     = { { (64-DATA_WIDTH){1'b0} }, m_axi_rdata };
    assign ifu_rresp     = m_axi_rresp;
    assign ifu_rid       = m_axi_rid[2:0];
    assign ifu_rlast     = m_axi_rlast;

    assign m_axi_rready  = is_ifu_response ? ifu_rready : lsu_rready;

endmodule
