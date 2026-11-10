// =============================================================================
// Brain Condition Detector (BCD) SoC - Boot ROM Slave (AXI4-Full)
// Address Range: 0x0000_0000 - 0x0000_FFFF (64 KiB)
// Read-only memory; any write transaction returns AXI SLVERR (2'b10).
// =============================================================================

`include "bcd_soc_pkg.vh"

module axi_slave_rom #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 4,
    parameter ROM_DEPTH  = 256, // Configurable simulation depth (e.g. 256 words)
    parameter INIT_FILE  = ""  // External hex file path (e.g. "mem/boot.hex")
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

    // Internal ROM Array
    reg [DATA_WIDTH-1:0] rom_mem [0:ROM_DEPTH-1];
    integer i;
    initial begin
        // Initialize with default BCD boot code / signature
        rom_mem[0] = 32'h6263_6431; // "bcd1"
        rom_mem[1] = 32'h0000_0013; // nop
        rom_mem[2] = 32'h0000_0093; // nop
        rom_mem[3] = 32'hCAFE_BABE; // Boot vector magic
        for (i = 4; i < ROM_DEPTH; i = i + 1) begin
            rom_mem[i] = 32'h1000_0000 + i;
        end

        // Load external memory image if provided
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, rom_mem);
        end
    end

    // -------------------------------------------------------------------------
    // Write Channel Logic: Always reject writes with SLVERR
    // -------------------------------------------------------------------------
    localparam W_IDLE  = 2'd0;
    localparam W_BURST = 2'd1;
    localparam W_RESP  = 2'd2;

    reg [1:0] w_state;
    reg [ID_WIDTH-1:0] write_id;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            w_state       <= W_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bid     <= {ID_WIDTH{1'b0}};
            s_axi_bresp   <= `AXI_RESP_OKAY;
            write_id      <= {ID_WIDTH{1'b0}};
        end else begin
            case (w_state)
                W_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    if (s_axi_awvalid) begin
                        s_axi_awready <= 1'b1;
                        write_id      <= s_axi_awid;
                        w_state       <= W_BURST;
                    end
                end

                W_BURST: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b1;
                    if (s_axi_wvalid && s_axi_wready) begin
                        if (s_axi_wlast) begin
                            s_axi_wready <= 1'b0;
                            s_axi_bid    <= write_id;
                            s_axi_bresp  <= `AXI_RESP_SLVERR; // Write Violation Error
                            s_axi_bvalid <= 1'b1;
                            w_state      <= W_RESP;
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

    // -------------------------------------------------------------------------
    // Read Channel Logic: Serve ROM contents
    // -------------------------------------------------------------------------
    localparam R_IDLE  = 1'd0;
    localparam R_BURST = 1'd1;

    reg r_state;
    reg [ID_WIDTH-1:0] read_id;
    reg [ADDR_WIDTH-1:0] read_addr;
    reg [7:0] read_len;
    reg [7:0] read_count;

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
                        read_addr     <= s_axi_araddr - `ADDR_BASE_ROM;
                        read_len      <= s_axi_arlen;
                        read_count    <= 8'd0;
                        r_state       <= R_BURST;
                    end
                end

                R_BURST: begin
                    s_axi_arready <= 1'b0;
                    if (!s_axi_rvalid || (s_axi_rvalid && s_axi_rready)) begin
                        s_axi_rid    <= read_id;
                        s_axi_rdata  <= rom_mem[(read_addr[9:2] + read_count) % ROM_DEPTH];
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
