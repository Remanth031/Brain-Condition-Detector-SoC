// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI Firewall / Protection Unit
// Filters per-master access permissions; blocks non-privileged masters
// (e.g. untrusted DMA or debug in production) from accessing sensitive regions
// like Security CSRs or Threshold Configuration registers.
// =============================================================================

`include "bcd_soc_pkg.vh"

module axi_firewall #(
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire                  aclk,
    input  wire                  aresetn,

    // Firewall Enable / Bypass
    input  wire                  firewall_en,
    input  wire                  production_mode, // locks out JTAG debug from secure CSRs

    // Input Transaction Attributes to Check
    input  wire [ID_WIDTH-1:0]   master_id,
    input  wire [ADDR_WIDTH-1:0] access_addr,
    input  wire                  is_write,

    // Firewall Evaluation Output
    output reg                   access_allowed,
    output reg                   violation_irq
);

    always @(*) begin
        if (!firewall_en) begin
            access_allowed = 1'b1;
        end else begin
            access_allowed = 1'b1;

            // Rule 1: Output / Display DMA (M4) is strictly READ-ONLY
            if (master_id == `MASTER_M4_DISPLAY && is_write) begin
                access_allowed = 1'b0;
            end

            // Rule 2: In production mode, JTAG Debug (M5) cannot access Security CSRs (0x4008_0000)
            if (production_mode && (master_id == `MASTER_M5_JTAG)) begin
                if (access_addr >= `CSR_BASE_SECURITY && access_addr < (`CSR_BASE_SECURITY + 32'h0001_0000)) begin
                    access_allowed = 1'b0;
                end
            end

            // Rule 3: DMAs (M1, M2, M3) cannot overwrite CSR registers directly
            if ((master_id == `MASTER_M1_DMA || master_id == `MASTER_M2_NPU || master_id == `MASTER_M3_SWIN) && is_write) begin
                if (access_addr >= `ADDR_BASE_CSR_BRIDGE && access_addr < (`ADDR_BASE_CSR_BRIDGE + `ADDR_SIZE_CSR_BRIDGE)) begin
                    access_allowed = 1'b0;
                end
            end
        end
    end

    // Sticky Violation Interrupt
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            violation_irq <= 1'b0;
        end else begin
            if (!access_allowed) begin
                violation_irq <= 1'b1;
            end
        end
    end

endmodule
