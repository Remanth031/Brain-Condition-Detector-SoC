// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Full to AXI4-Lite Bridge
// Translates AXI4-Full burst/ID protocol transactions into AXI4-Lite single-beat
// accesses for the CSR cluster.
// =============================================================================

`include "bcd_soc_pkg.vh"

module axi_to_axilite_bridge #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire                   aclk,
    input  wire                   aresetn,

    // -------------------------------------------------------------------------
    // AXI4-Full Slave Interface (from Interconnect)
    // -------------------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awvalid,
    output reg                    s_axi_awready,

    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output reg                    s_axi_wready,

    output reg  [ID_WIDTH-1:0]    s_axi_bid,
    output reg  [1:0]             s_axi_bresp,
    output reg                    s_axi_bvalid,
    input  wire                   s_axi_bready,

    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arvalid,
    output reg                    s_axi_arready,

    output reg  [ID_WIDTH-1:0]    s_axi_rid,
    output reg  [DATA_WIDTH-1:0]  s_axi_rdata,
    output reg  [1:0]             s_axi_rresp,
    output reg                    s_axi_rlast,
    output reg                    s_axi_rvalid,
    input  wire                   s_axi_rready,

    // -------------------------------------------------------------------------
    // AXI4-Lite Master Interface (to CSR Cluster)
    // -------------------------------------------------------------------------
    output reg  [ADDR_WIDTH-1:0]  m_axil_awaddr,
    output reg  [2:0]             m_axil_awprot,
    output reg                    m_axil_awvalid,
    input  wire                   m_axil_awready,

    output reg  [DATA_WIDTH-1:0]  m_axil_wdata,
    output reg  [(DATA_WIDTH/8)-1:0] m_axil_wstrb,
    output reg                    m_axil_wvalid,
    input  wire                   m_axil_wready,

    input  wire [1:0]             m_axil_bresp,
    input  wire                   m_axil_bvalid,
    output reg                    m_axil_bready,

    output reg  [ADDR_WIDTH-1:0]  m_axil_araddr,
    output reg  [2:0]             m_axil_arprot,
    output reg                    m_axil_arvalid,
    input  wire                   m_axil_arready,

    input  wire [DATA_WIDTH-1:0]  m_axil_rdata,
    input  wire [1:0]             m_axil_rresp,
    input  wire                   m_axil_rvalid,
    output reg                    m_axil_rready
);

    // Write Bridge FSM
    localparam WB_IDLE  = 2'd0;
    localparam WB_ADDR  = 2'd1;
    localparam WB_DATA  = 2'd2;
    localparam WB_RESP  = 2'd3;

    reg [1:0] wb_state;
    reg [ID_WIDTH-1:0] latched_awid;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wb_state       <= WB_IDLE;
            s_axi_awready  <= 1'b0;
            s_axi_wready   <= 1'b0;
            s_axi_bvalid   <= 1'b0;
            s_axi_bid      <= {ID_WIDTH{1'b0}};
            s_axi_bresp    <= `AXI_RESP_OKAY;
            m_axil_awvalid <= 1'b0;
            m_axil_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axil_awprot  <= 3'd0;
            m_axil_wvalid  <= 1'b0;
            m_axil_wdata   <= {DATA_WIDTH{1'b0}};
            m_axil_wstrb   <= {(DATA_WIDTH/8){1'b0}};
            m_axil_bready  <= 1'b0;
            latched_awid   <= {ID_WIDTH{1'b0}};
        end else begin
            case (wb_state)
                WB_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    if (s_axi_awvalid) begin
                        s_axi_awready  <= 1'b1;
                        latched_awid   <= s_axi_awid;
                        m_axil_awaddr  <= s_axi_awaddr;
                        m_axil_awvalid <= 1'b1;
                        wb_state       <= WB_ADDR;
                    end
                end

                WB_ADDR: begin
                    s_axi_awready <= 1'b0;
                    if (m_axil_awready && m_axil_awvalid) begin
                        m_axil_awvalid <= 1'b0;
                    end
                    if (s_axi_wvalid) begin
                        s_axi_wready  <= 1'b1;
                        m_axil_wdata  <= s_axi_wdata;
                        m_axil_wstrb  <= s_axi_wstrb;
                        m_axil_wvalid <= 1'b1;
                        wb_state      <= WB_DATA;
                    end
                end

                WB_DATA: begin
                    s_axi_wready <= 1'b0;
                    if (m_axil_wready && m_axil_wvalid) begin
                        m_axil_wvalid <= 1'b0;
                        m_axil_bready <= 1'b1;
                        wb_state      <= WB_RESP;
                    end
                end

                WB_RESP: begin
                    if (m_axil_bvalid && m_axil_bready) begin
                        m_axil_bready <= 1'b0;
                        s_axi_bid     <= latched_awid;
                        s_axi_bresp   <= m_axil_bresp;
                        s_axi_bvalid  <= 1'b1;
                    end
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wb_state     <= WB_IDLE;
                    end
                end
            endcase
        end
    end

    // Read Bridge FSM
    localparam RB_IDLE = 2'd0;
    localparam RB_ADDR = 2'd1;
    localparam RB_DATA = 2'd2;

    reg [1:0] rb_state;
    reg [ID_WIDTH-1:0] latched_arid;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rb_state       <= RB_IDLE;
            s_axi_arready  <= 1'b0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rid      <= {ID_WIDTH{1'b0}};
            s_axi_rdata    <= {DATA_WIDTH{1'b0}};
            s_axi_rresp    <= `AXI_RESP_OKAY;
            s_axi_rlast    <= 1'b0;
            m_axil_arvalid <= 1'b0;
            m_axil_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axil_arprot  <= 3'd0;
            m_axil_rready  <= 1'b0;
            latched_arid   <= {ID_WIDTH{1'b0}};
        end else begin
            case (rb_state)
                RB_IDLE: begin
                    s_axi_rvalid <= 1'b0;
                    s_axi_rlast  <= 1'b0;
                    if (s_axi_arvalid) begin
                        s_axi_arready  <= 1'b1;
                        latched_arid   <= s_axi_arid;
                        m_axil_araddr  <= s_axi_araddr;
                        m_axil_arvalid <= 1'b1;
                        rb_state       <= RB_ADDR;
                    end
                end

                RB_ADDR: begin
                    s_axi_arready <= 1'b0;
                    if (m_axil_arready && m_axil_arvalid) begin
                        m_axil_arvalid <= 1'b0;
                        m_axil_rready  <= 1'b1;
                        rb_state       <= RB_DATA;
                    end
                end

                RB_DATA: begin
                    if (m_axil_rvalid && m_axil_rready) begin
                        m_axil_rready <= 1'b0;
                        s_axi_rid     <= latched_arid;
                        s_axi_rdata   <= m_axil_rdata;
                        s_axi_rresp   <= m_axil_rresp;
                        s_axi_rlast   <= 1'b1; // Always single-beat for AXI4-Lite
                        s_axi_rvalid  <= 1'b1;
                    end
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        s_axi_rlast  <= 1'b0;
                        rb_state     <= RB_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
