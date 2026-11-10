// =============================================================================
// Brain Condition Detector (BCD) SoC - ADC Deserializer & Sample Formatter (AO)
// Section 3.2: Converts raw SPI / LVDS ADC bitstreams into channel-tagged AXI4-Stream
// signals with TDATA (24/32b), TID (channel index), TUSER (lead-off/artifact), and TLAST.
// =============================================================================

`include "bcd_soc_pkg.vh"

module ip_adc_deserializer #(
    parameter NUM_CHANNELS = 32,
    parameter DATA_WIDTH   = 32,
    parameter SAMPLE_WIDTH = 24
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Raw ADC Interface (SPI / LVDS Frame Inputs)
    input  wire                   adc_frame_sync,
    input  wire                   adc_sample_valid,
    input  wire [SAMPLE_WIDTH-1:0] adc_raw_data,
    input  wire [4:0]             adc_channel_id,
    input  wire                   adc_lead_off_flag,
    input  wire                   adc_saturation_flag,

    // AXI4-Stream Master Interface
    output reg  [DATA_WIDTH-1:0]  m_axis_tdata,
    output reg  [4:0]             m_axis_tid,       // Channel index (0..31)
    output reg  [1:0]             m_axis_tuser,     // {saturation, lead_off}
    output reg                    m_axis_tlast,     // Marks end of window
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready,

    // Diagnostics
    output reg  [31:0]            sample_counter
);

    reg [15:0] window_sample_count;
    parameter WINDOW_SIZE = 16'd256; // e.g. 256 samples per window

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata        <= {DATA_WIDTH{1'b0}};
            m_axis_tid          <= 5'd0;
            m_axis_tuser        <= 2'b00;
            m_axis_tlast        <= 1'b0;
            m_axis_tvalid       <= 1'b0;
            sample_counter      <= 32'd0;
            window_sample_count <= 16'd0;
        end else begin
            if (adc_sample_valid && (!m_axis_tvalid || m_axis_tready)) begin
                // Sign-extend 24-bit ADC sample to 32-bit TDATA
                m_axis_tdata  <= {{8{adc_raw_data[SAMPLE_WIDTH-1]}}, adc_raw_data};
                m_axis_tid    <= adc_channel_id;
                m_axis_tuser  <= {adc_saturation_flag, adc_lead_off_flag};
                m_axis_tvalid <= 1'b1;

                if (window_sample_count == WINDOW_SIZE - 1) begin
                    m_axis_tlast        <= 1'b1;
                    window_sample_count <= 16'd0;
                end else begin
                    m_axis_tlast        <= 1'b0;
                    window_sample_count <= window_sample_count + 16'd1;
                end
                sample_counter <= sample_counter + 32'd1;
            end else if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
            end
        end
    end

endmodule
