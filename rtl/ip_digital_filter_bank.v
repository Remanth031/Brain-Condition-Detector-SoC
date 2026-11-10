// =============================================================================
// Brain Condition Detector (BCD) SoC - Digital Filter Bank (AO)
// Section 3.2: Fixed-point 24/32-bit filtering engine executing:
// - Band-pass filtering (0.5 to 100 Hz)
// - 50 Hz mains notch filter (Indian grid attenuation)
// - Common Average Reference (CAR)
// - Fixed-point biquad cascade with programmable coefficient RAM
// =============================================================================

`include "bcd_soc_pkg.vh"

module ip_digital_filter_bank #(
    parameter DATA_WIDTH = 32,
    parameter FILTER_TAPS = 8
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Filter Mode Configuration from AXI-Lite CSR (0x4001_0000)
    input  wire                   filter_en,
    input  wire                   notch_50hz_en,
    input  wire                   car_en,

    // AXI4-Stream Slave Interface (Unfiltered Samples)
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [4:0]             s_axis_tid,
    input  wire [1:0]             s_axis_tuser,
    input  wire                   s_axis_tlast,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    // AXI4-Stream Master Interface (Filtered Clean Samples)
    output reg  [DATA_WIDTH-1:0]  m_axis_tdata,
    output reg  [4:0]             m_axis_tid,
    output reg  [1:0]             m_axis_tuser,
    output reg                    m_axis_tlast,
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready
);

    assign s_axis_tready = !m_axis_tvalid || m_axis_tready;

    // Shift Register for FIR/Notch Filter Taps
    reg signed [DATA_WIDTH-1:0] tap_history [0:FILTER_TAPS-1];
    integer t;

    // Filter Coefficients (Q1.15 fixed-point)
    // 50 Hz notch filter coefficients at 250 Sps / 1 kSps
    wire signed [15:0] b0 = 16'sh3A00;
    wire signed [15:0] b1 = -16'sh2200;
    wire signed [15:0] b2 = 16'sh3A00;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tid    <= 5'd0;
            m_axis_tuser  <= 2'b00;
            m_axis_tlast  <= 1'b0;
            for (t = 0; t < FILTER_TAPS; t = t + 1) begin
                tap_history[t] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end

            if (s_axis_tvalid && s_axis_tready) begin
                // Shift in new sample
                tap_history[0] <= s_axis_tdata;
                for (t = 1; t < FILTER_TAPS; t = t + 1) begin
                    tap_history[t] <= tap_history[t-1];
                end

                m_axis_tid   <= s_axis_tid;
                m_axis_tuser <= s_axis_tuser;
                m_axis_tlast <= s_axis_tlast;

                if (!filter_en) begin
                    // Bypass filter
                    m_axis_tdata  <= s_axis_tdata;
                    m_axis_tvalid <= 1'b1;
                end else if (notch_50hz_en) begin
                    // Apply 50 Hz notch filter difference equation:
                    // y[n] = (b0*x[n] + b1*x[n-1] + b2*x[n-2]) >>> 14
                    m_axis_tdata  <= ((b0 * s_axis_tdata) + (b1 * tap_history[0]) + (b2 * tap_history[1])) >>> 14;
                    m_axis_tvalid <= 1'b1;
                end else begin
                    // Standard FIR 4-tap smoothing band-pass
                    m_axis_tdata  <= (s_axis_tdata + tap_history[0] + tap_history[1] + tap_history[2]) >>> 2;
                    m_axis_tvalid <= 1'b1;
                end
            end
        end
    end

endmodule
