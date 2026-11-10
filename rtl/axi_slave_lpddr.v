// =============================================================================
// Brain Condition Detector (BCD) SoC - External LPDDR Controller Slave S1 (AXI4-Full)
// Address Range: 0x8000_0000 - 0xBFFF_FFFF (up to 1 GiB)
// Used for Swin Transformer weights, attention tokens, feature maps, and framebuffers.
// High-bandwidth burst support with INCR wrap-around simulation memory.
// =============================================================================

`include "bcd_soc_pkg.vh"

module axi_slave_lpddr #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 4,
    parameter MEM_DEPTH  = 2048,
    parameter INIT_FILE  = ""   // External LPDDR4 image (e.g. "mem/lpddr.hex")
)(
    input  wire                   aclk,
    input  wire                   aresetn,

    // AXI4-Full Write Channels
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awvalid,
    output reg                    s_axi_awready,

    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output reg                    s_axi_wready,

    output reg  [ID_WIDTH-1:0]    s_axi_bid,
    output reg  [1:0]             s_axi_bresp,
    output reg                    s_axi_bvalid,
    input  wire                   s_axi_bready,

    // AXI4-Full Read Channels
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
    input  wire                   s_axi_rready
);

    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1) mem[i] = 32'h8000_0000 + i;

        // Load external LPDDR4 memory image if provided
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    localparam W_IDLE  = 2'd0;
    localparam W_BURST = 2'd1;
    localparam W_RESP  = 2'd2;

    reg [1:0] w_state;
    reg [ID_WIDTH-1:0] write_id;
    reg [ADDR_WIDTH-1:0] write_addr;
    reg [7:0] write_len;
    reg [7:0] write_count;

    wire [ADDR_WIDTH-1:0] current_write_word = (write_addr[12:2] + write_count) % MEM_DEPTH;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            w_state       <= W_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bid     <= {ID_WIDTH{1'b0}};
            s_axi_bresp   <= `AXI_RESP_OKAY;
            write_id      <= {ID_WIDTH{1'b0}};
            write_addr    <= {ADDR_WIDTH{1'b0}};
            write_len     <= 8'd0;
            write_count   <= 8'd0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    if (s_axi_awvalid) begin
                        s_axi_awready <= 1'b1;
                        write_id      <= s_axi_awid;
                        write_addr    <= s_axi_awaddr - `ADDR_BASE_LPDDR;
                        write_len     <= s_axi_awlen;
                        write_count   <= 8'd0;
                        w_state       <= W_BURST;
                    end
                end

                W_BURST: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b1;
                    if (s_axi_wvalid && s_axi_wready) begin
                        mem[current_write_word] <= s_axi_wdata;
                        if (s_axi_wlast || (write_count == write_len)) begin
                            s_axi_wready <= 1'b0;
                            s_axi_bid    <= write_id;
                            s_axi_bresp  <= `AXI_RESP_OKAY;
                            s_axi_bvalid <= 1'b1;
                            w_state      <= W_RESP;
                        end else begin
                            write_count <= write_count + 8'd1;
                        end
                    end
                end

                W_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        w_state      <= W_IDLE;
                    end
                end
            endcase
        end
    end

    localparam R_IDLE  = 1'd0;
    localparam R_BURST = 1'd1;

    reg r_state;
    reg [ID_WIDTH-1:0] read_id;
    reg [ADDR_WIDTH-1:0] read_addr;
    reg [7:0] read_len;
    reg [7:0] read_count;

    wire [ADDR_WIDTH-1:0] current_read_word = (read_addr[12:2] + read_count) % MEM_DEPTH;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            r_state       <= R_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rlast   <= 1'b0;
            s_axi_rid     <= {ID_WIDTH{1'b0}};
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
            s_axi_rresp   <= `AXI_RESP_OKAY;
            read_id       <= {ID_WIDTH{1'b0}};
            read_addr     <= {ADDR_WIDTH{1'b0}};
            read_len      <= 8'd0;
            read_count    <= 8'd0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    s_axi_rvalid <= 1'b0;
                    s_axi_rlast  <= 1'b0;
                    if (s_axi_arvalid) begin
                        s_axi_arready <= 1'b1;
                        read_id       <= s_axi_arid;
                        read_addr     <= s_axi_araddr - `ADDR_BASE_LPDDR;
                        read_len      <= s_axi_arlen;
                        read_count    <= 8'd0;
                        r_state       <= R_BURST;
                    end
                end

                R_BURST: begin
                    s_axi_arready <= 1'b0;
                    if (!s_axi_rvalid || (s_axi_rvalid && s_axi_rready)) begin
                        s_axi_rid    <= read_id;
                        s_axi_rdata  <= mem[current_read_word];
                        s_axi_rresp  <= `AXI_RESP_OKAY;
                        s_axi_rvalid <= 1'b1;
                        s_axi_rlast  <= (read_count == read_len);

                        if (read_count == read_len) begin
                            r_state <= R_IDLE;
                        end else begin
                            read_count <= read_count + 8'd1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
