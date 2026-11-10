// =============================================================================
// Brain Condition Detector (BCD) SoC - Power Management Unit (PMU) Sequencer (AO)
// Section 3.4 & 4.5: Power island un-gating sequencer:
// - Manages power switch enable lines for Edge-AI & Swin accelerators
// - Controls isolation cells and level-shifter enables between AO and Compute domains
// - Enforces clean AXI quiescing handshakes before cutting power
// - Sequences clocks with glitch-free gating upon Threshold Wake assertions
// =============================================================================

`include "bcd_soc_pkg.vh"

module ip_pmu_power_sequencer (
    input  wire        clk_ao,
    input  wire        rst_ao_n,

    // Wake Request from RTL Threshold Engine
    input  wire        threshold_wake_req,
    input  wire [2:0]  wake_targets, // bit 0: NPU, bit 1: Swin, bit 2: Both

    // Handshakes from Compute Domain Accelerators
    input  wire        npu_idle_status,
    input  wire        swin_idle_status,

    // Physical Power Island & Clock Control Outputs
    output reg         power_switch_en_compute, // Enables VDD rails to compute domain
    output reg         isolation_cell_en,       // Clamps inputs during power-down
    output reg         compute_domain_rst_n,    // Clean domain reset release
    output reg         compute_clock_gate_en,   // Glitch-free clock enable

    // State Status for AXI-Lite CSR (0x4003_0000)
    output reg  [2:0]  pmu_state_out
);

    localparam PMU_OFF           = 3'd0;
    localparam PMU_POWER_UP      = 3'd1;
    localparam PMU_ISO_RELEASE   = 3'd2;
    localparam PMU_CLK_UNGATE    = 3'd3;
    localparam PMU_ACTIVE_COMP   = 3'd4;
    localparam PMU_QUIESCE_WAIT  = 3'd5;
    localparam PMU_POWER_DOWN    = 3'd6;

    reg [2:0] state;
    reg [7:0] settle_timer;

    always @(posedge clk_ao or negedge rst_ao_n) begin
        if (!rst_ao_n) begin
            state                   <= PMU_OFF;
            power_switch_en_compute <= 1'b0;
            isolation_cell_en       <= 1'b1; // Clamped in OFF
            compute_domain_rst_n    <= 1'b0;
            compute_clock_gate_en   <= 1'b0;
            settle_timer            <= 8'd0;
            pmu_state_out           <= PMU_OFF;
        end else begin
            pmu_state_out <= state;

            case (state)
                PMU_OFF: begin
                    compute_clock_gate_en   <= 1'b0;
                    compute_domain_rst_n    <= 1'b0;
                    isolation_cell_en       <= 1'b1;
                    power_switch_en_compute <= 1'b0;

                    if (threshold_wake_req) begin
                        power_switch_en_compute <= 1'b1; // Turn on power switches
                        settle_timer            <= 8'd10; // Wait 10 cycles for rail stabilization
                        state                   <= PMU_POWER_UP;
                    end
                end

                PMU_POWER_UP: begin
                    if (settle_timer > 0) begin
                        settle_timer <= settle_timer - 8'd1;
                    end else begin
                        isolation_cell_en <= 1'b0; // Release signal isolation
                        state             <= PMU_ISO_RELEASE;
                    end
                end

                PMU_ISO_RELEASE: begin
                    compute_clock_gate_en <= 1'b1; // Ungate clocks
                    compute_domain_rst_n  <= 1'b1; // Release domain reset
                    state                 <= PMU_ACTIVE_COMP;
                end

                PMU_ACTIVE_COMP: begin
                    // Accelerators running inference
                    if (!threshold_wake_req) begin
                        state <= PMU_QUIESCE_WAIT;
                    end
                end

                PMU_QUIESCE_WAIT: begin
                    // Section 4.5: Wait until both accelerators are idle (AXI quiesced)
                    if (npu_idle_status && swin_idle_status) begin
                        compute_clock_gate_en <= 1'b0; // Stop clocks first
                        compute_domain_rst_n  <= 1'b0;
                        isolation_cell_en     <= 1'b1; // Clamp boundary signals
                        settle_timer          <= 8'd5;
                        state                 <= PMU_POWER_DOWN;
                    end
                end

                PMU_POWER_DOWN: begin
                    if (settle_timer > 0) begin
                        settle_timer <= settle_timer - 8'd1;
                    end else begin
                        power_switch_en_compute <= 1'b0; // Cut power
                        state                   <= PMU_OFF;
                    end
                end
            endcase
        end
    end

endmodule
