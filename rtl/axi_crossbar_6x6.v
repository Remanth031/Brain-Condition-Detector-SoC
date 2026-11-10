// =============================================================================
// Brain Condition Detector (BCD) SoC - 6x6 AXI4 Interconnect / Crossbar
// Fully connects 6 AXI4 Masters to 6 AXI4 Slaves with Address Decoding,
// QoS/Priority Arbitration, and DECERR Handling.
// =============================================================================

`include "bcd_soc_pkg.vh"

module axi_crossbar_6x6 #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH / 8),
    parameter ID_WIDTH   = 4,
    parameter NUM_MASTERS = 6,
    parameter NUM_SLAVES  = 6
)(
    input  wire                   aclk,
    input  wire                   aresetn,

    // -------------------------------------------------------------------------
    // Master Interfaces (M0 to M5)
    // -------------------------------------------------------------------------
    // Write Address Channel
    input  wire [NUM_MASTERS*ID_WIDTH-1:0]    s_axi_awid,
    input  wire [NUM_MASTERS*ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [NUM_MASTERS*8-1:0]           s_axi_awlen,
    input  wire [NUM_MASTERS*3-1:0]           s_axi_awsize,
    input  wire [NUM_MASTERS*2-1:0]           s_axi_awburst,
    input  wire [NUM_MASTERS*4-1:0]           s_axi_awqos,
    input  wire [NUM_MASTERS-1:0]             s_axi_awvalid,
    output reg  [NUM_MASTERS-1:0]             s_axi_awready,

    // Write Data Channel
    input  wire [NUM_MASTERS*DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [NUM_MASTERS*STRB_WIDTH-1:0]  s_axi_wstrb,
    input  wire [NUM_MASTERS-1:0]             s_axi_wlast,
    input  wire [NUM_MASTERS-1:0]             s_axi_wvalid,
    output reg  [NUM_MASTERS-1:0]             s_axi_wready,

    // Write Response Channel
    output reg  [NUM_MASTERS*ID_WIDTH-1:0]    s_axi_bid,
    output reg  [NUM_MASTERS*2-1:0]           s_axi_bresp,
    output reg  [NUM_MASTERS-1:0]             s_axi_bvalid,
    input  wire [NUM_MASTERS-1:0]             s_axi_bready,

    // Read Address Channel
    input  wire [NUM_MASTERS*ID_WIDTH-1:0]    s_axi_arid,
    input  wire [NUM_MASTERS*ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [NUM_MASTERS*8-1:0]           s_axi_arlen,
    input  wire [NUM_MASTERS*3-1:0]           s_axi_arsize,
    input  wire [NUM_MASTERS*2-1:0]           s_axi_arburst,
    input  wire [NUM_MASTERS*4-1:0]           s_axi_arqos,
    input  wire [NUM_MASTERS-1:0]             s_axi_arvalid,
    output reg  [NUM_MASTERS-1:0]             s_axi_arready,

    // Read Data Channel
    output reg  [NUM_MASTERS*ID_WIDTH-1:0]    s_axi_rid,
    output reg  [NUM_MASTERS*DATA_WIDTH-1:0]  s_axi_rdata,
    output reg  [NUM_MASTERS*2-1:0]           s_axi_rresp,
    output reg  [NUM_MASTERS-1:0]             s_axi_rlast,
    output reg  [NUM_MASTERS-1:0]             s_axi_rvalid,
    input  wire [NUM_MASTERS-1:0]             s_axi_rready,

    // -------------------------------------------------------------------------
    // Slave Interfaces (S0 to S5)
    // S0: ROM, S1: SRAM, S2: Scratchpad, S3: CSR Bridge, S4: NVM, S5: LPDDR
    // -------------------------------------------------------------------------
    // Write Address Channel
    output reg  [NUM_SLAVES*ID_WIDTH-1:0]     m_axi_awid,
    output reg  [NUM_SLAVES*ADDR_WIDTH-1:0]   m_axi_awaddr,
    output reg  [NUM_SLAVES*8-1:0]            m_axi_awlen,
    output reg  [NUM_SLAVES*3-1:0]            m_axi_awsize,
    output reg  [NUM_SLAVES*2-1:0]            m_axi_awburst,
    output reg  [NUM_SLAVES-1:0]              m_axi_awvalid,
    input  wire [NUM_SLAVES-1:0]              m_axi_awready,

    // Write Data Channel
    output reg  [NUM_SLAVES*DATA_WIDTH-1:0]   m_axi_wdata,
    output reg  [NUM_SLAVES*STRB_WIDTH-1:0]   m_axi_wstrb,
    output reg  [NUM_SLAVES-1:0]              m_axi_wlast,
    output reg  [NUM_SLAVES-1:0]              m_axi_wvalid,
    input  wire [NUM_SLAVES-1:0]              m_axi_wready,

    // Write Response Channel
    input  wire [NUM_SLAVES*ID_WIDTH-1:0]     m_axi_bid,
    input  wire [NUM_SLAVES*2-1:0]            m_axi_bresp,
    input  wire [NUM_SLAVES-1:0]              m_axi_bvalid,
    output reg  [NUM_SLAVES-1:0]              m_axi_bready,

    // Read Address Channel
    output reg  [NUM_SLAVES*ID_WIDTH-1:0]     m_axi_arid,
    output reg  [NUM_SLAVES*ADDR_WIDTH-1:0]   m_axi_araddr,
    output reg  [NUM_SLAVES*8-1:0]            m_axi_arlen,
    output reg  [NUM_SLAVES*3-1:0]            m_axi_arsize,
    output reg  [NUM_SLAVES*2-1:0]            m_axi_arburst,
    output reg  [NUM_SLAVES-1:0]              m_axi_arvalid,
    input  wire [NUM_SLAVES-1:0]              m_axi_arready,

    // Read Data Channel
    input  wire [NUM_SLAVES*ID_WIDTH-1:0]     m_axi_rid,
    input  wire [NUM_SLAVES*DATA_WIDTH-1:0]   m_axi_rdata,
    input  wire [NUM_SLAVES*2-1:0]            m_axi_rresp,
    input  wire [NUM_SLAVES-1:0]              m_axi_rlast,
    input  wire [NUM_SLAVES-1:0]              m_axi_rvalid,
    output reg  [NUM_SLAVES-1:0]              m_axi_rready
);

    // =========================================================================
    // Address Decoding Function
    // Maps a 32-bit address to Slave Index (0..5) or 6 for DECERR
    // =========================================================================
    function [2:0] decode_address;
        input [ADDR_WIDTH-1:0] addr;
        begin
            if (addr >= `ADDR_BASE_ROM && addr < (`ADDR_BASE_ROM + `ADDR_SIZE_ROM))
                decode_address = 3'd0; // S0: Boot ROM
            else if (addr >= `ADDR_BASE_SRAM && addr < (`ADDR_BASE_SRAM + `ADDR_SIZE_SRAM))
                decode_address = 3'd1; // S1: On-chip SRAM
            else if (addr >= `ADDR_BASE_SCRATCHPAD && addr < (`ADDR_BASE_SCRATCHPAD + `ADDR_SIZE_SCRATCHPAD))
                decode_address = 3'd2; // S2: Scratchpad
            else if (addr >= `ADDR_BASE_CSR_BRIDGE && addr < (`ADDR_BASE_CSR_BRIDGE + `ADDR_SIZE_CSR_BRIDGE))
                decode_address = 3'd3; // S3: CSR Bridge
            else if (addr >= `ADDR_BASE_NVM && addr < (`ADDR_BASE_NVM + `ADDR_SIZE_NVM))
                decode_address = 3'd4; // S4: QSPI NVM
            else if (addr >= `ADDR_BASE_LPDDR && addr < (`ADDR_BASE_LPDDR + `ADDR_SIZE_LPDDR))
                decode_address = 3'd5; // S5: LPDDR
            else
                decode_address = 3'd6; // Unmapped -> DECERR
        end
    endfunction

    // =========================================================================
    // Write Transaction Routing & State Machine
    // =========================================================================
    localparam W_IDLE     = 2'd0;
    localparam W_DATA     = 2'd1;
    localparam W_RESP     = 2'd2;
    localparam W_DECERR   = 2'd3;

    reg [1:0] w_state;
    reg [2:0] active_w_master;
    reg [2:0] active_w_slave;
    reg [ID_WIDTH-1:0] active_w_id;
    reg [7:0] w_beat_count;
    reg [7:0] w_total_beats;

    // Decode target slave for each master's AWADDR
    wire [2:0] aw_target_slave [NUM_MASTERS-1:0];
    genvar gm;
    generate
        for (gm = 0; gm < NUM_MASTERS; gm = gm + 1) begin: GEN_AW_DECODE
            assign aw_target_slave[gm] = decode_address(s_axi_awaddr[gm*ADDR_WIDTH +: ADDR_WIDTH]);
        end
    endgenerate

    // Write Arbiter: Priority + QoS + Round Robin
    function [2:0] select_w_master;
        input [NUM_MASTERS-1:0] valid;
        input [NUM_MASTERS*4-1:0] qos;
        reg [3:0] max_qos;
        reg [2:0] best_m;
        integer i;
        begin
            max_qos = 4'd0;
            best_m  = 3'd0;
            // First check priority with QoS: Swin (M3) and DMA (M1) priority boost
            for (i = NUM_MASTERS-1; i >= 0; i = i - 1) begin
                if (valid[i]) begin
                    if (qos[i*4 +: 4] >= max_qos) begin
                        max_qos = qos[i*4 +: 4];
                        best_m = i[2:0];
                    end
                end
            end
            select_w_master = best_m;
        end
    endfunction

    // =========================================================================
    // Read Transaction Routing & State Machine
    // =========================================================================
    localparam R_IDLE   = 2'd0;
    localparam R_DATA   = 2'd1;
    localparam R_DECERR = 2'd2;

    reg [1:0] r_state;
    reg [2:0] active_r_master;
    reg [2:0] active_r_slave;
    reg [ID_WIDTH-1:0] active_r_id;
    reg [7:0] r_beat_count;
    reg [7:0] r_total_beats;

    wire [2:0] ar_target_slave [NUM_MASTERS-1:0];
    generate
        for (gm = 0; gm < NUM_MASTERS; gm = gm + 1) begin: GEN_AR_DECODE
            assign ar_target_slave[gm] = decode_address(s_axi_araddr[gm*ADDR_WIDTH +: ADDR_WIDTH]);
        end
    endgenerate

    // Read Arbiter: Priority + QoS
    function [2:0] select_r_master;
        input [NUM_MASTERS-1:0] valid;
        input [NUM_MASTERS*4-1:0] qos;
        reg [3:0] max_qos;
        reg [2:0] best_m;
        integer i;
        begin
            max_qos = 4'd0;
            best_m  = 3'd0;
            for (i = NUM_MASTERS-1; i >= 0; i = i - 1) begin
                if (valid[i]) begin
                    if (qos[i*4 +: 4] >= max_qos) begin
                        max_qos = qos[i*4 +: 4];
                        best_m = i[2:0];
                    end
                end
            end
            select_r_master = best_m;
        end
    endfunction

    // =========================================================================
    // Write Data Path Logic
    // =========================================================================
    integer sm, ss;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            w_state          <= W_IDLE;
            active_w_master  <= 3'd0;
            active_w_slave   <= 3'd0;
            active_w_id      <= {ID_WIDTH{1'b0}};
            w_beat_count     <= 8'd0;
            w_total_beats    <= 8'd0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    if (|s_axi_awvalid) begin
                        active_w_master <= select_w_master(s_axi_awvalid, s_axi_awqos);
                        active_w_id     <= s_axi_awid[select_w_master(s_axi_awvalid, s_axi_awqos)*ID_WIDTH +: ID_WIDTH];
                        w_total_beats   <= s_axi_awlen[select_w_master(s_axi_awvalid, s_axi_awqos)*8 +: 8];
                        w_beat_count    <= 8'd0;
                        
                        if (aw_target_slave[select_w_master(s_axi_awvalid, s_axi_awqos)] == 3'd6) begin
                            // Unmapped address -> Route to internal DECERR handler
                            active_w_slave <= 3'd6;
                            w_state        <= W_DECERR;
                        end else begin
                            active_w_slave <= aw_target_slave[select_w_master(s_axi_awvalid, s_axi_awqos)];
                            // Handshake AW if target slave is ready
                            if (m_axi_awready[aw_target_slave[select_w_master(s_axi_awvalid, s_axi_awqos)]]) begin
                                w_state <= W_DATA;
                            end
                        end
                    end
                end

                W_DATA: begin
                    if (s_axi_wvalid[active_w_master] && m_axi_wready[active_w_slave]) begin
                        if (s_axi_wlast[active_w_master] || (w_beat_count == w_total_beats)) begin
                            w_state <= W_RESP;
                        end else begin
                            w_beat_count <= w_beat_count + 8'd1;
                        end
                    end
                end

                W_RESP: begin
                    if (m_axi_bvalid[active_w_slave] && s_axi_bready[active_w_master]) begin
                        w_state <= W_IDLE;
                    end
                end

                W_DECERR: begin
                    // Consume any W payload for this unmapped transaction
                    if (s_axi_wvalid[active_w_master]) begin
                        if (s_axi_wlast[active_w_master] || (w_beat_count == w_total_beats)) begin
                            if (s_axi_bready[active_w_master]) begin
                                w_state <= W_IDLE;
                            end
                        end else begin
                            w_beat_count <= w_beat_count + 8'd1;
                        end
                    end
                end
            endcase
        end
    end

    // Combinational Write Channel Steering
    always @(*) begin
        // Defaults for Masters
        s_axi_awready = {NUM_MASTERS{1'b0}};
        s_axi_wready  = {NUM_MASTERS{1'b0}};
        s_axi_bid     = {NUM_MASTERS*ID_WIDTH{1'b0}};
        s_axi_bresp   = {NUM_MASTERS*2{1'b0}};
        s_axi_bvalid  = {NUM_MASTERS{1'b0}};

        // Defaults for Slaves
        m_axi_awid    = {NUM_SLAVES*ID_WIDTH{1'b0}};
        m_axi_awaddr  = {NUM_SLAVES*ADDR_WIDTH{1'b0}};
        m_axi_awlen   = {NUM_SLAVES*8{1'b0}};
        m_axi_awsize  = {NUM_SLAVES*3{1'b0}};
        m_axi_awburst = {NUM_SLAVES*2{1'b0}};
        m_axi_awvalid = {NUM_SLAVES{1'b0}};
        m_axi_wdata   = {NUM_SLAVES*DATA_WIDTH{1'b0}};
        m_axi_wstrb   = {NUM_SLAVES*STRB_WIDTH{1'b0}};
        m_axi_wlast   = {NUM_SLAVES{1'b0}};
        m_axi_wvalid  = {NUM_SLAVES{1'b0}};
        m_axi_bready  = {NUM_SLAVES{1'b0}};

        case (w_state)
            W_IDLE: begin
                if (|s_axi_awvalid) begin
                    if (aw_target_slave[select_w_master(s_axi_awvalid, s_axi_awqos)] == 3'd6) begin
                        // Accept address immediately for DECERR
                        s_axi_awready[select_w_master(s_axi_awvalid, s_axi_awqos)] = 1'b1;
                    end else begin
                        // Forward AW to target slave
                        m_axi_awid[aw_target_slave[select_w_master(s_axi_awvalid, s_axi_awqos)]*ID_WIDTH +: ID_WIDTH]
                            = s_axi_awid[select_w_master(s_axi_awvalid, s_axi_awqos)]*ID_WIDTH +: ID_WIDTH];
                        m_axi_awaddr[aw_target_slave[select_w_master(s_axi_awvalid, s_axi_awqos)]*ADDR_WIDTH +: ADDR_WIDTH]
                            = s_axi_awaddr[select_w_master(s_axi_awvalid, s_axi_awqos)*ADDR_WIDTH +: ADDR_WIDTH];
                        m_axi_awlen[aw_target_slave[select_w_master(s_axi_awvalid, s_axi_awqos)]*8 +: 8]
                            = s_axi_awlen[select_w_master(s_axi_awvalid, s_axi_awqos)*8 +: 8];
                        m_axi_awsize[aw_target_slave[select_w_master(s_axi_awvalid, s_axi_awqos)]*3 +: 3]
                            = s_axi_awsize[select_w_master(s_axi_awvalid, s_axi_awqos)*3 +: 3];
                        m_axi_awburst[aw_target_slave[select_w_master(s_axi_awvalid, s_axi_awqos)]*2 +: 2]
                            = s_axi_awburst[select_w_master(s_axi_awvalid, s_axi_awqos)*2 +: 2];
                        m_axi_awvalid[aw_target_slave[select_w_master(s_axi_awvalid, s_axi_awqos)]] = 1'b1;
                        s_axi_awready[select_w_master(s_axi_awvalid, s_axi_awqos)]
                            = m_axi_awready[aw_target_slave[select_w_master(s_axi_awvalid, s_axi_awqos)]];
                    end
                end
            end

            W_DATA: begin
                // Forward W channel between active master and active slave
                m_axi_wdata[active_w_slave*DATA_WIDTH +: DATA_WIDTH] = s_axi_wdata[active_w_master*DATA_WIDTH +: DATA_WIDTH];
                m_axi_wstrb[active_w_slave*STRB_WIDTH +: STRB_WIDTH] = s_axi_wstrb[active_w_master*STRB_WIDTH +: STRB_WIDTH];
                m_axi_wlast[active_w_slave]                          = s_axi_wlast[active_w_master];
                m_axi_wvalid[active_w_slave]                         = s_axi_wvalid[active_w_master];
                s_axi_wready[active_w_master]                        = m_axi_wready[active_w_slave];
            end

            W_RESP: begin
                // Forward B channel
                s_axi_bid[active_w_master*ID_WIDTH +: ID_WIDTH] = m_axi_bid[active_w_slave*ID_WIDTH +: ID_WIDTH];
                s_axi_bresp[active_w_master*2 +: 2]             = m_axi_bresp[active_w_slave*2 +: 2];
                s_axi_bvalid[active_w_master]                   = m_axi_bvalid[active_w_slave];
                m_axi_bready[active_w_slave]                    = s_axi_bready[active_w_master];
            end

            W_DECERR: begin
                s_axi_wready[active_w_master] = 1'b1;
                if (s_axi_wvalid[active_w_master] && (s_axi_wlast[active_w_master] || (w_beat_count == w_total_beats))) begin
                    s_axi_bid[active_w_master*ID_WIDTH +: ID_WIDTH] = active_w_id;
                    s_axi_bresp[active_w_master*2 +: 2]             = `AXI_RESP_DECERR;
                    s_axi_bvalid[active_w_master]                   = 1'b1;
                end
            end
        endcase
    end

    // =========================================================================
    // Read Data Path Logic
    // =========================================================================
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            r_state         <= R_IDLE;
            active_r_master <= 3'd0;
            active_r_slave  <= 3'd0;
            active_r_id     <= {ID_WIDTH{1'b0}};
            r_beat_count    <= 8'd0;
            r_total_beats   <= 8'd0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    if (|s_axi_arvalid) begin
                        active_r_master <= select_r_master(s_axi_arvalid, s_axi_arqos);
                        active_r_id     <= s_axi_arid[select_r_master(s_axi_arvalid, s_axi_arqos)*ID_WIDTH +: ID_WIDTH];
                        r_total_beats   <= s_axi_arlen[select_r_master(s_axi_arvalid, s_axi_arqos)*8 +: 8];
                        r_beat_count    <= 8'd0;

                        if (ar_target_slave[select_r_master(s_axi_arvalid, s_axi_arqos)] == 3'd6) begin
                            active_r_slave <= 3'd6;
                            r_state        <= R_DECERR;
                        end else begin
                            active_r_slave <= ar_target_slave[select_r_master(s_axi_arvalid, s_axi_arqos)];
                            if (m_axi_arready[ar_target_slave[select_r_master(s_axi_arvalid, s_axi_arqos)]]) begin
                                r_state <= R_DATA;
                            end
                        end
                    end
                end

                R_DATA: begin
                    if (m_axi_rvalid[active_r_slave] && s_axi_rready[active_r_master]) begin
                        if (m_axi_rlast[active_r_slave] || (r_beat_count == r_total_beats)) begin
                            r_state <= R_IDLE;
                        end else begin
                            r_beat_count <= r_beat_count + 8'd1;
                        end
                    end
                end

                R_DECERR: begin
                    if (s_axi_rready[active_r_master]) begin
                        if (r_beat_count == r_total_beats) begin
                            r_state <= R_IDLE;
                        end else begin
                            r_beat_count <= r_beat_count + 8'd1;
                        end
                    end
                end
            endcase
        end
    end

    // Combinational Read Channel Steering
    always @(*) begin
        s_axi_arready = {NUM_MASTERS{1'b0}};
        s_axi_rid     = {NUM_MASTERS*ID_WIDTH{1'b0}};
        s_axi_rdata   = {NUM_MASTERS*DATA_WIDTH{1'b0}};
        s_axi_rresp   = {NUM_MASTERS*2{1'b0}};
        s_axi_rlast   = {NUM_MASTERS{1'b0}};
        s_axi_rvalid  = {NUM_MASTERS{1'b0}};

        m_axi_arid    = {NUM_SLAVES*ID_WIDTH{1'b0}};
        m_axi_araddr  = {NUM_SLAVES*ADDR_WIDTH{1'b0}};
        m_axi_arlen   = {NUM_SLAVES*8{1'b0}};
        m_axi_arsize  = {NUM_SLAVES*3{1'b0}};
        m_axi_arburst = {NUM_SLAVES*2{1'b0}};
        m_axi_arvalid = {NUM_SLAVES{1'b0}};
        m_axi_rready  = {NUM_SLAVES{1'b0}};

        case (r_state)
            R_IDLE: begin
                if (|s_axi_arvalid) begin
                    if (ar_target_slave[select_r_master(s_axi_arvalid, s_axi_arqos)] == 3'd6) begin
                        s_axi_arready[select_r_master(s_axi_arvalid, s_axi_arqos)] = 1'b1;
                    end else begin
                        m_axi_arid[ar_target_slave[select_r_master(s_axi_arvalid, s_axi_arqos)]*ID_WIDTH +: ID_WIDTH]
                            = s_axi_arid[select_r_master(s_axi_arvalid, s_axi_arqos)*ID_WIDTH +: ID_WIDTH];
                        m_axi_araddr[ar_target_slave[select_r_master(s_axi_arvalid, s_axi_arqos)]*ADDR_WIDTH +: ADDR_WIDTH]
                            = s_axi_araddr[select_r_master(s_axi_arvalid, s_axi_arqos)*ADDR_WIDTH +: ADDR_WIDTH];
                        m_axi_arlen[ar_target_slave[select_r_master(s_axi_arvalid, s_axi_arqos)]*8 +: 8]
                            = s_axi_arlen[select_r_master(s_axi_arvalid, s_axi_arqos)*8 +: 8];
                        m_axi_arsize[ar_target_slave[select_r_master(s_axi_arvalid, s_axi_arqos)]*3 +: 3]
                            = s_axi_arsize[select_r_master(s_axi_arvalid, s_axi_arqos)*3 +: 3];
                        m_axi_arburst[ar_target_slave[select_r_master(s_axi_arvalid, s_axi_arqos)]*2 +: 2]
                            = s_axi_arburst[select_r_master(s_axi_arvalid, s_axi_arqos)*2 +: 2];
                        m_axi_arvalid[ar_target_slave[select_r_master(s_axi_arvalid, s_axi_arqos)]] = 1'b1;
                        s_axi_arready[select_r_master(s_axi_arvalid, s_axi_arqos)]
                            = m_axi_arready[ar_target_slave[select_r_master(s_axi_arvalid, s_axi_arqos)]];
                    end
                end
            end

            R_DATA: begin
                s_axi_rid[active_r_master*ID_WIDTH +: ID_WIDTH]       = m_axi_rid[active_r_slave*ID_WIDTH +: ID_WIDTH];
                s_axi_rdata[active_r_master*DATA_WIDTH +: DATA_WIDTH] = m_axi_rdata[active_r_slave*DATA_WIDTH +: DATA_WIDTH];
                s_axi_rresp[active_r_master*2 +: 2]                   = m_axi_rresp[active_r_slave*2 +: 2];
                s_axi_rlast[active_r_master]                          = m_axi_rlast[active_r_slave];
                s_axi_rvalid[active_r_master]                         = m_axi_rvalid[active_r_slave];
                m_axi_rready[active_r_slave]                          = s_axi_rready[active_r_master];
            end

            R_DECERR: begin
                s_axi_rid[active_r_master*ID_WIDTH +: ID_WIDTH]       = active_r_id;
                s_axi_rdata[active_r_master*DATA_WIDTH +: DATA_WIDTH] = 32'hDEAD_DEAD;
                s_axi_rresp[active_r_master*2 +: 2]                   = `AXI_RESP_DECERR;
                s_axi_rlast[active_r_master]                          = (r_beat_count == r_total_beats);
                s_axi_rvalid[active_r_master]                         = 1'b1;
            end
        endcase
    end

endmodule
