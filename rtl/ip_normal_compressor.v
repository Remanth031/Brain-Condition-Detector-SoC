// =============================================================================
// Brain Condition Detector (BCD) SoC - Normal Path Compressor (AO)
// Section 2.1: Implements Delta + Rice coding for normal EEG windows.
// Encodes difference between consecutive samples into variable-length unary/binary
// symbols for ultra-low-power BLE transmission while accelerators remain powered off.
// =============================================================================

`include "bcd_soc_pkg.vh"

module ip_normal_compressor #(
    parameter DATA_WIDTH = 32,
    parameter RICE_K     = 4  // Golomb-Rice parameter k
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   compress_en,

    // Streaming EEG Input
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    // Compressed Bitstream Output (to BLE / SPI / Flash FIFO)
    output reg  [15:0]            comp_data_word,
    output reg  [4:0]             comp_bit_length,
    output reg                    comp_valid,
    input  wire                   comp_ready
);

    assign s_axis_tready = !comp_valid || comp_ready;

    reg signed [DATA_WIDTH-1:0] prev_sample;
    wire signed [DATA_WIDTH-1:0] diff = s_axis_tdata - prev_sample;

    // Map signed difference to non-negative integer (Zigzag encoding)
    // 0 -> 0, -1 -> 1, 1 -> 2, -2 -> 3, etc.
    wire [31:0] zigzag = (diff >= 0) ? (diff << 1) : ((-diff << 1) - 1);

    // Rice quotient and remainder
    wire [27:0] quotient  = zigzag >> RICE_K;
    wire [RICE_K-1:0] rem = zigzag & ((1 << RICE_K) - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_sample     <= {DATA_WIDTH{1'b0}};
            comp_data_word  <= 16'd0;
            comp_bit_length <= 5'd0;
            comp_valid      <= 1'b0;
        end else begin
            if (comp_valid && comp_ready) begin
                comp_valid <= 1'b0;
            end

            if (compress_en && s_axis_tvalid && s_axis_tready) begin
                prev_sample <= s_axis_tdata;

                // Pack Rice codeword: unary code for quotient (quotient '0's followed by a '1') + remainder
                // Cap quotient representation to avoid overflow in word
                if (quotient < 11) begin
                    comp_data_word  <= ((16'h1 << RICE_K) | rem) << (11 - quotient);
                    comp_bit_length <= (quotient[4:0] + 1'b1 + RICE_K);
                    comp_valid      <= 1'b1;
                end else begin
                    // Fallback literal prefix
                    comp_data_word  <= {8'hFF, zigzag[7:0]};
                    comp_bit_length <= 5'd16;
                    comp_valid      <= 1'b1;
                end
            end
        end
    end

endmodule
