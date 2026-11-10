// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Lite CSR Cluster
// Decodes and routes AXI4-Lite CSR accesses (0x4000_0000 - 0x4009_0000)
// Integrates the RTL Threshold Engine (Block 2), Edge-AI NPU (Block 5),
// Swin Transformer Accelerator (Block 6) and generic CSR registers for other blocks.
// =============================================================================

`include "bcd_soc_pkg.vh"

module axilite_csr_cluster #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                  aclk,
    input  wire                  aresetn,

    // AXI4-Lite Slave Interface from Bridge
    input  wire [ADDR_WIDTH-1:0] s_axil_awaddr,
    input  wire [2:0]            s_axil_awprot,
    input  wire                  s_axil_awvalid,
    output wire                  s_axil_awready,

    input  wire [DATA_WIDTH-1:0] s_axil_wdata,
    input  wire [3:0]            s_axil_wstrb,
    input  wire                  s_axil_wvalid,
    output wire                  s_axil_wready,

    output wire [1:0]            s_axil_bresp,
    output wire                  s_axil_bvalid,
    input  wire                  s_axil_bready,

    input  wire [ADDR_WIDTH-1:0] s_axil_araddr,
    input  wire [2:0]            s_axil_arprot,
    input  wire                  s_axil_arvalid,
    output wire                  s_axil_arready,

    output wire [DATA_WIDTH-1:0] s_axil_rdata,
    output wire [1:0]            s_axil_rresp,
    output wire                  s_axil_rvalid,
    input  wire                  s_axil_rready,

    // Block 5: Edge-AI NPU CSR Sub-Bus (0x4005_0000)
    output wire [ADDR_WIDTH-1:0] npu_axil_awaddr,
    output wire                  npu_axil_awvalid,
    input  wire                  npu_axil_awready,
    output wire [DATA_WIDTH-1:0] npu_axil_wdata,
    output wire [3:0]            npu_axil_wstrb,
    output wire                  npu_axil_wvalid,
    input  wire                  npu_axil_wready,
    input  wire [1:0]            npu_axil_bresp,
    input  wire                  npu_axil_bvalid,
    output wire                  npu_axil_bready,
    output wire [ADDR_WIDTH-1:0] npu_axil_araddr,
    output wire                  npu_axil_arvalid,
    input  wire                  npu_axil_arready,
    input  wire [DATA_WIDTH-1:0] npu_axil_rdata,
    input  wire [1:0]            npu_axil_rresp,
    input  wire                  npu_axil_rvalid,
    output wire                  npu_axil_rready,

    // Block 6: Swin Transformer CSR Sub-Bus (0x4006_0000)
    output wire [ADDR_WIDTH-1:0] swin_axil_awaddr,
    output wire                  swin_axil_awvalid,
    input  wire                  swin_axil_awready,
    output wire [DATA_WIDTH-1:0] swin_axil_wdata,
    output wire [3:0]            swin_axil_wstrb,
    output wire                  swin_axil_wvalid,
    input  wire                  swin_axil_wready,
    input  wire [1:0]            swin_axil_bresp,
    input  wire                  swin_axil_bvalid,
    output wire                  swin_axil_bready,
    output wire [ADDR_WIDTH-1:0] swin_axil_araddr,
    output wire                  swin_axil_arvalid,
    input  wire                  swin_axil_arready,
    input  wire [DATA_WIDTH-1:0] swin_axil_rdata,
    input  wire [1:0]            swin_axil_rresp,
    input  wire                  swin_axil_rvalid,
    output wire                  swin_axil_rready,

    // Sub-block hardware signals
    output wire                  threshold_irq,
    output wire [2:0]            wake_target
);

    // CSR Block Decode based on address bits [19:16]
    wire [3:0] w_block = s_axil_awaddr[19:16];
    wire [3:0] r_block = s_axil_araddr[19:16];

    wire is_thresh_write = (w_block == 4'h2);
    wire is_thresh_read  = (r_block == 4'h2);

    wire is_npu_write    = (w_block == 4'h5);
    wire is_npu_read     = (r_block == 4'h5);

    wire is_swin_write   = (w_block == 4'h6);
    wire is_swin_read    = (r_block == 4'h6);

    wire is_gen_write    = (!is_thresh_write && !is_npu_write && !is_swin_write);
    wire is_gen_read     = (!is_thresh_read && !is_npu_read && !is_swin_read);

    // Generic Register Storage for other blocks (0, 1, 3, 4, 7, 8, 9)
    reg [31:0] generic_csrs [0:9];
    integer g;
    initial begin
        for (g = 0; g < 10; g = g + 1) begin
            generic_csrs[g] = 32'h0000_0000;
        end
        generic_csrs[0] = 32'h0000_0001; // AFE active
        generic_csrs[3] = 32'h0000_0003; // PMU active
        generic_csrs[4] = 32'h0000_0100; // DMA ring size
        generic_csrs[8] = 32'h5345_4355; // Security "SECU"
    end

    // -------------------------------------------------------------------------
    // Threshold Engine (Block 2)
    // -------------------------------------------------------------------------
    wire thresh_awready, thresh_wready, thresh_bvalid, thresh_arready, thresh_rvalid;
    wire [1:0] thresh_bresp, thresh_rresp;
    wire [31:0] thresh_rdata;

    rtl_threshold_engine u_threshold_engine (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .s_axil_awaddr    (s_axil_awaddr),
        .s_axil_awvalid   (s_axil_awvalid && is_thresh_write),
        .s_axil_awready   (thresh_awready),
        .s_axil_wdata     (s_axil_wdata),
        .s_axil_wstrb     (s_axil_wstrb),
        .s_axil_wvalid    (s_axil_wvalid && is_thresh_write),
        .s_axil_wready    (thresh_wready),
        .s_axil_bresp     (thresh_bresp),
        .s_axil_bvalid    (thresh_bvalid),
        .s_axil_bready    (s_axil_bready && is_thresh_write),
        .s_axil_araddr    (s_axil_araddr),
        .s_axil_arvalid   (s_axil_arvalid && is_thresh_read),
        .s_axil_arready   (thresh_arready),
        .s_axil_rdata     (thresh_rdata),
        .s_axil_rresp     (thresh_rresp),
        .s_axil_rvalid    (thresh_rvalid),
        .s_axil_rready    (s_axil_rready && is_thresh_read),
        .abnormal_wake_irq(threshold_irq),
        .wake_target_out  (wake_target)
    );

    // -------------------------------------------------------------------------
    // Forward to Block 5: NPU Sub-Bus
    // -------------------------------------------------------------------------
    assign npu_axil_awaddr  = s_axil_awaddr;
    assign npu_axil_awvalid = s_axil_awvalid && is_npu_write;
    assign npu_axil_wdata   = s_axil_wdata;
    assign npu_axil_wstrb   = s_axil_wstrb;
    assign npu_axil_wvalid  = s_axil_wvalid && is_npu_write;
    assign npu_axil_bready  = s_axil_bready && is_npu_write;
    assign npu_axil_araddr  = s_axil_araddr;
    assign npu_axil_arvalid = s_axil_arvalid && is_npu_read;
    assign npu_axil_rready  = s_axil_rready && is_npu_read;

    // -------------------------------------------------------------------------
    // Forward to Block 6: Swin Sub-Bus
    // -------------------------------------------------------------------------
    assign swin_axil_awaddr  = s_axil_awaddr;
    assign swin_axil_awvalid = s_axil_awvalid && is_swin_write;
    assign swin_axil_wdata   = s_axil_wdata;
    assign swin_axil_wstrb   = s_axil_wstrb;
    assign swin_axil_wvalid  = s_axil_wvalid && is_swin_write;
    assign swin_axil_bready  = s_axil_bready && is_swin_write;
    assign swin_axil_araddr  = s_axil_araddr;
    assign swin_axil_arvalid = s_axil_arvalid && is_swin_read;
    assign swin_axil_rready  = s_axil_rready && is_swin_read;

    // -------------------------------------------------------------------------
    // Generic CSR Cluster Handshake (Blocks 0, 1, 3, 4, 7, 8, 9)
    // -------------------------------------------------------------------------
    reg gen_awready, gen_wready, gen_bvalid, gen_arready, gen_rvalid;
    reg [31:0] gen_rdata;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            gen_awready <= 1'b0;
            gen_wready  <= 1'b0;
            gen_bvalid  <= 1'b0;
            gen_arready <= 1'b0;
            gen_rvalid  <= 1'b0;
            gen_rdata   <= 32'd0;
        end else begin
            // Generic Write
            if (s_axil_awvalid && is_gen_write && !gen_awready) begin
                gen_awready <= 1'b1;
            end else begin
                gen_awready <= 1'b0;
            end

            if (s_axil_wvalid && is_gen_write && !gen_wready) begin
                gen_wready <= 1'b1;
                gen_bvalid <= 1'b1;
                if (w_block < 10) begin
                    generic_csrs[w_block] <= s_axil_wdata;
                end
            end else begin
                gen_wready <= 1'b0;
            end

            if (gen_bvalid && s_axil_bready) begin
                gen_bvalid <= 1'b0;
            end

            // Generic Read
            if (s_axil_arvalid && is_gen_read && !gen_arready) begin
                gen_arready <= 1'b1;
                gen_rvalid  <= 1'b1;
                if (r_block < 10) begin
                    gen_rdata <= generic_csrs[r_block];
                end else begin
                    gen_rdata <= 32'hDEAD_C512;
                end
            end else begin
                gen_arready <= 1'b0;
            end

            if (gen_rvalid && s_axil_rready) begin
                gen_rvalid <= 1'b0;
            end
        end
    end

    // Multiplex CSR outputs back to Bridge
    assign s_axil_awready = is_thresh_write ? thresh_awready :
                            is_npu_write    ? npu_axil_awready :
                            is_swin_write   ? swin_axil_awready : gen_awready;

    assign s_axil_wready  = is_thresh_write ? thresh_wready :
                            is_npu_write    ? npu_axil_wready :
                            is_swin_write   ? swin_axil_wready : gen_wready;

    assign s_axil_bresp   = is_thresh_write ? thresh_bresp :
                            is_npu_write    ? npu_axil_bresp :
                            is_swin_write   ? swin_axil_bresp : `AXI_RESP_OKAY;

    assign s_axil_bvalid  = is_thresh_write ? thresh_bvalid :
                            is_npu_write    ? npu_axil_bvalid :
                            is_swin_write   ? swin_axil_bvalid : gen_bvalid;

    assign s_axil_arready = is_thresh_read  ? thresh_arready :
                            is_npu_read     ? npu_axil_arready :
                            is_swin_read    ? swin_axil_arready : gen_arready;

    assign s_axil_rdata   = is_thresh_read  ? thresh_rdata :
                            is_npu_read     ? npu_axil_rdata :
                            is_swin_read    ? swin_axil_rdata : gen_rdata;

    assign s_axil_rresp   = is_thresh_read  ? thresh_rresp :
                            is_npu_read     ? npu_axil_rresp :
                            is_swin_read    ? swin_axil_rresp : `AXI_RESP_OKAY;

    assign s_axil_rvalid  = is_thresh_read  ? thresh_rvalid :
                            is_npu_read     ? npu_axil_rvalid :
                            is_swin_read    ? swin_axil_rvalid : gen_rvalid;

endmodule
