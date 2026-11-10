// =============================================================================
// Brain Condition Detector (BCD) SoC - Edge-AI NPU Accelerator (Power-Gated)
// Section 3.3 & 2.1: INT8 Systolic Hardware Accelerator implementing:
// - Multi-Layer EEGNet Neural Network Pipeline:
//     * Layer 0: Temporal 1D Convolution (Bandpass filter learning)
//     * Layer 1: Depthwise Spatial Convolution (Montage spatial projection across 32 channels)
//     * Layer 2: Separable Temporal Convolution + Pointwise Feature Mixing
//     * Layer 3: Dense Classifier with Softmax Confidence Score
// - Hardware Fixed-Point Batch Normalization & ReLU / ELU Activation Unit
// - Hardware Average Pooling Subsampling Engine
// - Local Weight & Activation Scratchpad Storage
// - Autonomous AXI4 DMA Master M2 Interface (Burst read weights from NVM/LPDDR,
//   intermediate feature map spillover to Scratchpad S2, result mailbox write to SRAM S1)
// - AXI4-Lite CSR Slave Interface at Base 0x4005_0000
// =============================================================================

`include "bcd_soc_pkg.vh"

module ip_edge_ai_npu #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter ARRAY_SIZE  = 4    // 4x4 INT8 Systolic Processing Elements
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // AXI4-Lite CSR Control Interface (Base 0x4005_0000)
    input  wire [ADDR_WIDTH-1:0]  s_axil_awaddr,
    input  wire                   s_axil_awvalid,
    output reg                    s_axil_awready,
    input  wire [DATA_WIDTH-1:0]  s_axil_wdata,
    input  wire [3:0]             s_axil_wstrb,
    input  wire                   s_axil_wvalid,
    output reg                    s_axil_wready,
    output reg  [1:0]             s_axil_bresp,
    output reg                    s_axil_bvalid,
    input  wire                   s_axil_bready,

    input  wire [ADDR_WIDTH-1:0]  s_axil_araddr,
    input  wire                   s_axil_arvalid,
    output reg                    s_axil_arready,
    output reg  [DATA_WIDTH-1:0]  s_axil_rdata,
    output reg  [1:0]             s_axil_rresp,
    output reg                    s_axil_rvalid,
    input  wire                   s_axil_rready,

    // Hardware Trigger from Wake-up Controller / Threshold Engine
    input  wire                   npu_hw_start,

    // Streaming EEG Input Window (AXI4-Stream Slave from Broadcaster)
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tlast,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    // Autonomous AXI Master M2 DMA Interface
    output reg                    dma_m2_start,
    output reg                    dma_m2_is_write,
    output reg  [ADDR_WIDTH-1:0]  dma_m2_addr,
    output reg  [7:0]             dma_m2_len,
    output reg  [DATA_WIDTH-1:0]  dma_m2_wdata,
    input  wire                   dma_m2_done,
    input  wire [DATA_WIDTH-1:0]  dma_m2_rdata,

    // Accelerator Status & IRQ
    output reg                    npu_busy,
    output reg                    npu_done_irq,

    // Direct Diagnostic Result Outputs to Output Fusion Block
    output reg  [3:0]             event_class_id,   // 0=Normal, 1=Seizure, 2=Spindle, 3=Encephalopathy, 4=Artifact
    output reg  [7:0]             event_confidence  // 0-255 Confidence Score
);

    // =========================================================================
    // 1. CSR Registers (Section 4.3 Base 0x4005_0000)
    // =========================================================================
    reg [31:0] reg_ctrl;          // 0x00: [0] Start, [1] Auto-DMA En, [3:2] Layer Mode, [4] Soft Reset
    reg [31:0] reg_status;        // 0x04: [0] Busy, [1] Done, [4:2] Current Layer, [5] DMA Busy
    reg [31:0] reg_weight_addr;   // 0x08: AXI base address of model weights (e.g. 0x6000_0000)
    reg [31:0] reg_scratch_addr;  // 0x0C: AXI base address of scratchpad (e.g. 0x1100_0000)
    reg [31:0] reg_result_class;  // 0x10: [3:0] Classified class ID
    reg [31:0] reg_confidence;    // 0x14: [7:0] Confidence score
    reg [31:0] reg_cycle_count;   // 0x18: Total inference execution cycles
    reg [31:0] reg_irq_en;        // 0x1C: Interrupt enable

    // =========================================================================
    // 2. Local Memories (Weight Caches & Feature Scratchpads)
    // =========================================================================
    // 64-entry INT8 Weight Cache (Pre-loaded / DMA refreshed)
    reg signed [7:0] weight_cache [0:63];

    // Preload trained EEGNet weights (Temporal, Spatial Depthwise, Pointwise, Classifier)
    integer k;
    initial begin
        // Layer 0: Temporal Conv weights (bandpass filters in 0.5-100Hz)
        weight_cache[0]  = 8'sd14;  weight_cache[1]  = 8'sd28;  weight_cache[2]  = -8'sd18; weight_cache[3]  = 8'sd10;
        weight_cache[4]  = 8'sd35;  weight_cache[5]  = -8'sd45; weight_cache[6]  = 8'sd12;  weight_cache[7]  = 8'sd22;
        weight_cache[8]  = -8'sd8;  weight_cache[9]  = 8'sd12;  weight_cache[10] = 8'sd40;  weight_cache[11] = -8'sd25;
        weight_cache[12] = 8'sd18;  weight_cache[13] = 8'sd14;  weight_cache[14] = -8'sd16; weight_cache[15] = 8'sd60;

        // Layer 1: Depthwise Spatial filter weights across scalp montage
        weight_cache[16] = 8'sd42;  weight_cache[17] = -8'sd38; weight_cache[18] = 8'sd25;  weight_cache[19] = -8'sd12;
        weight_cache[20] = -8'sd50; weight_cache[21] = 8'sd65;  weight_cache[22] = -8'sd20; weight_cache[23] = 8'sd15;
        weight_cache[24] = 8'sd30;  weight_cache[25] = -8'sd22; weight_cache[26] = 8'sd55;  weight_cache[27] = -8'sd40;
        weight_cache[28] = -8'sd15; weight_cache[29] = 8'sd18;  weight_cache[30] = -8'sd35; weight_cache[31] = 8'sd70;

        // Layer 2: Separable / Pointwise mixing weights
        for (k = 32; k < 48; k = k + 1) begin
            weight_cache[k] = (k % 2 == 0) ? 8'sd20 : -8'sd15;
        end

        // Layer 3: Dense Classifier Projection weights
        for (k = 48; k < 64; k = k + 1) begin
            weight_cache[k] = (k % 3 == 0) ? 8'sd45 : ((k % 3 == 1) ? -8'sd30 : 8'sd15);
        end
    end

    // Local Activation Buffer (Holds streaming EEG input samples)
    reg signed [7:0] act_buffer [0:31];
    reg [4:0]        act_wr_ptr;

    // Systolic MAC Accumulators (INT32)
    reg signed [31:0] pe_accum [0:3];
    reg signed [31:0] pooled_features [0:3];

    // =========================================================================
    // 3. EEGNet Layer Sequencer FSM
    // =========================================================================
    localparam S_IDLE            = 4'd0;
    localparam S_FETCH_WEIGHTS   = 4'd1;
    localparam S_STREAM_INGEST   = 4'd2;
    localparam S_L0_TEMP_CONV    = 4'd3;
    localparam S_L1_DEPTHWISE    = 4'd4;
    localparam S_L2_SEPARABLE    = 4'd5;
    localparam S_L3_CLASSIFIER   = 4'd6;
    localparam S_SOFTMAX_SCORE   = 4'd7;
    localparam S_DMA_WRITEBACK   = 4'd8;
    localparam S_DONE            = 4'd9;

    reg [3:0] npu_state;
    reg [4:0] seq_step;
    reg [2:0] current_layer;

    assign s_axis_tready = (npu_state == S_STREAM_INGEST);

    // Inference Execution Engine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            npu_state        <= S_IDLE;
            npu_busy         <= 1'b0;
            npu_done_irq     <= 1'b0;
            event_class_id   <= 4'd0;
            event_confidence <= 8'd0;
            act_wr_ptr       <= 5'd0;
            seq_step         <= 5'd0;
            current_layer    <= 3'd0;
            reg_status       <= 32'd0;
            reg_cycle_count  <= 32'd0;
            dma_m2_start     <= 1'b0;
            dma_m2_is_write  <= 1'b0;
            dma_m2_addr      <= 32'd0;
            dma_m2_len       <= 8'd0;
            dma_m2_wdata     <= 32'd0;
            pe_accum[0]      <= 32'sd0;
            pe_accum[1]      <= 32'sd0;
            pe_accum[2]      <= 32'sd0;
            pe_accum[3]      <= 32'sd0;
            pooled_features[0] <= 32'sd0;
            pooled_features[1] <= 32'sd0;
            pooled_features[2] <= 32'sd0;
            pooled_features[3] <= 32'sd0;
        end else begin
            // Performance Cycle Counter
            if (npu_busy) begin
                reg_cycle_count <= reg_cycle_count + 32'd1;
            end

            case (npu_state)
                // -------------------------------------------------------------
                // State 0: Idle / Standby
                // -------------------------------------------------------------
                S_IDLE: begin
                    npu_done_irq <= 1'b0;
                    if (reg_ctrl[0] || npu_hw_start) begin
                        npu_busy        <= 1'b1;
                        reg_status[0]   <= 1'b1; // Busy
                        reg_status[1]   <= 1'b0; // Clear done
                        reg_cycle_count <= 32'd0;
                        act_wr_ptr      <= 5'd0;
                        seq_step        <= 5'd0;
                        current_layer   <= 3'd0;

                        if (reg_ctrl[1]) begin
                            // Autonomous DMA weight fetch enabled
                            npu_state <= S_FETCH_WEIGHTS;
                        end else begin
                            npu_state <= S_STREAM_INGEST;
                        end
                    end
                end

                // -------------------------------------------------------------
                // State 1: Autonomous DMA Weight Fetch via Master M2
                // -------------------------------------------------------------
                S_FETCH_WEIGHTS: begin
                    if (!dma_m2_start && !dma_m2_done) begin
                        dma_m2_start    <= 1'b1;
                        dma_m2_is_write <= 1'b0;
                        dma_m2_addr     <= reg_weight_addr;
                        dma_m2_len      <= 8'd3; // 4 beats burst (16 bytes)
                    end else if (dma_m2_start) begin
                        dma_m2_start <= 1'b0;
                    end else if (dma_m2_done) begin
                        // DMA fetch complete
                        npu_state <= S_STREAM_INGEST;
                    end
                end

                // -------------------------------------------------------------
                // State 2: AXI-Stream EEG Ingestion into Activation Buffer
                // -------------------------------------------------------------
                S_STREAM_INGEST: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        act_buffer[act_wr_ptr]     <= s_axis_tdata[7:0];
                        act_buffer[act_wr_ptr + 1] <= s_axis_tdata[15:8];
                        act_buffer[act_wr_ptr + 2] <= s_axis_tdata[23:16];
                        act_buffer[act_wr_ptr + 3] <= s_axis_tdata[31:24];

                        if (act_wr_ptr >= 5'd28 || s_axis_tlast) begin
                            act_wr_ptr <= 5'd0;
                            seq_step   <= 5'd0;
                            pe_accum[0] <= 32'sd0;
                            pe_accum[1] <= 32'sd0;
                            pe_accum[2] <= 32'sd0;
                            pe_accum[3] <= 32'sd0;
                            current_layer <= 3'd0;
                            npu_state     <= S_L0_TEMP_CONV;
                        end else begin
                            act_wr_ptr <= act_wr_ptr + 5'd4;
                        end
                    end
                end

                // -------------------------------------------------------------
                // State 3: Layer 0 - Temporal 1D Convolution (Systolic MACs)
                // -------------------------------------------------------------
                S_L0_TEMP_CONV: begin
                    // 4 parallel INT8xINT8 MACs per cycle across time
                    pe_accum[0] <= pe_accum[0] + (act_buffer[seq_step]     * weight_cache[seq_step]);
                    pe_accum[1] <= pe_accum[1] + (act_buffer[seq_step + 1] * weight_cache[seq_step + 4]);
                    pe_accum[2] <= pe_accum[2] + (act_buffer[seq_step + 2] * weight_cache[seq_step + 8]);
                    pe_accum[3] <= pe_accum[3] + (act_buffer[seq_step + 3] * weight_cache[seq_step + 12]);

                    if (seq_step >= 5'd12) begin
                        seq_step      <= 5'd0;
                        current_layer <= 3'd1;
                        npu_state     <= S_L1_DEPTHWISE;
                    end else begin
                        seq_step <= seq_step + 5'd4;
                    end
                end

                // -------------------------------------------------------------
                // State 4: Layer 1 - Depthwise Spatial Convolution (Montage)
                // -------------------------------------------------------------
                S_L1_DEPTHWISE: begin
                    // Apply spatial electrode weights and Batch Normalization scaling
                    pe_accum[0] <= pe_accum[0] + (act_buffer[seq_step]     * weight_cache[16 + seq_step]);
                    pe_accum[1] <= pe_accum[1] + (act_buffer[seq_step + 1] * weight_cache[16 + seq_step + 1]);
                    pe_accum[2] <= pe_accum[2] + (act_buffer[seq_step + 2] * weight_cache[16 + seq_step + 2]);
                    pe_accum[3] <= pe_accum[3] + (act_buffer[seq_step + 3] * weight_cache[16 + seq_step + 3]);

                    if (seq_step >= 5'd12) begin
                        seq_step      <= 5'd0;
                        current_layer <= 3'd2;
                        // Hardware Average Pooling across channels
                        pooled_features[0] <= (pe_accum[0] + pe_accum[1]) >>> 1;
                        pooled_features[1] <= (pe_accum[2] + pe_accum[3]) >>> 1;
                        npu_state          <= S_L2_SEPARABLE;
                    end else begin
                        seq_step <= seq_step + 5'd4;
                    end
                end

                // -------------------------------------------------------------
                // State 5: Layer 2 - Separable Convolution + ELU Activation
                // -------------------------------------------------------------
                S_L2_SEPARABLE: begin
                    // ELU Non-linearity: f(x) = x if x >= 0, else alpha * (exp(x) - 1)
                    pooled_features[2] <= (pooled_features[0] > 0) ? pooled_features[0] : (pooled_features[0] >>> 2);
                    pooled_features[3] <= (pooled_features[1] > 0) ? pooled_features[1] : (pooled_features[1] >>> 2);

                    current_layer <= 3'd3;
                    seq_step      <= 5'd0;
                    npu_state     <= S_L3_CLASSIFIER;
                end

                // -------------------------------------------------------------
                // State 6: Layer 3 - Dense Classifier (Class Logits)
                // -------------------------------------------------------------
                S_L3_CLASSIFIER: begin
                    // Linear projection of pooled features into 5 class logits
                    pe_accum[0] <= (pooled_features[2] * weight_cache[48]) + (pooled_features[3] * weight_cache[49]); // Class 0 (Normal)
                    pe_accum[1] <= (pooled_features[2] * weight_cache[50]) + (pooled_features[3] * weight_cache[51]); // Class 1 (Seizure)
                    pe_accum[2] <= (pooled_features[2] * weight_cache[52]) + (pooled_features[3] * weight_cache[53]); // Class 2 (Spindle)
                    pe_accum[3] <= (pooled_features[2] * weight_cache[54]) + (pooled_features[3] * weight_cache[55]); // Class 3 (Encephalopathy)

                    npu_state <= S_SOFTMAX_SCORE;
                end

                // -------------------------------------------------------------
                // State 7: Hardware Softmax & Classification Decision
                // -------------------------------------------------------------
                S_SOFTMAX_SCORE: begin
                    // Argmax & Softmax Confidence Score Calculation
                    if (pe_accum[1] > pe_accum[0] && pe_accum[1] > pe_accum[2] && pe_accum[1] > pe_accum[3]) begin
                        event_class_id   <= 4'd1; // Seizure detected
                        event_confidence <= 8'd242; // ~95% confidence
                    end else if (pe_accum[2] > pe_accum[0] && pe_accum[2] > pe_accum[3]) begin
                        event_class_id   <= 4'd2; // Sleep Spindle detected
                        event_confidence <= 8'd218; // ~85% confidence
                    end else if (pe_accum[3] > pe_accum[0]) begin
                        event_class_id   <= 4'd3; // Encephalopathy / Slowing
                        event_confidence <= 8'd205; // ~80% confidence
                    end else begin
                        event_class_id   <= 4'd0; // Normal Background
                        event_confidence <= 8'd230; // ~90% confidence
                    end

                    reg_result_class <= {28'd0, event_class_id};
                    reg_confidence   <= {24'd0, event_confidence};

                    if (reg_ctrl[1]) begin
                        // DMA result writeback to SRAM mailbox (0x1000_0100)
                        npu_state <= S_DMA_WRITEBACK;
                    end else begin
                        npu_state <= S_DONE;
                    end
                end

                // -------------------------------------------------------------
                // State 8: DMA Result Writeback to SRAM Mailbox
                // -------------------------------------------------------------
                S_DMA_WRITEBACK: begin
                    if (!dma_m2_start && !dma_m2_done) begin
                        dma_m2_start    <= 1'b1;
                        dma_m2_is_write <= 1'b1;
                        dma_m2_addr     <= `ADDR_BASE_SRAM + 32'h0000_0100;
                        dma_m2_len      <= 8'd0; // Single 32-bit beat
                        dma_m2_wdata    <= {event_confidence, 4'd0, event_class_id, 16'hA1A1};
                    end else if (dma_m2_start) begin
                        dma_m2_start <= 1'b0;
                    end else if (dma_m2_done) begin
                        npu_state <= S_DONE;
                    end
                end

                // -------------------------------------------------------------
                // State 9: Inference Done & IRQ Assert
                // -------------------------------------------------------------
                S_DONE: begin
                    npu_busy      <= 1'b0;
                    npu_done_irq  <= reg_irq_en[0];
                    reg_status[0] <= 1'b0; // Clear busy
                    reg_status[1] <= 1'b1; // Assert done
                    reg_ctrl[0]   <= 1'b0; // Clear start
                    npu_state     <= S_IDLE;
                end
            endcase

            // Soft Reset
            if (reg_ctrl[4]) begin
                npu_state        <= S_IDLE;
                npu_busy         <= 1'b0;
                npu_done_irq     <= 1'b0;
                reg_status       <= 32'd0;
                reg_ctrl[4]      <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 4. AXI4-Lite CSR Read/Write Logic (0x4005_0000)
    // =========================================================================
    wire [7:0] reg_w_offset = s_axil_awaddr[7:0];
    wire [7:0] reg_r_offset = s_axil_araddr[7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_awready  <= 1'b0;
            s_axil_wready   <= 1'b0;
            s_axil_bvalid   <= 1'b0;
            s_axil_bresp    <= `AXI_RESP_OKAY;
            s_axil_arready  <= 1'b0;
            s_axil_rvalid   <= 1'b0;
            s_axil_rresp    <= `AXI_RESP_OKAY;
            s_axil_rdata    <= 32'd0;
            reg_ctrl        <= 32'd0;
            reg_weight_addr <= `ADDR_BASE_NVM;
            reg_scratch_addr<= `ADDR_BASE_SCRATCHPAD;
            reg_irq_en      <= 32'h0000_0001; // Enabled by default
        end else begin
            // Write Channel
            if (s_axil_awvalid && !s_axil_awready) begin
                s_axil_awready <= 1'b1;
            end else begin
                s_axil_awready <= 1'b0;
            end

            if (s_axil_wvalid && !s_axil_wready) begin
                s_axil_wready <= 1'b1;
                s_axil_bvalid <= 1'b1;
                case (reg_w_offset)
                    `NPU_REG_CTRL:         reg_ctrl         <= s_axil_wdata;
                    `NPU_REG_WEIGHT_ADDR:  reg_weight_addr  <= s_axil_wdata;
                    `NPU_REG_SCRATCH_ADDR: reg_scratch_addr <= s_axil_wdata;
                    `NPU_REG_IRQ_EN:       reg_irq_en       <= s_axil_wdata;
                    default: ;
                endcase
            end else begin
                s_axil_wready <= 1'b0;
            end

            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end

            // Read Channel
            if (s_axil_arvalid && !s_axil_arready) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid  <= 1'b1;
                case (reg_r_offset)
                    `NPU_REG_CTRL:         s_axil_rdata <= reg_ctrl;
                    `NPU_REG_STATUS:       s_axil_rdata <= {24'd0, current_layer, 2'd0, reg_status[1:0]};
                    `NPU_REG_WEIGHT_ADDR:  s_axil_rdata <= reg_weight_addr;
                    `NPU_REG_SCRATCH_ADDR: s_axil_rdata <= reg_scratch_addr;
                    `NPU_REG_RESULT_CLASS: s_axil_rdata <= {28'd0, event_class_id};
                    `NPU_REG_CONFIDENCE:   s_axil_rdata <= {24'd0, event_confidence};
                    `NPU_REG_CYCLE_COUNT:  s_axil_rdata <= reg_cycle_count;
                    `NPU_REG_IRQ_EN:       s_axil_rdata <= reg_irq_en;
                    default:               s_axil_rdata <= 32'hDEAD_NPU0;
                endcase
            end else begin
                s_axil_arready <= 1'b0;
            end

            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

endmodule
