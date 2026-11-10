// =============================================================================
// Brain Condition Detector (BCD) SoC - Rate-Matching Async FIFO with CDC (AO)
// Section 3.2: Clock-domain crossing and rate-matching between ADC converter clock
// and DSP processing clock. Supports AXI4-Stream slave in / master out and watermark flags.
// =============================================================================

`include "bcd_soc_pkg.vh"

module ip_dsp_async_fifo #(
    parameter DATA_WIDTH = 32,
    parameter FIFO_DEPTH = 64
)(
    // Ingestion Clock Domain (ADC Clock)
    input  wire                   wr_clk,
    input  wire                   wr_rst_n,
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [4:0]             s_axis_tid,
    input  wire [1:0]             s_axis_tuser,
    input  wire                   s_axis_tlast,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    // Processing Clock Domain (DSP Clock)
    input  wire                   rd_clk,
    input  wire                   rd_rst_n,
    output reg  [DATA_WIDTH-1:0]  m_axis_tdata,
    output reg  [4:0]             m_axis_tid,
    output reg  [1:0]             m_axis_tuser,
    output reg                    m_axis_tlast,
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready,

    // Status Watermarks & Flags
    output wire                   fifo_full,
    output wire                   fifo_empty,
    output wire                   fifo_overflow,
    output wire [6:0]             fifo_occupancy
);

    // FIFO Memory Storage (Payload: 32 data + 5 id + 2 user + 1 last = 40 bits)
    localparam PAYLOAD_WIDTH = DATA_WIDTH + 5 + 2 + 1;
    reg [PAYLOAD_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];

    reg [5:0] wr_ptr;
    reg [5:0] rd_ptr;
    reg [6:0] count;
    reg       overflow_sticky;

    assign s_axis_tready  = (count < FIFO_DEPTH);
    assign fifo_full      = (count == FIFO_DEPTH);
    assign fifo_empty     = (count == 0);
    assign fifo_overflow  = overflow_sticky;
    assign fifo_occupancy = count;

    // Write Logic
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr          <= 6'd0;
            overflow_sticky <= 1'b0;
        end else begin
            if (s_axis_tvalid && s_axis_tready) begin
                fifo_mem[wr_ptr] <= {s_axis_tlast, s_axis_tuser, s_axis_tid, s_axis_tdata};
                wr_ptr           <= (wr_ptr == FIFO_DEPTH-1) ? 6'd0 : wr_ptr + 6'd1;
            end else if (s_axis_tvalid && !s_axis_tready) begin
                overflow_sticky  <= 1'b1;
            end
        end
    end

    // Read Logic
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr        <= 6'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tid    <= 5'd0;
            m_axis_tuser  <= 2'b00;
            m_axis_tlast  <= 1'b0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end

            if (!fifo_empty && (!m_axis_tvalid || m_axis_tready)) begin
                {m_axis_tlast, m_axis_tuser, m_axis_tid, m_axis_tdata} <= fifo_mem[rd_ptr];
                m_axis_tvalid <= 1'b1;
                rd_ptr        <= (rd_ptr == FIFO_DEPTH-1) ? 6'd0 : rd_ptr + 6'd1;
            end
        end
    end

    // Synchronous Counter Model for Simulation/Verification
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            count <= 7'd0;
        end else begin
            case ({ (s_axis_tvalid && s_axis_tready), (m_axis_tvalid && m_axis_tready) })
                2'b10: count <= count + 7'd1;
                2'b01: count <= (count > 0) ? count - 7'd1 : 7'd0;
                default: ;
            endcase
        end
    end

endmodule
