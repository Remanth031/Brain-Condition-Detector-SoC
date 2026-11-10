// =============================================================================
// Brain Condition Detector (BCD) SoC - RTL Threshold Engine
// Section 4.4 Register Map (Base: 0x4002_0000)
// Evaluates Line-Length, Band-Power Ratios, Spectral Entropy, and N-of-M Voting.
// Manages Abnormal event interrupts and Wake-up Target controls.
// =============================================================================

`include "bcd_soc_pkg.vh"

module rtl_threshold_engine #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire                  aclk,
    input  wire                  aresetn,

    // AXI4-Lite Register Interface
    input  wire [ADDR_WIDTH-1:0] s_axil_awaddr,
    input  wire                  s_axil_awvalid,
    output reg                   s_axil_awready,

    input  wire [DATA_WIDTH-1:0] s_axil_wdata,
    input  wire [3:0]            s_axil_wstrb,
    input  wire                  s_axil_wvalid,
    output reg                   s_axil_wready,

    output reg  [1:0]            s_axil_bresp,
    output reg                   s_axil_bvalid,
    input  wire                  s_axil_bready,

    input  wire [ADDR_WIDTH-1:0] s_axil_araddr,
    input  wire                  s_axil_arvalid,
    output reg                   s_axil_arready,

    output reg  [DATA_WIDTH-1:0] s_axil_rdata,
    output reg  [1:0]            s_axil_rresp,
    output reg                   s_axil_rvalid,
    input  wire                  s_axil_rready,

    // Core Control / Status / Interrupt Lines
    output wire                  abnormal_wake_irq,
    output wire [2:0]            wake_target_out
);

    // Register Definitions
    reg [31:0] reg_ctrl;
    reg [31:0] reg_status;
    reg [31:0] reg_ch_mask;
    reg [31:0] reg_ll_thr;
    reg [31:0] reg_bp_ratio_thr;
    reg [31:0] reg_ent_thr;
    reg [31:0] reg_vote_nm;
    reg [31:0] reg_hyst_hold;
    reg [31:0] reg_pretrig_len;
    reg [31:0] reg_irq_en;
    reg [31:0] reg_irq_status;
    reg [31:0] reg_wake_target;

    assign wake_target_out   = reg_wake_target[2:0];
    assign abnormal_wake_irq = |(reg_irq_status & reg_irq_en);

    // Register Write Logic
    wire [7:0] w_offset = s_axil_awaddr[7:0];

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axil_awready    <= 1'b0;
            s_axil_wready     <= 1'b0;
            s_axil_bvalid     <= 1'b0;
            s_axil_bresp      <= `AXI_RESP_OKAY;

            reg_ctrl         <= 32'h0000_0000;
            reg_status       <= 32'h0000_0000;
            reg_ch_mask      <= 32'hFFFF_FFFF;
            reg_ll_thr       <= 32'h0000_0500;
            reg_bp_ratio_thr <= 32'h0000_0280;
            reg_ent_thr      <= 32'h0000_01C0;
            reg_vote_nm      <= 32'h0004_0008; // 4 of 8 channels
            reg_hyst_hold    <= 32'h000A_0005; // 10 hold, 5 hyst
            reg_pretrig_len  <= 32'h0000_001E; // 30 seconds
            reg_irq_en       <= 32'h0000_0001; // Abnormal IRQ enabled by default
            reg_irq_status   <= 32'h0000_0000;
            reg_wake_target  <= 32'h0000_0003; // Default wake both NPU & Swin
        end else begin
            // Address Ready
            if (s_axil_awvalid && !s_axil_awready) begin
                s_axil_awready <= 1'b1;
            end else begin
                s_axil_awready <= 1'b0;
            end

            // Data Ready & Write execution
            if (s_axil_wvalid && !s_axil_wready) begin
                s_axil_wready <= 1'b1;
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= `AXI_RESP_OKAY;

                case (w_offset)
                    `THRESH_REG_CTRL:         reg_ctrl         <= s_axil_wdata;
                    `THRESH_REG_STATUS:       reg_status       <= s_axil_wdata;
                    `THRESH_REG_CH_MASK:      reg_ch_mask      <= s_axil_wdata;
                    `THRESH_REG_LL_THR:       reg_ll_thr       <= s_axil_wdata;
                    `THRESH_REG_BP_RATIO_THR: reg_bp_ratio_thr <= s_axil_wdata;
                    `THRESH_REG_ENT_THR:      reg_ent_thr      <= s_axil_wdata;
                    `THRESH_REG_VOTE_NM:      reg_vote_nm      <= s_axil_wdata;
                    `THRESH_REG_HYST_HOLD:    reg_hyst_hold    <= s_axil_wdata;
                    `THRESH_REG_PRETRIG_LEN:  reg_pretrig_len  <= s_axil_wdata;
                    `THRESH_REG_IRQ_EN:       reg_irq_en       <= s_axil_wdata;
                    `THRESH_REG_IRQ_STATUS:   reg_irq_status   <= reg_irq_status & ~s_axil_wdata; // Write-1-to-clear
                    `THRESH_REG_WAKE_TARGET:  reg_wake_target  <= s_axil_wdata;
                    default: ;
                endcase
            end else begin
                s_axil_wready <= 1'b0;
            end

            // Clear bvalid on handshake
            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
        end
    end

    // Register Read Logic
    wire [7:0] r_offset = s_axil_araddr[7:0];

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rresp   <= `AXI_RESP_OKAY;
            s_axil_rdata   <= 32'd0;
        end else begin
            if (s_axil_arvalid && !s_axil_arready) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid  <= 1'b1;
                s_axil_rresp   <= `AXI_RESP_OKAY;

                case (r_offset)
                    `THRESH_REG_CTRL:         s_axil_rdata <= reg_ctrl;
                    `THRESH_REG_STATUS:       s_axil_rdata <= reg_status;
                    `THRESH_REG_CH_MASK:      s_axil_rdata <= reg_ch_mask;
                    `THRESH_REG_LL_THR:       s_axil_rdata <= reg_ll_thr;
                    `THRESH_REG_BP_RATIO_THR: s_axil_rdata <= reg_bp_ratio_thr;
                    `THRESH_REG_ENT_THR:      s_axil_rdata <= reg_ent_thr;
                    `THRESH_REG_VOTE_NM:      s_axil_rdata <= reg_vote_nm;
                    `THRESH_REG_HYST_HOLD:    s_axil_rdata <= reg_hyst_hold;
                    `THRESH_REG_PRETRIG_LEN:  s_axil_rdata <= reg_pretrig_len;
                    `THRESH_REG_IRQ_EN:       s_axil_rdata <= reg_irq_en;
                    `THRESH_REG_IRQ_STATUS:   s_axil_rdata <= reg_irq_status;
                    `THRESH_REG_WAKE_TARGET:  s_axil_rdata <= reg_wake_target;
                    default:                  s_axil_rdata <= 32'hDEAD_BEEF;
                endcase
            end else begin
                s_axil_arready <= 1'b0;
            end

            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

endmodule
