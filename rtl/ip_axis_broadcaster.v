// =============================================================================
// Brain Condition Detector (BCD) SoC - AXIS Broadcaster & Switch (AO)
// Section 3.2 & 4.5: Replicates the flagged window stream to both the Edge-AI NPU
// and the Swin Transformer in parallel. Employs per-port skid buffers to prevent
// sample drops when one accelerator stalls.
// =============================================================================

`include "bcd_soc_pkg.vh"

module ip_axis_broadcaster #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Routing Enable Mask from AXI-Lite (bit 0 = NPU, bit 1 = Swin)
    input  wire [1:0]             route_enable,

    // AXI4-Stream Slave Input (Flagged Window from SRAM/DMA)
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [4:0]             s_axis_tid,
    input  wire                   s_axis_tlast,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    // Port 0: To Edge-AI NPU
    output reg  [DATA_WIDTH-1:0]  m0_axis_tdata,
    output reg  [4:0]             m0_axis_tid,
    output reg                    m0_axis_tlast,
    output reg                    m0_axis_tvalid,
    input  wire                   m0_axis_tready,

    // Port 1: To Swin Transformer Accelerator
    output reg  [DATA_WIDTH-1:0]  m1_axis_tdata,
    output reg  [4:0]             m1_axis_tid,
    output reg                    m1_axis_tlast,
    output reg                    m1_axis_tvalid,
    input  wire                   m1_axis_tready
);

    // Skid Buffer for Port 0 (NPU)
    reg [DATA_WIDTH-1:0] p0_skid_data;
    reg [4:0]            p0_skid_id;
    reg                  p0_skid_last;
    reg                  p0_skid_valid;

    // Skid Buffer for Port 1 (Swin)
    reg [DATA_WIDTH-1:0] p1_skid_data;
    reg [4:0]            p1_skid_id;
    reg                  p1_skid_last;
    reg                  p1_skid_valid;

    // Ready when neither active port's skid buffer is full
    assign s_axis_tready = (!route_enable[0] || (!m0_axis_tvalid || m0_axis_tready || !p0_skid_valid)) &&
                           (!route_enable[1] || (!m1_axis_tvalid || m1_axis_tready || !p1_skid_valid));

    // Port 0 (NPU) Pipeline
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m0_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m0_axis_tid    <= 5'd0;
            m0_axis_tlast  <= 1'b0;
            m0_axis_tvalid <= 1'b0;
            p0_skid_valid  <= 1'b0;
        end else begin
            if (m0_axis_tready && p0_skid_valid) begin
                m0_axis_tdata  <= p0_skid_data;
                m0_axis_tid    <= p0_skid_id;
                m0_axis_tlast  <= p0_skid_last;
                m0_axis_tvalid <= 1'b1;
                p0_skid_valid  <= 1'b0;
            end else if (m0_axis_tready) begin
                m0_axis_tvalid <= 1'b0;
            end

            if (route_enable[0] && s_axis_tvalid && s_axis_tready) begin
                if (!m0_axis_tvalid || m0_axis_tready) begin
                    m0_axis_tdata  <= s_axis_tdata;
                    m0_axis_tid    <= s_axis_tid;
                    m0_axis_tlast  <= s_axis_tlast;
                    m0_axis_tvalid <= 1'b1;
                end else if (!p0_skid_valid) begin
                    p0_skid_data  <= s_axis_tdata;
                    p0_skid_id    <= s_axis_tid;
                    p0_skid_last  <= s_axis_tlast;
                    p0_skid_valid <= 1'b1;
                end
            end
        end
    end

    // Port 1 (Swin) Pipeline
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m1_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m1_axis_tid    <= 5'd0;
            m1_axis_tlast  <= 1'b0;
            m1_axis_tvalid <= 1'b0;
            p1_skid_valid  <= 1'b0;
        end else begin
            if (m1_axis_tready && p1_skid_valid) begin
                m1_axis_tdata  <= p1_skid_data;
                m1_axis_tid    <= p1_skid_id;
                m1_axis_tlast  <= p1_skid_last;
                m1_axis_tvalid <= 1'b1;
                p1_skid_valid  <= 1'b0;
            end else if (m1_axis_tready) begin
                m1_axis_tvalid <= 1'b0;
            end

            if (route_enable[1] && s_axis_tvalid && s_axis_tready) begin
                if (!m1_axis_tvalid || m1_axis_tready) begin
                    m1_axis_tdata  <= s_axis_tdata;
                    m1_axis_tid    <= s_axis_tid;
                    m1_axis_tlast  <= s_axis_tlast;
                    m1_axis_tvalid <= 1'b1;
                end else if (!p1_skid_valid) begin
                    p1_skid_data  <= s_axis_tdata;
                    p1_skid_id    <= s_axis_tid;
                    p1_skid_last  <= s_axis_tlast;
                    p1_skid_valid <= 1'b1;
                end
            end
        end
    end

endmodule
