// =============================================================================
// Brain Condition Detector (BCD) SoC - Output Fusion & Problem Report Generator
// Section 3.4: Merges Edge-AI NPU and Swin Transformer classifications,
// resolves disagreement by confidence weighting, renders the diagnostic heatmap
// image overlay, and generates a structured clinical problem report.
// =============================================================================

`include "bcd_soc_pkg.vh"

module ip_output_fusion #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Accelerator Decision Inputs
    input  wire                   fusion_trigger,
    input  wire [3:0]             npu_class_id,
    input  wire [7:0]             npu_confidence,
    input  wire [3:0]             swin_class_id,
    input  wire [7:0]             swin_confidence,

    // Saliency Attention Input (from Swin)
    input  wire [31:0]            saliency_heat_val,

    // Fused Output Results
    output reg  [3:0]             final_class_id,       // Fused diagnostic label
    output reg  [7:0]             final_confidence,     // Fused confidence score
    output reg  [31:0]            diagnostic_image_word,// Heatmap overlay pixel
    output reg  [63:0]            report_text_ascii,    // ASCII finding code (e.g. "SEIZ_ACT")
    output reg                    report_ready_irq
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            final_class_id        <= 4'd0;
            final_confidence      <= 8'd0;
            diagnostic_image_word <= 32'd0;
            report_text_ascii     <= 64'd0;
            report_ready_irq      <= 1'b0;
        end else begin
            report_ready_irq <= 1'b0;

            if (fusion_trigger) begin
                report_ready_irq <= 1'b1;

                // Confidence-based resolution
                if (swin_confidence >= npu_confidence) begin
                    final_class_id   <= swin_class_id;
                    final_confidence <= swin_confidence;
                end else begin
                    final_class_id   <= npu_class_id;
                    final_confidence <= npu_confidence;
                end

                // Diagnostic Heatmap generation: blend baseline grayscale with red/yellow saliency
                diagnostic_image_word <= (saliency_heat_val > 32'h0000_1000) ? 
                                         32'h00FF_0000 : // Red hot-spot (anomaly focal point)
                                         32'h0000_8080;   // Ambient background

                // Templated ASCII clinical findings report
                case (swin_confidence >= npu_confidence ? swin_class_id : npu_class_id)
                    4'd1: report_text_ascii <= 64'h5345_495A_5552_4521; // "SEIZURE!"
                    4'd2: report_text_ascii <= 64'h5350_494E_444C_4553; // "SPINDLES"
                    4'd3: report_text_ascii <= 64'h4152_5449_4641_4354; // "ARTIFACT"
                    default: report_text_ascii <= 64'h4E4F_524D_414C_5F5F; // "NORMAL__"
                endcase
            end
        end
    end

endmodule
