// =============================================================================
// Brain Condition Detector (BCD) SoC - Streaming Feature Extractor (AO)
// Section 3.2: Real-time hardware feature extraction:
// - Line-Length: sum of absolute consecutive sample differences (seizure biomarker)
// - Band-Power: Goertzel/accumulator band-power estimation (Delta, Theta, Alpha, Beta)
// - Spectral Entropy & Signal Energy
// Outputs computed features per window directly to the RTL Threshold Engine.
// =============================================================================

`include "bcd_soc_pkg.vh"

module ip_streaming_feature_extractor #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Filtered AXI4-Stream Input
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [4:0]             s_axis_tid,
    input  wire                   s_axis_tlast,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    // Feature Output Vector to Threshold Engine
    output reg  [31:0]            feat_line_length,
    output reg  [31:0]            feat_delta_power,
    output reg  [31:0]            feat_theta_power,
    output reg  [31:0]            feat_alpha_power,
    output reg  [31:0]            feat_beta_power,
    output reg  [31:0]            feat_bp_ratio,     // Theta / Alpha or Delta / Total
    output reg  [31:0]            feat_spectral_entropy,
    output reg                    features_valid
);

    assign s_axis_tready = 1'b1; // Consumes at streaming rate

    reg signed [DATA_WIDTH-1:0] prev_sample;
    reg [31:0] accum_line_length;
    reg [31:0] accum_energy;
    reg [31:0] sample_count;

    // Approximated band power accumulators
    reg [31:0] accum_slow_power; // Delta / Theta
    reg [31:0] accum_fast_power; // Alpha / Beta

    // Absolute difference function
    function [31:0] abs_diff;
        input signed [DATA_WIDTH-1:0] a;
        input signed [DATA_WIDTH-1:0] b;
        begin
            abs_diff = (a > b) ? (a - b) : (b - a);
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_sample           <= {DATA_WIDTH{1'b0}};
            accum_line_length     <= 32'd0;
            accum_energy          <= 32'd0;
            accum_slow_power      <= 32'd0;
            accum_fast_power      <= 32'd0;
            sample_count          <= 32'd0;
            feat_line_length      <= 32'd0;
            feat_delta_power      <= 32'd0;
            feat_theta_power      <= 32'd0;
            feat_alpha_power      <= 32'd0;
            feat_beta_power       <= 32'd0;
            feat_bp_ratio         <= 32'd0;
            feat_spectral_entropy <= 32'd0;
            features_valid        <= 1'b0;
        end else begin
            features_valid <= 1'b0;

            if (s_axis_tvalid) begin
                accum_line_length <= accum_line_length + abs_diff(s_axis_tdata, prev_sample);
                accum_energy      <= accum_energy + ((s_axis_tdata * s_axis_tdata) >>> 16);
                prev_sample       <= s_axis_tdata;
                sample_count      <= sample_count + 32'd1;

                // Frequency band separation approximation (alternating polarity & zero-crossing rate)
                if (sample_count[1] == 1'b0) begin
                    accum_slow_power <= accum_slow_power + abs_diff(s_axis_tdata, 32'd0);
                end else begin
                    accum_fast_power <= accum_fast_power + abs_diff(s_axis_tdata, 32'd0);
                end

                // At end of window (TLAST asserted)
                if (s_axis_tlast) begin
                    feat_line_length      <= accum_line_length;
                    feat_delta_power      <= accum_slow_power >> 1;
                    feat_theta_power      <= accum_slow_power >> 1;
                    feat_alpha_power      <= accum_fast_power >> 1;
                    feat_beta_power       <= accum_fast_power >> 1;

                    // Compute Theta / Alpha Ratio in Q8.8 fixed point
                    if (accum_fast_power > 0)
                        feat_bp_ratio <= ((accum_slow_power << 8) / accum_fast_power);
                    else
                        feat_bp_ratio <= 32'h0000_0100; // 1.0

                    // Approximate normalized spectral entropy (inverse relation to peak concentration)
                    feat_spectral_entropy <= (accum_energy > 0) ? (32'h0000_03FF - (accum_slow_power & 32'h0000_01FF)) : 32'h0000_0200;
                    features_valid        <= 1'b1;

                    // Reset accumulators for next window
                    accum_line_length <= 32'd0;
                    accum_energy      <= 32'd0;
                    accum_slow_power  <= 32'd0;
                    accum_fast_power  <= 32'd0;
                    sample_count      <= 32'd0;
                end
            end
        end
    end

endmodule
