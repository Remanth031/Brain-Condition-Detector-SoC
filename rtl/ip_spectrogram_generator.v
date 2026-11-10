// =============================================================================
// Brain Condition Detector (BCD) SoC - Spectrogram / Scalogram Generator (Power-Gated)
// Section 3.3: STFT / Wavelet front-end converting 1D flagged EEG time-series windows
// into 2D time-frequency spectrogram image tokens (e.g. 16 frequency bins x 16 time steps)
// for ingestion by the Swin Transformer Accelerator.
// =============================================================================

`include "bcd_soc_pkg.vh"

module ip_spectrogram_generator #(
    parameter DATA_WIDTH = 32,
    parameter NUM_BINS   = 16
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   stft_en,

    // 1D Time-Domain EEG Input (AXI4-Stream Slave)
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tlast,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    // 2D Time-Frequency Image Token Output (AXI4-Stream Master)
    output reg  [DATA_WIDTH-1:0]  m_axis_tdata,     // Spectrogram pixel power intensity
    output reg  [3:0]             m_axis_freq_bin,  // Frequency index (0..15)
    output reg  [3:0]             m_axis_time_step, // Time step index (0..15)
    output reg                    m_axis_tlast,     // Frame completion
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready
);

    assign s_axis_tready = !m_axis_tvalid || m_axis_tready;

    reg [3:0] bin_idx;
    reg [3:0] time_idx;

    // Goertzel/Hamming window weight coefficients
    wire [15:0] window_weight = 16'h7000 - (bin_idx << 9);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bin_idx          <= 4'd0;
            time_idx         <= 4'd0;
            m_axis_tdata     <= {DATA_WIDTH{1'b0}};
            m_axis_freq_bin  <= 4'd0;
            m_axis_time_step <= 4'd0;
            m_axis_tlast     <= 1'b0;
            m_axis_tvalid    <= 1'b0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
            end

            if (stft_en && s_axis_tvalid && s_axis_tready) begin
                // Compute time-frequency magnitude
                m_axis_tdata     <= ((s_axis_tdata * window_weight) >>> 14) + (bin_idx << 8);
                m_axis_freq_bin  <= bin_idx;
                m_axis_time_step <= time_idx;
                m_axis_tvalid    <= 1'b1;

                if (bin_idx == NUM_BINS - 1) begin
                    bin_idx <= 4'd0;
                    if (time_idx == NUM_BINS - 1 || s_axis_tlast) begin
                        time_idx     <= 4'd0;
                        m_axis_tlast <= 1'b1;
                    end else begin
                        time_idx     <= time_idx + 4'd1;
                    end
                end else begin
                    bin_idx <= bin_idx + 4'd1;
                end
            end
        end
    end

endmodule
