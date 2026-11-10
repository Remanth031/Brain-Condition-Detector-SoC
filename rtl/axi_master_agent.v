// =============================================================================
// Brain Condition Detector (BCD) SoC - Configurable AXI4 Master Agent
// Used to represent M0 (RISC-V), M1 (AXI DMA), M2 (NPU DMA), M3 (Swin DMA),
// M4 (Display DMA), and M5 (JTAG-to-AXI Debug).
// Features configurable Master ID, default AxQOS, burst generator, and checkers.
// =============================================================================

`include "bcd_soc_pkg.vh"

module axi_master_agent #(
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter STRB_WIDTH    = (DATA_WIDTH / 8),
    parameter ID_WIDTH      = 4,
    parameter MASTER_ID_VAL = 4'd0,
    parameter DEFAULT_QOS   = 4'd0
)(
    input  wire                   aclk,
    input  wire                   aresetn,

    // Command Interface for Testbench / RISC-V Firmware Trigger
    input  wire                   cmd_start,
    input  wire                   cmd_is_write,
    input  wire [ADDR_WIDTH-1:0]  cmd_addr,
    input  wire [7:0]             cmd_len,       // 0 = 1 beat, 1 = 2 beats, etc.
    input  wire [2:0]             cmd_size,      // 3'b010 = 4 bytes (32-bit)
    input  wire [1:0]             cmd_burst,     // 2'b01 = INCR
    input  wire [3:0]             cmd_qos,
    input  wire [DATA_WIDTH-1:0]  cmd_wdata,
    input  wire [STRB_WIDTH-1:0]  cmd_wstrb,
    output reg                    cmd_done,
    output reg  [1:0]             cmd_resp,
    output reg  [DATA_WIDTH-1:0]  cmd_rdata,

    // -------------------------------------------------------------------------
    // AXI4-Full Master Interface
    // -------------------------------------------------------------------------
    // Write Address Channel
    output reg  [ID_WIDTH-1:0]    m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output reg  [7:0]             m_axi_awlen,
    output reg  [2:0]             m_axi_awsize,
    output reg  [1:0]             m_axi_awburst,
    output reg  [3:0]             m_axi_awqos,
    output reg                    m_axi_awvalid,
    input  wire                   m_axi_awready,

    // Write Data Channel
    output reg  [DATA_WIDTH-1:0]  m_axi_wdata,
    output reg  [STRB_WIDTH-1:0]  m_axi_wstrb,
    output reg                    m_axi_wlast,
    output reg                    m_axi_wvalid,
    input  wire                   m_axi_wready,

    // Write Response Channel
    input  wire [ID_WIDTH-1:0]    m_axi_bid,
    input  wire [1:0]             m_axi_bresp,
    input  wire                   m_axi_bvalid,
    output reg                    m_axi_bready,

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
    output reg                    m_axi_rready
);

    // Internal Master FSM
    localparam M_IDLE      = 3'd0;
    localparam M_WRITE_AW  = 3'd1;
    localparam M_WRITE_W   = 3'd2;
    localparam M_WRITE_B   = 3'd3;
    localparam M_READ_AR   = 3'd4;
    localparam M_READ_R    = 3'd5;
    localparam M_DONE      = 3'd6;

    reg [2:0] state;
    reg [7:0] beat_count;
    reg [7:0] total_beats;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state         <= M_IDLE;
            cmd_done      <= 1'b0;
            cmd_resp      <= `AXI_RESP_OKAY;
            cmd_rdata     <= 32'd0;
            beat_count    <= 8'd0;
            total_beats   <= 8'd0;

            m_axi_awid    <= MASTER_ID_VAL;
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen   <= 8'd0;
            m_axi_awsize  <= 3'b010;
            m_axi_awburst <= `AXI_BURST_INCR;
            m_axi_awqos   <= DEFAULT_QOS;
            m_axi_awvalid <= 1'b0;

            m_axi_wdata   <= {DATA_WIDTH{1'b0}};
            m_axi_wstrb   <= {STRB_WIDTH{1'b1}};
            m_axi_wlast   <= 1'b0;
            m_axi_wvalid  <= 1'b0;

            m_axi_bready  <= 1'b0;

            m_axi_arid    <= MASTER_ID_VAL;
            m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen   <= 8'd0;
            m_axi_arsize  <= 3'b010;
            m_axi_arburst <= `AXI_BURST_INCR;
            m_axi_arqos   <= DEFAULT_QOS;
            m_axi_arvalid <= 1'b0;

            m_axi_rready  <= 1'b0;
        end else begin
            case (state)
                M_IDLE: begin
                    cmd_done <= 1'b0;
                    if (cmd_start) begin
                        total_beats <= cmd_len;
                        beat_count  <= 8'd0;
                        if (cmd_is_write) begin
                            m_axi_awid    <= MASTER_ID_VAL;
                            m_axi_awaddr  <= cmd_addr;
                            m_axi_awlen   <= cmd_len;
                            m_axi_awsize  <= cmd_size;
                            m_axi_awburst <= cmd_burst;
                            m_axi_awqos   <= (cmd_qos != 4'd0) ? cmd_qos : DEFAULT_QOS;
                            m_axi_awvalid <= 1'b1;
                            state         <= M_WRITE_AW;
                        end else begin
                            m_axi_arid    <= MASTER_ID_VAL;
                            m_axi_araddr  <= cmd_addr;
                            m_axi_arlen   <= cmd_len;
                            m_axi_arsize  <= cmd_size;
                            m_axi_arburst <= cmd_burst;
                            m_axi_arqos   <= (cmd_qos != 4'd0) ? cmd_qos : DEFAULT_QOS;
                            m_axi_arvalid <= 1'b1;
                            state         <= M_READ_AR;
                        end
                    end
                end

                M_WRITE_AW: begin
                    if (m_axi_awready && m_axi_awvalid) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wdata   <= cmd_wdata;
                        m_axi_wstrb   <= cmd_wstrb;
                        m_axi_wlast   <= (total_beats == 8'd0);
                        m_axi_wvalid  <= 1'b1;
                        state         <= M_WRITE_W;
                    end
                end

                M_WRITE_W: begin
                    if (m_axi_wready && m_axi_wvalid) begin
                        if (m_axi_wlast || (beat_count == total_beats)) begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast  <= 1'b0;
                            m_axi_bready <= 1'b1;
                            state        <= M_WRITE_B;
                        end else begin
                            beat_count   <= beat_count + 8'd1;
                            m_axi_wdata  <= cmd_wdata + beat_count + 8'd1; // sequential burst pattern
                            m_axi_wlast  <= (beat_count + 8'd1 == total_beats);
                        end
                    end
                end

                M_WRITE_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        cmd_resp     <= m_axi_bresp;
                        state        <= M_DONE;
                    end
                end

                M_READ_AR: begin
                    if (m_axi_arready && m_axi_arvalid) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= M_READ_R;
                    end
                end

                M_READ_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        cmd_rdata <= m_axi_rdata;
                        cmd_resp  <= m_axi_rresp;
                        if (m_axi_rlast || (beat_count == total_beats)) begin
                            m_axi_rready <= 1'b0;
                            state        <= M_DONE;
                        end else begin
                            beat_count <= beat_count + 8'd1;
                        end
                    end
                end

                M_DONE: begin
                    cmd_done <= 1'b1;
                    state    <= M_IDLE;
                end
            endcase
        end
    end

endmodule
