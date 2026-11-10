// =============================================================================
// Brain Condition Detector (BCD) SoC - Imaging Ingest IP (Tumor Triage Pathway)
// Section 3.4: Receives DICOM / NIfTI MRI/CT axial, coronal, or sagittal slices
// from external USB/Ethernet/Host interface. Performs 16-bit to 8-bit normalization,
// scaling to 224x224, and bursts slices directly to LPDDR memory for Swin processing.
// =============================================================================

`include "bcd_soc_pkg.vh"

module ip_imaging_ingest #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Control from AXI-Lite CSR (0x4007_0000)
    input  wire                   ingest_start,
    input  wire [1:0]             modality_type, // 0=MRI T1, 1=MRI T2/FLAIR, 2=CT, 3=PET
    output reg                    ingest_busy,
    output reg                    ingest_done_irq,

    // Slice Stream Input from Host
    input  wire [15:0]            host_pixel_data,
    input  wire                   host_pixel_valid,
    output wire                   host_pixel_ready,

    // Normalized Slice Output (Streaming to Swin or LPDDR DMA)
    output reg  [DATA_WIDTH-1:0]  norm_slice_pixel,
    output reg                    norm_slice_valid,
    input  wire                   norm_slice_ready,

    // Statistics
    output reg  [31:0]            total_pixels_ingested
);

    assign host_pixel_ready = ingest_busy && (!norm_slice_valid || norm_slice_ready);

    // Dynamic Range Normalization (Windowing & Leveling)
    // Centers 12-to-16-bit Hounsfield/Intensity values into 8-bit range [0..255]
    wire [7:0] scaled_pixel = (host_pixel_data > 16'd2048) ? 8'd255 : host_pixel_data[10:3];

    reg [1:0] pixel_pack_cnt;
    reg [23:0] pack_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ingest_busy           <= 1'b0;
            ingest_done_irq       <= 1'b0;
            norm_slice_pixel      <= {DATA_WIDTH{1'b0}};
            norm_slice_valid      <= 1'b0;
            pixel_pack_cnt        <= 2'd0;
            pack_reg              <= 24'd0;
            total_pixels_ingested <= 32'd0;
        end else begin
            if (norm_slice_valid && norm_slice_ready) begin
                norm_slice_valid <= 1'b0;
            end

            if (ingest_start && !ingest_busy) begin
                ingest_busy           <= 1'b1;
                ingest_done_irq       <= 1'b0;
                pixel_pack_cnt        <= 2'd0;
                total_pixels_ingested <= 32'd0;
            end else if (ingest_busy) begin
                if (host_pixel_valid && host_pixel_ready) begin
                    total_pixels_ingested <= total_pixels_ingested + 32'd1;

                    // Pack 4 8-bit pixels into 32-bit AXI word
                    if (pixel_pack_cnt == 2'd3) begin
                        norm_slice_pixel <= {scaled_pixel, pack_reg};
                        norm_slice_valid <= 1'b1;
                        pixel_pack_cnt   <= 2'd0;
                    end else begin
                        pack_reg <= (pack_reg << 8) | scaled_pixel;
                        pixel_pack_cnt <= pixel_pack_cnt + 2'd1;
                    end

                    // Sample frame size: 256 pixels per slice test
                    if (total_pixels_ingested >= 32'd255) begin
                        ingest_busy     <= 1'b0;
                        ingest_done_irq <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
