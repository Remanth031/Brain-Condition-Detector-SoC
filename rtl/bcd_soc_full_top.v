// =============================================================================
// Brain Condition Detector (BCD) SoC - Full System-on-Chip Top-Level Integration
// Wires the complete end-to-end heterogeneous architecture:
// - VeeR EL2 RISC-V Management Core (Master M0)
// - AXI DMA Engine (Master M1)
// - Edge-AI NPU Accelerator (Master M2)
// - Swin Transformer Accelerator (Master M3)
// - Output / Display DMA (Master M4)
// - JTAG-to-AXI Debug Master (Master M5)
// - 6x6 AXI4 Crossbar Interconnect with QoS Arbitration & Address Decoder
// - AXI Security Firewall Unit
// - AXI4-to-AXI4-Lite Bridge & Peripheral CSR Cluster (0x4000_0000 - 0x4009_0000)
// - S0: Boot ROM (0x0000_0000, 64 KiB)
// - S1: On-chip SRAM Ring Buffer (0x1000_0000, 1 MiB)
// - S2: Accelerator Scratchpads (0x1100_0000, 2 MiB)
// - S4: QSPI NVM / MRAM (0x6000_0000, 128 MiB)
// - S5: LPDDR Memory Controller (0x8000_0000, 1 GiB)
// - Streaming Pipeline: ADC Deserializer -> DSP FIFO -> Filter Bank -> Feature Extractor
// - Real-time RTL Threshold Engine with N-of-M voting & Wake-up Request
// - AXIS Broadcaster replicating flagged streams with per-port Skid Buffers
// - STFT Spectrogram Generator & MRI/CT Imaging Ingest Block
// - Output Fusion & Clinical Finding Report Generator
// - Normal Path Delta+Rice Low-Power Compressor
// - PMU Power Island Sequencer & AXI Quiescer
// - AES-256-GCM, SHA-256 & TRNG Hardware Security Engine
// =============================================================================

`include "bcd_soc_pkg.vh"

module bcd_soc_full_top #(
    parameter ADDR_WIDTH          = 32,
    parameter DATA_WIDTH          = 32,
    parameter STRB_WIDTH          = (DATA_WIDTH / 8),
    parameter ID_WIDTH            = 4,
    parameter BOOT_HEX_FILE       = "",
    parameter SRAM_MEM_FILE       = "",
    parameter SCRATCHPAD_HEX_FILE = "",
    parameter NVM_HEX_FILE        = "",
    parameter LPDDR_HEX_FILE      = ""
)(
    // Clocks and Resets
    input  wire                   clk_ao,           // Always-On domain clock (e.g. 50-100 MHz)
    input  wire                   rst_ao_n,         // Always-On domain active-low reset
    input  wire                   clk_adc,          // ADC sampling clock (e.g. 1-4 MHz)
    input  wire                   rst_adc_n,

    // Raw ADC Serial/Parallel Ingest (Tier 1 Sensors)
    input  wire                   adc_sample_valid,
    input  wire [23:0]            adc_raw_data,
    input  wire [4:0]             adc_channel_id,
    input  wire                   adc_lead_off_flag,
    input  wire                   adc_saturation_flag,

    // Host Slice Ingest Interface (Tier 3 MRI/CT Tumor Pathway)
    input  wire                   host_pixel_valid,
    input  wire [15:0]            host_pixel_data,
    output wire                   host_pixel_ready,

    // CPU Control & PMU Interface
    input  wire                   cpu_halt_req,
    output wire                   cpu_halt_ack,
    input  wire                   cpu_run_req,
    output wire                   cpu_run_ack,

    // Firewall & Security Pin Controls
    input  wire                   firewall_en,
    input  wire                   production_mode,

    // JTAG Debug Master M5 Stimulus
    input  wire                   jtag_cmd_start,
    input  wire                   jtag_cmd_is_write,
    input  wire [ADDR_WIDTH-1:0]  jtag_cmd_addr,
    input  wire [7:0]             jtag_cmd_len,
    input  wire [DATA_WIDTH-1:0]  jtag_cmd_wdata,
    output wire                   jtag_cmd_done,
    output wire [DATA_WIDTH-1:0]  jtag_cmd_rdata,

    // System Telemetry & Clinical Outputs
    output wire [15:0]            compressed_normal_word, // Low-rate Rice compressed summary over BLE
    output wire [4:0]             compressed_bit_length,
    output wire                   compressed_valid,
    output wire [3:0]             clinical_event_label,   // 0=Normal, 1=Seizure, 2=Spindle, 3=Artifact
    output wire [7:0]             clinical_confidence,    // 0-255 confidence metric
    output wire [31:0]            diagnostic_heatmap_pixel,
    output wire [63:0]            clinical_report_ascii,  // e.g. "SEIZURE!" in ASCII
    output wire                   system_alarm_irq
);

    // =========================================================================
    // 1. Crossbar Signals (6 Masters x 6 Slaves)
    // =========================================================================
    wire [6*ID_WIDTH-1:0]    xb_s_awid;
    wire [6*ADDR_WIDTH-1:0]  xb_s_awaddr;
    wire [6*8-1:0]           xb_s_awlen;
    wire [6*3-1:0]           xb_s_awsize;
    wire [6*2-1:0]           xb_s_awburst;
    wire [6*4-1:0]           xb_s_awqos;
    wire [5:0]               xb_s_awvalid;
    wire [5:0]               xb_s_awready;

    wire [6*DATA_WIDTH-1:0]  xb_s_wdata;
    wire [6*STRB_WIDTH-1:0]  xb_s_wstrb;
    wire [5:0]               xb_s_wlast;
    wire [5:0]               xb_s_wvalid;
    wire [5:0]               xb_s_wready;

    wire [6*ID_WIDTH-1:0]    xb_s_bid;
    wire [6*2-1:0]           xb_s_bresp;
    wire [5:0]               xb_s_bvalid;
    wire [5:0]               xb_s_bready;

    wire [6*ID_WIDTH-1:0]    xb_s_arid;
    wire [6*ADDR_WIDTH-1:0]  xb_s_araddr;
    wire [6*8-1:0]           xb_s_arlen;
    wire [6*3-1:0]           xb_s_arsize;
    wire [6*2-1:0]           xb_s_arburst;
    wire [6*4-1:0]           xb_s_arqos;
    wire [5:0]               xb_s_arvalid;
    wire [5:0]               xb_s_arready;

    wire [6*ID_WIDTH-1:0]    xb_s_rid;
    wire [6*DATA_WIDTH-1:0]  xb_s_rdata;
    wire [6*2-1:0]           xb_s_rresp;
    wire [5:0]               xb_s_rlast;
    wire [5:0]               xb_s_rvalid;
    wire [5:0]               xb_s_rready;

    wire [6*ID_WIDTH-1:0]    xb_m_awid;
    wire [6*ADDR_WIDTH-1:0]  xb_m_awaddr;
    wire [6*8-1:0]           xb_m_awlen;
    wire [6*3-1:0]           xb_m_awsize;
    wire [6*2-1:0]           xb_m_awburst;
    wire [5:0]               xb_m_awvalid;
    wire [5:0]               xb_m_awready;

    wire [6*DATA_WIDTH-1:0]  xb_m_wdata;
    wire [6*STRB_WIDTH-1:0]  xb_m_wstrb;
    wire [5:0]               xb_m_wlast;
    wire [5:0]               xb_m_wvalid;
    wire [5:0]               xb_m_wready;

    wire [6*ID_WIDTH-1:0]    xb_m_bid;
    wire [6*2-1:0]           xb_m_bresp;
    wire [5:0]               xb_m_bvalid;
    wire [5:0]               xb_m_bready;

    wire [6*ID_WIDTH-1:0]    xb_m_arid;
    wire [6*ADDR_WIDTH-1:0]  xb_m_araddr;
    wire [6*8-1:0]           xb_m_arlen;
    wire [6*3-1:0]           xb_m_arsize;
    wire [6*2-1:0]           xb_m_arburst;
    wire [5:0]               xb_m_arvalid;
    wire [5:0]               xb_m_arready;

    wire [6*ID_WIDTH-1:0]    xb_m_rid;
    wire [6*DATA_WIDTH-1:0]  xb_m_rdata;
    wire [6*2-1:0]           xb_m_rresp;
    wire [5:0]               xb_m_rlast;
    wire [5:0]               xb_m_rvalid;
    wire [5:0]               xb_m_rready;

    // =========================================================================
    // 2. Hardware Control & Interrupt Signals
    // =========================================================================
    wire threshold_abnormal_irq;
    wire [2:0] threshold_wake_target;
    wire firewall_violation_irq;
    wire npu_done_irq;
    wire swin_done_irq;
    wire report_ready_irq;
    wire dma_done_irq;

    assign system_alarm_irq = threshold_abnormal_irq || firewall_violation_irq;

    // PMU Controls
    wire power_switch_compute;
    wire isolation_clamp;
    wire compute_rst_n;
    wire compute_clk_gate;
    wire npu_busy, swin_busy;

    // =========================================================================
    // 3. Streaming Signal Chain (Always-On Domain)
    // =========================================================================
    // ADC Deserializer
    wire [DATA_WIDTH-1:0] adc_axis_data;
    wire [4:0]            adc_axis_id;
    wire [1:0]            adc_axis_user;
    wire                  adc_axis_last;
    wire                  adc_axis_valid;
    wire                  adc_axis_ready;

    ip_adc_deserializer u_adc_deserializer (
        .clk(clk_adc), .rst_n(rst_adc_n),
        .adc_frame_sync(1'b1), .adc_sample_valid(adc_sample_valid),
        .adc_raw_data(adc_raw_data), .adc_channel_id(adc_channel_id),
        .adc_lead_off_flag(adc_lead_off_flag), .adc_saturation_flag(adc_saturation_flag),
        .m_axis_tdata(adc_axis_data), .m_axis_tid(adc_axis_id),
        .m_axis_tuser(adc_axis_user), .m_axis_tlast(adc_axis_last),
        .m_axis_tvalid(adc_axis_valid), .m_axis_tready(adc_axis_ready),
        .sample_counter()
    );

    // DSP Rate-Matching Async FIFO (CDC)
    wire [DATA_WIDTH-1:0] dsp_fifo_data;
    wire [4:0]            dsp_fifo_id;
    wire [1:0]            dsp_fifo_user;
    wire                  dsp_fifo_last;
    wire                  dsp_fifo_valid;
    wire                  dsp_fifo_ready;

    ip_dsp_async_fifo u_dsp_fifo (
        .wr_clk(clk_adc), .wr_rst_n(rst_adc_n),
        .s_axis_tdata(adc_axis_data), .s_axis_tid(adc_axis_id),
        .s_axis_tuser(adc_axis_user), .s_axis_tlast(adc_axis_last),
        .s_axis_tvalid(adc_axis_valid), .s_axis_tready(adc_axis_ready),
        .rd_clk(clk_ao), .rd_rst_n(rst_ao_n),
        .m_axis_tdata(dsp_fifo_data), .m_axis_tid(dsp_fifo_id),
        .m_axis_tuser(dsp_fifo_user), .m_axis_tlast(dsp_fifo_last),
        .m_axis_tvalid(dsp_fifo_valid), .m_axis_tready(dsp_fifo_ready),
        .fifo_full(), .fifo_empty(), .fifo_overflow(), .fifo_occupancy()
    );

    // Digital Filter Bank (0.5-100Hz BPF, 50Hz Notch, CAR)
    wire [DATA_WIDTH-1:0] filtered_data;
    wire [4:0]            filtered_id;
    wire [1:0]            filtered_user;
    wire                  filtered_last;
    wire                  filtered_valid;
    wire                  filtered_ready;

    ip_digital_filter_bank u_digital_filter (
        .clk(clk_ao), .rst_n(rst_ao_n),
        .filter_en(1'b1), .notch_50hz_en(1'b1), .car_en(1'b1),
        .s_axis_tdata(dsp_fifo_data), .s_axis_tid(dsp_fifo_id),
        .s_axis_tuser(dsp_fifo_user), .s_axis_tlast(dsp_fifo_last),
        .s_axis_tvalid(dsp_fifo_valid), .s_axis_tready(dsp_fifo_ready),
        .m_axis_tdata(filtered_data), .m_axis_tid(filtered_id),
        .m_axis_tuser(filtered_user), .m_axis_tlast(filtered_last),
        .m_axis_tvalid(filtered_valid), .m_axis_tready(filtered_ready)
    );

    // Streaming Feature Extractor
    wire [31:0] feat_ll, feat_bp_ratio, feat_entropy;
    wire        feat_valid;

    ip_streaming_feature_extractor u_feature_extractor (
        .clk(clk_ao), .rst_n(rst_ao_n),
        .s_axis_tdata(filtered_data), .s_axis_tid(filtered_id),
        .s_axis_tlast(filtered_last), .s_axis_tvalid(filtered_valid),
        .s_axis_tready(filtered_ready),
        .feat_line_length(feat_ll), .feat_delta_power(), .feat_theta_power(),
        .feat_alpha_power(), .feat_beta_power(), .feat_bp_ratio(feat_bp_ratio),
        .feat_spectral_entropy(feat_entropy), .features_valid(feat_valid)
    );

    // Normal Path Compressor (Delta + Rice Encoding)
    ip_normal_compressor u_normal_compressor (
        .clk(clk_ao), .rst_n(rst_ao_n),
        .compress_en(!threshold_abnormal_irq),
        .s_axis_tdata(filtered_data), .s_axis_tvalid(filtered_valid),
        .s_axis_tready(),
        .comp_data_word(compressed_normal_word),
        .comp_bit_length(compressed_bit_length),
        .comp_valid(compressed_valid),
        .comp_ready(1'b1)
    );

    // =========================================================================
    // 4. Power-Gated Compute Acceleration Chain
    // =========================================================================
    // AXIS Broadcaster & Switch
    wire [DATA_WIDTH-1:0] npu_in_data, swin_in_data;
    wire                  npu_in_valid, npu_in_ready;
    wire                  swin_in_valid, swin_in_ready;
    wire                  npu_in_last, swin_in_last;

    ip_axis_broadcaster u_axis_broadcaster (
        .clk(clk_ao), .rst_n(rst_ao_n),
        .route_enable(threshold_wake_target[1:0]),
        .s_axis_tdata(filtered_data), .s_axis_tid(filtered_id),
        .s_axis_tlast(filtered_last), .s_axis_tvalid(filtered_valid && threshold_abnormal_irq),
        .s_axis_tready(),
        .m0_axis_tdata(npu_in_data), .m0_axis_tid(), .m0_axis_tlast(npu_in_last),
        .m0_axis_tvalid(npu_in_valid), .m0_axis_tready(npu_in_ready),
        .m1_axis_tdata(swin_in_data), .m1_axis_tid(), .m1_axis_tlast(swin_in_last),
        .m1_axis_tvalid(swin_in_valid), .m1_axis_tready(swin_in_ready)
    );

    // -------------------------------------------------------------------------
    // Accelerators CSR Sub-Buses & Autonomous DMA Interconnect Wires
    // -------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] npu_axil_awaddr;
    wire                  npu_axil_awvalid, npu_axil_awready;
    wire [DATA_WIDTH-1:0] npu_axil_wdata;
    wire [3:0]            npu_axil_wstrb;
    wire                  npu_axil_wvalid, npu_axil_wready;
    wire [1:0]            npu_axil_bresp;
    wire                  npu_axil_bvalid, npu_axil_bready;
    wire [ADDR_WIDTH-1:0] npu_axil_araddr;
    wire                  npu_axil_arvalid, npu_axil_arready;
    wire [DATA_WIDTH-1:0] npu_axil_rdata;
    wire [1:0]            npu_axil_rresp;
    wire                  npu_axil_rvalid, npu_axil_rready;

    wire [ADDR_WIDTH-1:0] swin_axil_awaddr;
    wire                  swin_axil_awvalid, swin_axil_awready;
    wire [DATA_WIDTH-1:0] swin_axil_wdata;
    wire [3:0]            swin_axil_wstrb;
    wire                  swin_axil_wvalid, swin_axil_wready;
    wire [1:0]            swin_axil_bresp;
    wire                  swin_axil_bvalid, swin_axil_bready;
    wire [ADDR_WIDTH-1:0] swin_axil_araddr;
    wire                  swin_axil_arvalid, swin_axil_arready;
    wire [DATA_WIDTH-1:0] swin_axil_rdata;
    wire [1:0]            swin_axil_rresp;
    wire                  swin_axil_rvalid, swin_axil_rready;

    wire                  dma_m2_start;
    wire                  dma_m2_is_write;
    wire [ADDR_WIDTH-1:0] dma_m2_addr;
    wire [7:0]            dma_m2_len;
    wire [DATA_WIDTH-1:0] dma_m2_wdata;
    wire                  dma_m2_done;
    wire [DATA_WIDTH-1:0] dma_m2_rdata;

    wire                  dma_m3_start;
    wire                  dma_m3_is_write;
    wire [ADDR_WIDTH-1:0] dma_m3_addr;
    wire [7:0]            dma_m3_len;
    wire [DATA_WIDTH-1:0] dma_m3_wdata;
    wire                  dma_m3_done;
    wire [DATA_WIDTH-1:0] dma_m3_rdata;

    // Edge-AI NPU Accelerator (Master M2)
    wire [3:0] npu_class;
    wire [7:0] npu_conf;

    ip_edge_ai_npu #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_edge_ai_npu (
        .clk(clk_ao), .rst_n(rst_ao_n && compute_rst_n),
        .s_axil_awaddr(npu_axil_awaddr), .s_axil_awvalid(npu_axil_awvalid), .s_axil_awready(npu_axil_awready),
        .s_axil_wdata(npu_axil_wdata), .s_axil_wstrb(npu_axil_wstrb), .s_axil_wvalid(npu_axil_wvalid), .s_axil_wready(npu_axil_wready),
        .s_axil_bresp(npu_axil_bresp), .s_axil_bvalid(npu_axil_bvalid), .s_axil_bready(npu_axil_bready),
        .s_axil_araddr(npu_axil_araddr), .s_axil_arvalid(npu_axil_arvalid), .s_axil_arready(npu_axil_arready),
        .s_axil_rdata(npu_axil_rdata), .s_axil_rresp(npu_axil_rresp), .s_axil_rvalid(npu_axil_rvalid), .s_axil_rready(npu_axil_rready),
        .npu_hw_start(threshold_abnormal_irq && threshold_wake_target[0]),
        .s_axis_tdata(npu_in_data), .s_axis_tlast(npu_in_last),
        .s_axis_tvalid(npu_in_valid), .s_axis_tready(npu_in_ready),
        .dma_m2_start(dma_m2_start), .dma_m2_is_write(dma_m2_is_write), .dma_m2_addr(dma_m2_addr),
        .dma_m2_len(dma_m2_len), .dma_m2_wdata(dma_m2_wdata), .dma_m2_done(dma_m2_done), .dma_m2_rdata(dma_m2_rdata),
        .npu_busy(npu_busy), .npu_done_irq(npu_done_irq),
        .event_class_id(npu_class), .event_confidence(npu_conf)
    );

    // Spectrogram STFT Generator
    wire [DATA_WIDTH-1:0] spec_token_data;
    wire spec_token_valid, spec_token_ready;

    ip_spectrogram_generator u_spectrogram_gen (
        .clk(clk_ao), .rst_n(rst_ao_n && compute_rst_n),
        .stft_en(threshold_wake_target[1]),
        .s_axis_tdata(swin_in_data), .s_axis_tlast(swin_in_last),
        .s_axis_tvalid(swin_in_valid), .s_axis_tready(swin_in_ready),
        .m_axis_tdata(spec_token_data), .m_axis_freq_bin(), .m_axis_time_step(),
        .m_axis_tlast(), .m_axis_tvalid(spec_token_valid), .m_axis_tready(spec_token_ready)
    );

    // Swin Transformer Accelerator Engine (Master M3)
    wire [3:0]  swin_class;
    wire [7:0]  swin_conf;
    wire [31:0] saliency_val;

    ip_swin_transformer_engine #(
        .TOKEN_DIM(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_swin_transformer (
        .clk(clk_ao), .rst_n(rst_ao_n && compute_rst_n),
        .s_axil_awaddr(swin_axil_awaddr), .s_axil_awvalid(swin_axil_awvalid), .s_axil_awready(swin_axil_awready),
        .s_axil_wdata(swin_axil_wdata), .s_axil_wstrb(swin_axil_wstrb), .s_axil_wvalid(swin_axil_wvalid), .s_axil_wready(swin_axil_wready),
        .s_axil_bresp(swin_axil_bresp), .s_axil_bvalid(swin_axil_bvalid), .s_axil_bready(swin_axil_bready),
        .s_axil_araddr(swin_axil_araddr), .s_axil_arvalid(swin_axil_arvalid), .s_axil_arready(swin_axil_arready),
        .s_axil_rdata(swin_axil_rdata), .s_axil_rresp(swin_axil_rresp), .s_axil_rvalid(swin_axil_rvalid), .s_axil_rready(swin_axil_rready),
        .swin_hw_start(threshold_abnormal_irq && threshold_wake_target[1]),
        .token_in_data(spec_token_data), .token_in_valid(spec_token_valid),
        .token_in_ready(spec_token_ready),
        .dma_m3_start(dma_m3_start), .dma_m3_is_write(dma_m3_is_write), .dma_m3_addr(dma_m3_addr),
        .dma_m3_len(dma_m3_len), .dma_m3_wdata(dma_m3_wdata), .dma_m3_done(dma_m3_done), .dma_m3_rdata(dma_m3_rdata),
        .saliency_out_data(saliency_val), .saliency_patch_id(), .saliency_valid(),
        .swin_busy(swin_busy), .swin_done_irq(swin_done_irq),
        .swin_class_id(swin_class), .swin_confidence(swin_conf)
    );

    // Imaging Ingest Unit (MRI/CT Slices)
    ip_imaging_ingest u_imaging_ingest (
        .clk(clk_ao), .rst_n(rst_ao_n),
        .ingest_start(1'b0), .modality_type(2'd0),
        .ingest_busy(), .ingest_done_irq(),
        .host_pixel_data(host_pixel_data), .host_pixel_valid(host_pixel_valid),
        .host_pixel_ready(host_pixel_ready),
        .norm_slice_pixel(), .norm_slice_valid(), .norm_slice_ready(1'b1),
        .total_pixels_ingested()
    );

    // Output Fusion & Clinical Report Generator
    ip_output_fusion u_output_fusion (
        .clk(clk_ao), .rst_n(rst_ao_n),
        .fusion_trigger(npu_done_irq || swin_done_irq),
        .npu_class_id(npu_class), .npu_confidence(npu_conf),
        .swin_class_id(swin_class), .swin_confidence(swin_conf),
        .saliency_heat_val(saliency_val),
        .final_class_id(clinical_event_label),
        .final_confidence(clinical_confidence),
        .diagnostic_image_word(diagnostic_heatmap_pixel),
        .report_text_ascii(clinical_report_ascii),
        .report_ready_irq(report_ready_irq)
    );

    // PMU Power Sequencer
    ip_pmu_power_sequencer u_pmu_sequencer (
        .clk_ao(clk_ao), .rst_ao_n(rst_ao_n),
        .threshold_wake_req(threshold_abnormal_irq),
        .wake_targets(threshold_wake_target),
        .npu_idle_status(!npu_busy), .swin_idle_status(!swin_busy),
        .power_switch_en_compute(power_switch_compute),
        .isolation_cell_en(isolation_clamp),
        .compute_domain_rst_n(compute_rst_n),
        .compute_clock_gate_en(compute_clk_gate),
        .pmu_state_out()
    );

    // Hardware Cryptographic Engine
    ip_crypto_engine u_crypto_engine (
        .clk(clk_ao), .rst_n(rst_ao_n),
        .start_op(1'b0), .crypto_mode(2'd0),
        .busy(), .done_irq(),
        .cipher_key(256'h0123456789ABCDEF_0123456789ABCDEF_0123456789ABCDEF_0123456789ABCDEF),
        .data_in_block(128'h0),
        .data_out_block(), .sha_digest_out(), .trng_random_word()
    );

    // =========================================================================
    // 5. Processor & Interconnect Core Subsystem
    // =========================================================================
    // M0: VeeR EL2 RISC-V Management Core
    bcd_veer_core_wrapper #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .STRB_WIDTH(STRB_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) u_veer_core (
        .clk(clk_ao), .rst_n(rst_ao_n),
        .cpu_halt_req(cpu_halt_req), .cpu_halt_ack(cpu_halt_ack),
        .cpu_halt_status(), .cpu_run_req(cpu_run_req), .cpu_run_ack(cpu_run_ack),
        .irq_threshold_abnormal(threshold_abnormal_irq),
        .irq_dma_complete(dma_done_irq),
        .irq_pmu_power_event(1'b0),
        .irq_firewall_violation(firewall_violation_irq),
        .irq_npu_done(npu_done_irq),
        .irq_swin_done(swin_done_irq),
        .irq_report_ready(report_ready_irq),
        .irq_timer_tick(1'b0),

        .m_axi_awid(xb_s_awid[0*ID_WIDTH +: ID_WIDTH]),
        .m_axi_awaddr(xb_s_awaddr[0*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_awlen(xb_s_awlen[0*8 +: 8]), .m_axi_awsize(xb_s_awsize[0*3 +: 3]),
        .m_axi_awburst(xb_s_awburst[0*2 +: 2]), .m_axi_awqos(xb_s_awqos[0*4 +: 4]),
        .m_axi_awvalid(xb_s_awvalid[0]), .m_axi_awready(xb_s_awready[0]),
        .m_axi_wdata(xb_s_wdata[0*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_wstrb(xb_s_wstrb[0*STRB_WIDTH +: STRB_WIDTH]),
        .m_axi_wlast(xb_s_wlast[0]), .m_axi_wvalid(xb_s_wvalid[0]), .m_axi_wready(xb_s_wready[0]),
        .m_axi_bid(xb_s_bid[0*ID_WIDTH +: ID_WIDTH]), .m_axi_bresp(xb_s_bresp[0*2 +: 2]),
        .m_axi_bvalid(xb_s_bvalid[0]), .m_axi_bready(xb_s_bready[0]),
        .m_axi_arid(xb_s_arid[0*ID_WIDTH +: ID_WIDTH]),
        .m_axi_araddr(xb_s_araddr[0*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_arlen(xb_s_arlen[0*8 +: 8]), .m_axi_arsize(xb_s_arsize[0*3 +: 3]),
        .m_axi_arburst(xb_s_arburst[0*2 +: 2]), .m_axi_arqos(xb_s_arqos[0*4 +: 4]),
        .m_axi_arvalid(xb_s_arvalid[0]), .m_axi_arready(xb_s_arready[0]),
        .m_axi_rid(xb_s_rid[0*ID_WIDTH +: ID_WIDTH]), .m_axi_rdata(xb_s_rdata[0*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_rresp(xb_s_rresp[0*2 +: 2]), .m_axi_rlast(xb_s_rlast[0]),
        .m_axi_rvalid(xb_s_rvalid[0]), .m_axi_rready(xb_s_rready[0]),
        .trace_pc(), .trace_valid(), .trace_instr()
    );

    // M1: AXI DMA
    axi_master_agent #(.MASTER_ID_VAL(`MASTER_M1_DMA), .DEFAULT_QOS(4'd12)) u_master_m1 (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .cmd_start(1'b0), .cmd_is_write(1'b0), .cmd_addr(32'd0),
        .cmd_len(8'd0), .cmd_size(3'b010), .cmd_burst(`AXI_BURST_INCR), .cmd_qos(4'd12),
        .cmd_wdata(32'd0), .cmd_wstrb(4'b1111), .cmd_done(dma_done_irq),
        .cmd_resp(), .cmd_rdata(),
        .m_axi_awid(xb_s_awid[1*ID_WIDTH +: ID_WIDTH]), .m_axi_awaddr(xb_s_awaddr[1*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_awlen(xb_s_awlen[1*8 +: 8]), .m_axi_awsize(xb_s_awsize[1*3 +: 3]),
        .m_axi_awburst(xb_s_awburst[1*2 +: 2]), .m_axi_awqos(xb_s_awqos[1*4 +: 4]),
        .m_axi_awvalid(xb_s_awvalid[1]), .m_axi_awready(xb_s_awready[1]),
        .m_axi_wdata(xb_s_wdata[1*DATA_WIDTH +: DATA_WIDTH]), .m_axi_wstrb(xb_s_wstrb[1*STRB_WIDTH +: STRB_WIDTH]),
        .m_axi_wlast(xb_s_wlast[1]), .m_axi_wvalid(xb_s_wvalid[1]), .m_axi_wready(xb_s_wready[1]),
        .m_axi_bid(xb_s_bid[1*ID_WIDTH +: ID_WIDTH]), .m_axi_bresp(xb_s_bresp[1*2 +: 2]),
        .m_axi_bvalid(xb_s_bvalid[1]), .m_axi_bready(xb_s_bready[1]),
        .m_axi_arid(xb_s_arid[1*ID_WIDTH +: ID_WIDTH]), .m_axi_araddr(xb_s_araddr[1*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_arlen(xb_s_arlen[1*8 +: 8]), .m_axi_arsize(xb_s_arsize[1*3 +: 3]),
        .m_axi_arburst(xb_s_arburst[1*2 +: 2]), .m_axi_arqos(xb_s_arqos[1*4 +: 4]),
        .m_axi_arvalid(xb_s_arvalid[1]), .m_axi_arready(xb_s_arready[1]),
        .m_axi_rid(xb_s_rid[1*ID_WIDTH +: ID_WIDTH]), .m_axi_rdata(xb_s_rdata[1*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_rresp(xb_s_rresp[1*2 +: 2]), .m_axi_rlast(xb_s_rlast[1]),
        .m_axi_rvalid(xb_s_rvalid[1]), .m_axi_rready(xb_s_rready[1])
    );

    // M2 (NPU), M3 (Swin), M4 (Display) Interconnect Connections
    axi_master_agent #(.MASTER_ID_VAL(`MASTER_M2_NPU), .DEFAULT_QOS(4'd8)) u_master_m2 (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .cmd_start(dma_m2_start), .cmd_is_write(dma_m2_is_write), .cmd_addr(dma_m2_addr),
        .cmd_len(dma_m2_len), .cmd_size(3'b010), .cmd_burst(`AXI_BURST_INCR), .cmd_qos(4'd8),
        .cmd_wdata(dma_m2_wdata), .cmd_wstrb(4'b1111), .cmd_done(dma_m2_done), .cmd_resp(), .cmd_rdata(dma_m2_rdata),
        .m_axi_awid(xb_s_awid[2*ID_WIDTH +: ID_WIDTH]), .m_axi_awaddr(xb_s_awaddr[2*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_awlen(xb_s_awlen[2*8 +: 8]), .m_axi_awsize(xb_s_awsize[2*3 +: 3]),
        .m_axi_awburst(xb_s_awburst[2*2 +: 2]), .m_axi_awqos(xb_s_awqos[2*4 +: 4]),
        .m_axi_awvalid(xb_s_awvalid[2]), .m_axi_awready(xb_s_awready[2]),
        .m_axi_wdata(xb_s_wdata[2*DATA_WIDTH +: DATA_WIDTH]), .m_axi_wstrb(xb_s_wstrb[2*STRB_WIDTH +: STRB_WIDTH]),
        .m_axi_wlast(xb_s_wlast[2]), .m_axi_wvalid(xb_s_wvalid[2]), .m_axi_wready(xb_s_wready[2]),
        .m_axi_bid(xb_s_bid[2*ID_WIDTH +: ID_WIDTH]), .m_axi_bresp(xb_s_bresp[2*2 +: 2]),
        .m_axi_bvalid(xb_s_bvalid[2]), .m_axi_bready(xb_s_bready[2]),
        .m_axi_arid(xb_s_arid[2*ID_WIDTH +: ID_WIDTH]), .m_axi_araddr(xb_s_araddr[2*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_arlen(xb_s_arlen[2*8 +: 8]), .m_axi_arsize(xb_s_arsize[2*3 +: 3]),
        .m_axi_arburst(xb_s_arburst[2*2 +: 2]), .m_axi_arqos(xb_s_arqos[2*4 +: 4]),
        .m_axi_arvalid(xb_s_arvalid[2]), .m_axi_arready(xb_s_arready[2]),
        .m_axi_rid(xb_s_rid[2*ID_WIDTH +: ID_WIDTH]), .m_axi_rdata(xb_s_rdata[2*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_rresp(xb_s_rresp[2*2 +: 2]), .m_axi_rlast(xb_s_rlast[2]),
        .m_axi_rvalid(xb_s_rvalid[2]), .m_axi_rready(xb_s_rready[2])
    );

    axi_master_agent #(.MASTER_ID_VAL(`MASTER_M3_SWIN), .DEFAULT_QOS(4'd15)) u_master_m3 (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .cmd_start(dma_m3_start), .cmd_is_write(dma_m3_is_write), .cmd_addr(dma_m3_addr),
        .cmd_len(dma_m3_len), .cmd_size(3'b010), .cmd_burst(`AXI_BURST_INCR), .cmd_qos(4'd15),
        .cmd_wdata(dma_m3_wdata), .cmd_wstrb(4'b1111), .cmd_done(dma_m3_done), .cmd_resp(), .cmd_rdata(dma_m3_rdata),
        .m_axi_awid(xb_s_awid[3*ID_WIDTH +: ID_WIDTH]), .m_axi_awaddr(xb_s_awaddr[3*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_awlen(xb_s_awlen[3*8 +: 8]), .m_axi_awsize(xb_s_awsize[3*3 +: 3]),
        .m_axi_awburst(xb_s_awburst[3*2 +: 2]), .m_axi_awqos(xb_s_awqos[3*4 +: 4]),
        .m_axi_awvalid(xb_s_awvalid[3]), .m_axi_awready(xb_s_awready[3]),
        .m_axi_wdata(xb_s_wdata[3*DATA_WIDTH +: DATA_WIDTH]), .m_axi_wstrb(xb_s_wstrb[3*STRB_WIDTH +: STRB_WIDTH]),
        .m_axi_wlast(xb_s_wlast[3]), .m_axi_wvalid(xb_s_wvalid[3]), .m_axi_wready(xb_s_wready[3]),
        .m_axi_bid(xb_s_bid[3*ID_WIDTH +: ID_WIDTH]), .m_axi_bresp(xb_s_bresp[3*2 +: 2]),
        .m_axi_bvalid(xb_s_bvalid[3]), .m_axi_bready(xb_s_bready[3]),
        .m_axi_arid(xb_s_arid[3*ID_WIDTH +: ID_WIDTH]), .m_axi_araddr(xb_s_araddr[3*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_arlen(xb_s_arlen[3*8 +: 8]), .m_axi_arsize(xb_s_arsize[3*3 +: 3]),
        .m_axi_arburst(xb_s_arburst[3*2 +: 2]), .m_axi_arqos(xb_s_arqos[3*4 +: 4]),
        .m_axi_arvalid(xb_s_arvalid[3]), .m_axi_arready(xb_s_arready[3]),
        .m_axi_rid(xb_s_rid[3*ID_WIDTH +: ID_WIDTH]), .m_axi_rdata(xb_s_rdata[3*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_rresp(xb_s_rresp[3*2 +: 2]), .m_axi_rlast(xb_s_rlast[3]),
        .m_axi_rvalid(xb_s_rvalid[3]), .m_axi_rready(xb_s_rready[3])
    );

    axi_master_agent #(.MASTER_ID_VAL(`MASTER_M4_DISPLAY), .DEFAULT_QOS(4'd10)) u_master_m4 (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .cmd_start(1'b0), .cmd_is_write(1'b0), .cmd_addr(32'd0),
        .cmd_len(8'd0), .cmd_size(3'b010), .cmd_burst(`AXI_BURST_INCR), .cmd_qos(4'd10),
        .cmd_wdata(32'd0), .cmd_wstrb(4'b1111), .cmd_done(), .cmd_resp(), .cmd_rdata(),
        .m_axi_awid(xb_s_awid[4*ID_WIDTH +: ID_WIDTH]), .m_axi_awaddr(xb_s_awaddr[4*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_awlen(xb_s_awlen[4*8 +: 8]), .m_axi_awsize(xb_s_awsize[4*3 +: 3]),
        .m_axi_awburst(xb_s_awburst[4*2 +: 2]), .m_axi_awqos(xb_s_awqos[4*4 +: 4]),
        .m_axi_awvalid(xb_s_awvalid[4]), .m_axi_awready(xb_s_awready[4]),
        .m_axi_wdata(xb_s_wdata[4*DATA_WIDTH +: DATA_WIDTH]), .m_axi_wstrb(xb_s_wstrb[4*STRB_WIDTH +: STRB_WIDTH]),
        .m_axi_wlast(xb_s_wlast[4]), .m_axi_wvalid(xb_s_wvalid[4]), .m_axi_wready(xb_s_wready[4]),
        .m_axi_bid(xb_s_bid[4*ID_WIDTH +: ID_WIDTH]), .m_axi_bresp(xb_s_bresp[4*2 +: 2]),
        .m_axi_bvalid(xb_s_bvalid[4]), .m_axi_bready(xb_s_bready[4]),
        .m_axi_arid(xb_s_arid[4*ID_WIDTH +: ID_WIDTH]), .m_axi_araddr(xb_s_araddr[4*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_arlen(xb_s_arlen[4*8 +: 8]), .m_axi_arsize(xb_s_arsize[4*3 +: 3]),
        .m_axi_arburst(xb_s_arburst[4*2 +: 2]), .m_axi_arqos(xb_s_arqos[4*4 +: 4]),
        .m_axi_arvalid(xb_s_arvalid[4]), .m_axi_arready(xb_s_arready[4]),
        .m_axi_rid(xb_s_rid[4*ID_WIDTH +: ID_WIDTH]), .m_axi_rdata(xb_s_rdata[4*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_rresp(xb_s_rresp[4*2 +: 2]), .m_axi_rlast(xb_s_rlast[4]),
        .m_axi_rvalid(xb_s_rvalid[4]), .m_axi_rready(xb_s_rready[4])
    );

    // M5: JTAG Debug Master
    axi_master_agent #(.MASTER_ID_VAL(`MASTER_M5_JTAG), .DEFAULT_QOS(4'd1)) u_master_m5 (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .cmd_start(jtag_cmd_start), .cmd_is_write(jtag_cmd_is_write), .cmd_addr(jtag_cmd_addr),
        .cmd_len(jtag_cmd_len), .cmd_size(3'b010), .cmd_burst(`AXI_BURST_INCR), .cmd_qos(4'd1),
        .cmd_wdata(jtag_cmd_wdata), .cmd_wstrb(4'b1111), .cmd_done(jtag_cmd_done),
        .cmd_resp(), .cmd_rdata(jtag_cmd_rdata),
        .m_axi_awid(xb_s_awid[5*ID_WIDTH +: ID_WIDTH]), .m_axi_awaddr(xb_s_awaddr[5*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_awlen(xb_s_awlen[5*8 +: 8]), .m_axi_awsize(xb_s_awsize[5*3 +: 3]),
        .m_axi_awburst(xb_s_awburst[5*2 +: 2]), .m_axi_awqos(xb_s_awqos[5*4 +: 4]),
        .m_axi_awvalid(xb_s_awvalid[5]), .m_axi_awready(xb_s_awready[5]),
        .m_axi_wdata(xb_s_wdata[5*DATA_WIDTH +: DATA_WIDTH]), .m_axi_wstrb(xb_s_wstrb[5*STRB_WIDTH +: STRB_WIDTH]),
        .m_axi_wlast(xb_s_wlast[5]), .m_axi_wvalid(xb_s_wvalid[5]), .m_axi_wready(xb_s_wready[5]),
        .m_axi_bid(xb_s_bid[5*ID_WIDTH +: ID_WIDTH]), .m_axi_bresp(xb_s_bresp[5*2 +: 2]),
        .m_axi_bvalid(xb_s_bvalid[5]), .m_axi_bready(xb_s_bready[5]),
        .m_axi_arid(xb_s_arid[5*ID_WIDTH +: ID_WIDTH]), .m_axi_araddr(xb_s_araddr[5*ADDR_WIDTH +: ADDR_WIDTH]),
        .m_axi_arlen(xb_s_arlen[5*8 +: 8]), .m_axi_arsize(xb_s_arsize[5*3 +: 3]),
        .m_axi_arburst(xb_s_arburst[5*2 +: 2]), .m_axi_arqos(xb_s_arqos[5*4 +: 4]),
        .m_axi_arvalid(xb_s_arvalid[5]), .m_axi_arready(xb_s_arready[5]),
        .m_axi_rid(xb_s_rid[5*ID_WIDTH +: ID_WIDTH]), .m_axi_rdata(xb_s_rdata[5*DATA_WIDTH +: DATA_WIDTH]),
        .m_axi_rresp(xb_s_rresp[5*2 +: 2]), .m_axi_rlast(xb_s_rlast[5]),
        .m_axi_rvalid(xb_s_rvalid[5]), .m_axi_rready(xb_s_rready[5])
    );

    // AXI Firewall
    axi_firewall #(.ADDR_WIDTH(ADDR_WIDTH), .ID_WIDTH(ID_WIDTH)) u_firewall (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .firewall_en(firewall_en), .production_mode(production_mode),
        .master_id(xb_s_awvalid[5] ? `MASTER_M5_JTAG : `MASTER_M0_RISCV),
        .access_addr(xb_s_awvalid[5] ? xb_s_awaddr[5*ADDR_WIDTH +: ADDR_WIDTH] : xb_s_awaddr[0*ADDR_WIDTH +: ADDR_WIDTH]),
        .is_write(xb_s_awvalid[5] || xb_s_awvalid[0]),
        .access_allowed(), .violation_irq(firewall_violation_irq)
    );

    // 6x6 Interconnect Crossbar
    axi_crossbar_6x6 #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .NUM_MASTERS(6), .NUM_SLAVES(6)
    ) u_crossbar (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .s_axi_awid(xb_s_awid), .s_axi_awaddr(xb_s_awaddr), .s_axi_awlen(xb_s_awlen),
        .s_axi_awsize(xb_s_awsize), .s_axi_awburst(xb_s_awburst), .s_axi_awqos(xb_s_awqos),
        .s_axi_awvalid(xb_s_awvalid), .s_axi_awready(xb_s_awready),
        .s_axi_wdata(xb_s_wdata), .s_axi_wstrb(xb_s_wstrb), .s_axi_wlast(xb_s_wlast),
        .s_axi_wvalid(xb_s_wvalid), .s_axi_wready(xb_s_wready),
        .s_axi_bid(xb_s_bid), .s_axi_bresp(xb_s_bresp), .s_axi_bvalid(xb_s_bvalid),
        .s_axi_bready(xb_s_bready),
        .s_axi_arid(xb_s_arid), .s_axi_araddr(xb_s_araddr), .s_axi_arlen(xb_s_arlen),
        .s_axi_arsize(xb_s_arsize), .s_axi_arburst(xb_s_arburst), .s_axi_arqos(xb_s_arqos),
        .s_axi_arvalid(xb_s_arvalid), .s_axi_arready(xb_s_arready),
        .s_axi_rid(xb_s_rid), .s_axi_rdata(xb_s_rdata), .s_axi_rresp(xb_s_rresp),
        .s_axi_rlast(xb_s_rlast), .s_axi_rvalid(xb_s_rvalid), .s_axi_rready(xb_s_rready),

        .m_axi_awid(xb_m_awid), .m_axi_awaddr(xb_m_awaddr), .m_axi_awlen(xb_m_awlen),
        .m_axi_awsize(xb_m_awsize), .m_axi_awburst(xb_m_awburst),
        .m_axi_awvalid(xb_m_awvalid), .m_axi_awready(xb_m_awready),
        .m_axi_wdata(xb_m_wdata), .m_axi_wstrb(xb_m_wstrb), .m_axi_wlast(xb_m_wlast),
        .m_axi_wvalid(xb_m_wvalid), .m_axi_wready(xb_m_wready),
        .m_axi_bid(xb_m_bid), .m_axi_bresp(xb_m_bresp), .m_axi_bvalid(xb_m_bvalid),
        .m_axi_bready(xb_m_bready),
        .m_axi_arid(xb_m_arid), .m_axi_araddr(xb_m_araddr), .m_axi_arlen(xb_m_arlen),
        .m_axi_arsize(xb_m_arsize), .m_axi_arburst(xb_m_arburst),
        .m_axi_arvalid(xb_m_arvalid), .m_axi_arready(xb_m_arready),
        .m_axi_rid(xb_m_rid), .m_axi_rdata(xb_m_rdata), .m_axi_rresp(xb_m_rresp),
        .m_axi_rlast(xb_m_rlast), .m_axi_rvalid(xb_m_rvalid), .m_axi_rready(xb_m_rready)
    );

    // Slaves S0 - S5
    axi_slave_rom #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .INIT_FILE(BOOT_HEX_FILE)
    ) u_slave_rom (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .s_axi_awid(xb_m_awid[0*ID_WIDTH +: ID_WIDTH]), .s_axi_awaddr(xb_m_awaddr[0*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_awlen(xb_m_awlen[0*8 +: 8]), .s_axi_awsize(xb_m_awsize[0*3 +: 3]),
        .s_axi_awburst(xb_m_awburst[0*2 +: 2]), .s_axi_awvalid(xb_m_awvalid[0]), .s_axi_awready(xb_m_awready[0]),
        .s_axi_wdata(xb_m_wdata[0*DATA_WIDTH +: DATA_WIDTH]), .s_axi_wstrb(xb_m_wstrb[0*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(xb_m_wlast[0]), .s_axi_wvalid(xb_m_wvalid[0]), .s_axi_wready(xb_m_wready[0]),
        .s_axi_bid(xb_m_bid[0*ID_WIDTH +: ID_WIDTH]), .s_axi_bresp(xb_m_bresp[0*2 +: 2]),
        .s_axi_bvalid(xb_m_bvalid[0]), .s_axi_bready(xb_m_bready[0]),
        .s_axi_arid(xb_m_arid[0*ID_WIDTH +: ID_WIDTH]), .s_axi_araddr(xb_m_araddr[0*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_arlen(xb_m_arlen[0*8 +: 8]), .s_axi_arsize(xb_m_arsize[0*3 +: 3]),
        .s_axi_arburst(xb_m_arburst[0*2 +: 2]), .s_axi_arvalid(xb_m_arvalid[0]), .s_axi_arready(xb_m_arready[0]),
        .s_axi_rid(xb_m_rid[0*ID_WIDTH +: ID_WIDTH]), .s_axi_rdata(xb_m_rdata[0*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(xb_m_rresp[0*2 +: 2]), .s_axi_rlast(xb_m_rlast[0]),
        .s_axi_rvalid(xb_m_rvalid[0]), .s_axi_rready(xb_m_rready[0])
    );

    axi_slave_sram #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .INIT_FILE(SRAM_MEM_FILE)
    ) u_slave_sram (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .s_axi_awid(xb_m_awid[1*ID_WIDTH +: ID_WIDTH]), .s_axi_awaddr(xb_m_awaddr[1*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_awlen(xb_m_awlen[1*8 +: 8]), .s_axi_awsize(xb_m_awsize[1*3 +: 3]),
        .s_axi_awburst(xb_m_awburst[1*2 +: 2]), .s_axi_awvalid(xb_m_awvalid[1]), .s_axi_awready(xb_m_awready[1]),
        .s_axi_wdata(xb_m_wdata[1*DATA_WIDTH +: DATA_WIDTH]), .s_axi_wstrb(xb_m_wstrb[1*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(xb_m_wlast[1]), .s_axi_wvalid(xb_m_wvalid[1]), .s_axi_wready(xb_m_wready[1]),
        .s_axi_bid(xb_m_bid[1*ID_WIDTH +: ID_WIDTH]), .s_axi_bresp(xb_m_bresp[1*2 +: 2]),
        .s_axi_bvalid(xb_m_bvalid[1]), .s_axi_bready(xb_m_bready[1]),
        .s_axi_arid(xb_m_arid[1*ID_WIDTH +: ID_WIDTH]), .s_axi_araddr(xb_m_araddr[1*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_arlen(xb_m_arlen[1*8 +: 8]), .s_axi_arsize(xb_m_arsize[1*3 +: 3]),
        .s_axi_arburst(xb_m_arburst[1*2 +: 2]), .s_axi_arvalid(xb_m_arvalid[1]), .s_axi_arready(xb_m_arready[1]),
        .s_axi_rid(xb_m_rid[1*ID_WIDTH +: ID_WIDTH]), .s_axi_rdata(xb_m_rdata[1*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(xb_m_rresp[1*2 +: 2]), .s_axi_rlast(xb_m_rlast[1]),
        .s_axi_rvalid(xb_m_rvalid[1]), .s_axi_rready(xb_m_rready[1])
    );

    axi_slave_scratchpad #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .INIT_FILE(SCRATCHPAD_HEX_FILE)
    ) u_slave_scratchpad (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .s_axi_awid(xb_m_awid[2*ID_WIDTH +: ID_WIDTH]), .s_axi_awaddr(xb_m_awaddr[2*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_awlen(xb_m_awlen[2*8 +: 8]), .s_axi_awsize(xb_m_awsize[2*3 +: 3]),
        .s_axi_awburst(xb_m_awburst[2*2 +: 2]), .s_axi_awvalid(xb_m_awvalid[2]), .s_axi_awready(xb_m_awready[2]),
        .s_axi_wdata(xb_m_wdata[2*DATA_WIDTH +: DATA_WIDTH]), .s_axi_wstrb(xb_m_wstrb[2*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(xb_m_wlast[2]), .s_axi_wvalid(xb_m_wvalid[2]), .s_axi_wready(xb_m_wready[2]),
        .s_axi_bid(xb_m_bid[2*ID_WIDTH +: ID_WIDTH]), .s_axi_bresp(xb_m_bresp[2*2 +: 2]),
        .s_axi_bvalid(xb_m_bvalid[2]), .s_axi_bready(xb_m_bready[2]),
        .s_axi_arid(xb_m_arid[2*ID_WIDTH +: ID_WIDTH]), .s_axi_araddr(xb_m_araddr[2*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_arlen(xb_m_arlen[2*8 +: 8]), .s_axi_arsize(xb_m_arsize[2*3 +: 3]),
        .s_axi_arburst(xb_m_arburst[2*2 +: 2]), .s_axi_arvalid(xb_m_arvalid[2]), .s_axi_arready(xb_m_arready[2]),
        .s_axi_rid(xb_m_rid[2*ID_WIDTH +: ID_WIDTH]), .s_axi_rdata(xb_m_rdata[2*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(xb_m_rresp[2*2 +: 2]), .s_axi_rlast(xb_m_rlast[2]),
        .s_axi_rvalid(xb_m_rvalid[2]), .s_axi_rready(xb_m_rready[2])
    );

    // S3: AXI4-Lite Bridge & CSR Cluster
    wire [ADDR_WIDTH-1:0]  axil_awaddr, axil_araddr;
    wire [2:0]             axil_awprot, axil_arprot;
    wire                   axil_awvalid, axil_awready;
    wire [DATA_WIDTH-1:0]  axil_wdata, axil_rdata;
    wire [STRB_WIDTH-1:0]  axil_wstrb;
    wire                   axil_wvalid, axil_wready;
    wire [1:0]             axil_bresp, axil_rresp;
    wire                   axil_bvalid, axil_bready;
    wire                   axil_arvalid, axil_arready;
    wire                   axil_rvalid, axil_rready;

    axi_to_axilite_bridge u_axilite_bridge (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .s_axi_awid(xb_m_awid[3*ID_WIDTH +: ID_WIDTH]), .s_axi_awaddr(xb_m_awaddr[3*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_awlen(xb_m_awlen[3*8 +: 8]), .s_axi_awsize(xb_m_awsize[3*3 +: 3]),
        .s_axi_awburst(xb_m_awburst[3*2 +: 2]), .s_axi_awvalid(xb_m_awvalid[3]), .s_axi_awready(xb_m_awready[3]),
        .s_axi_wdata(xb_m_wdata[3*DATA_WIDTH +: DATA_WIDTH]), .s_axi_wstrb(xb_m_wstrb[3*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(xb_m_wlast[3]), .s_axi_wvalid(xb_m_wvalid[3]), .s_axi_wready(xb_m_wready[3]),
        .s_axi_bid(xb_m_bid[3*ID_WIDTH +: ID_WIDTH]), .s_axi_bresp(xb_m_bresp[3*2 +: 2]),
        .s_axi_bvalid(xb_m_bvalid[3]), .s_axi_bready(xb_m_bready[3]),
        .s_axi_arid(xb_m_arid[3*ID_WIDTH +: ID_WIDTH]), .s_axi_araddr(xb_m_araddr[3*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_arlen(xb_m_arlen[3*8 +: 8]), .s_axi_arsize(xb_m_arsize[3*3 +: 3]),
        .s_axi_arburst(xb_m_arburst[3*2 +: 2]), .s_axi_arvalid(xb_m_arvalid[3]), .s_axi_arready(xb_m_arready[3]),
        .s_axi_rid(xb_m_rid[3*ID_WIDTH +: ID_WIDTH]), .s_axi_rdata(xb_m_rdata[3*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(xb_m_rresp[3*2 +: 2]), .s_axi_rlast(xb_m_rlast[3]),
        .s_axi_rvalid(xb_m_rvalid[3]), .s_axi_rready(xb_m_rready[3]),

        .m_axil_awaddr(axil_awaddr), .m_axil_awprot(axil_awprot), .m_axil_awvalid(axil_awvalid),
        .m_axil_awready(axil_awready),
        .m_axil_wdata(axil_wdata), .m_axil_wstrb(axil_wstrb), .m_axil_wvalid(axil_wvalid),
        .m_axil_wready(axil_wready),
        .m_axil_bresp(axil_bresp), .m_axil_bvalid(axil_bvalid), .m_axil_bready(axil_bready),
        .m_axil_araddr(axil_araddr), .m_axil_arprot(axil_arprot), .m_axil_arvalid(axil_arvalid),
        .m_axil_arready(axil_arready),
        .m_axil_rdata(axil_rdata), .m_axil_rresp(axil_rresp), .m_axil_rvalid(axil_rvalid),
        .m_axil_rready(axil_rready)
    );

    axilite_csr_cluster u_csr_cluster (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .s_axil_awaddr(axil_awaddr), .s_axil_awprot(axil_awprot), .s_axil_awvalid(axil_awvalid),
        .s_axil_awready(axil_awready),
        .s_axil_wdata(axil_wdata), .s_axil_wstrb(axil_wstrb), .s_axil_wvalid(axil_wvalid),
        .s_axil_wready(axil_wready),
        .s_axil_bresp(axil_bresp), .s_axil_bvalid(axil_bvalid), .s_axil_bready(axil_bready),
        .s_axil_araddr(axil_araddr), .s_axil_arprot(axil_arprot), .s_axil_arvalid(axil_arvalid),
        .s_axil_arready(axil_arready),
        .s_axil_rdata(axil_rdata), .s_axil_rresp(axil_rresp), .s_axil_rvalid(axil_rvalid),
        .s_axil_rready(axil_rready),
        .npu_axil_awaddr(npu_axil_awaddr), .npu_axil_awvalid(npu_axil_awvalid), .npu_axil_awready(npu_axil_awready),
        .npu_axil_wdata(npu_axil_wdata), .npu_axil_wstrb(npu_axil_wstrb), .npu_axil_wvalid(npu_axil_wvalid), .npu_axil_wready(npu_axil_wready),
        .npu_axil_bresp(npu_axil_bresp), .npu_axil_bvalid(npu_axil_bvalid), .npu_axil_bready(npu_axil_bready),
        .npu_axil_araddr(npu_axil_araddr), .npu_axil_arvalid(npu_axil_arvalid), .npu_axil_arready(npu_axil_arready),
        .npu_axil_rdata(npu_axil_rdata), .npu_axil_rresp(npu_axil_rresp), .npu_axil_rvalid(npu_axil_rvalid), .npu_axil_rready(npu_axil_rready),
        .swin_axil_awaddr(swin_axil_awaddr), .swin_axil_awvalid(swin_axil_awvalid), .swin_axil_awready(swin_axil_awready),
        .swin_axil_wdata(swin_axil_wdata), .swin_axil_wstrb(swin_axil_wstrb), .swin_axil_wvalid(swin_axil_wvalid), .swin_axil_wready(swin_axil_wready),
        .swin_axil_bresp(swin_axil_bresp), .swin_axil_bvalid(swin_axil_bvalid), .swin_axil_bready(swin_axil_bready),
        .swin_axil_araddr(swin_axil_araddr), .swin_axil_arvalid(swin_axil_arvalid), .swin_axil_arready(swin_axil_arready),
        .swin_axil_rdata(swin_axil_rdata), .swin_axil_rresp(swin_axil_rresp), .swin_axil_rvalid(swin_axil_rvalid), .swin_axil_rready(swin_axil_rready),
        .threshold_irq(threshold_abnormal_irq),
        .wake_target(threshold_wake_target)
    );

    axi_slave_nvm #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .INIT_FILE(NVM_HEX_FILE)
    ) u_slave_nvm (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .s_axi_awid(xb_m_awid[4*ID_WIDTH +: ID_WIDTH]), .s_axi_awaddr(xb_m_awaddr[4*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_awlen(xb_m_awlen[4*8 +: 8]), .s_axi_awsize(xb_m_awsize[4*3 +: 3]),
        .s_axi_awburst(xb_m_awburst[4*2 +: 2]), .s_axi_awvalid(xb_m_awvalid[4]), .s_axi_awready(xb_m_awready[4]),
        .s_axi_wdata(xb_m_wdata[4*DATA_WIDTH +: DATA_WIDTH]), .s_axi_wstrb(xb_m_wstrb[4*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(xb_m_wlast[4]), .s_axi_wvalid(xb_m_wvalid[4]), .s_axi_wready(xb_m_wready[4]),
        .s_axi_bid(xb_m_bid[4*ID_WIDTH +: ID_WIDTH]), .s_axi_bresp(xb_m_bresp[4*2 +: 2]),
        .s_axi_bvalid(xb_m_bvalid[4]), .s_axi_bready(xb_m_bready[4]),
        .s_axi_arid(xb_m_arid[4*ID_WIDTH +: ID_WIDTH]), .s_axi_araddr(xb_m_araddr[4*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_arlen(xb_m_arlen[4*8 +: 8]), .s_axi_arsize(xb_m_arsize[4*3 +: 3]),
        .s_axi_arburst(xb_m_arburst[4*2 +: 2]), .s_axi_arvalid(xb_m_arvalid[4]), .s_axi_arready(xb_m_arready[4]),
        .s_axi_rid(xb_m_rid[4*ID_WIDTH +: ID_WIDTH]), .s_axi_rdata(xb_m_rdata[4*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(xb_m_rresp[4*2 +: 2]), .s_axi_rlast(xb_m_rlast[4]),
        .s_axi_rvalid(xb_m_rvalid[4]), .s_axi_rready(xb_m_rready[4])
    );

    axi_slave_lpddr #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .INIT_FILE(LPDDR_HEX_FILE)
    ) u_slave_lpddr (
        .aclk(clk_ao), .aresetn(rst_ao_n),
        .s_axi_awid(xb_m_awid[5*ID_WIDTH +: ID_WIDTH]), .s_axi_awaddr(xb_m_awaddr[5*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_awlen(xb_m_awlen[5*8 +: 8]), .s_axi_awsize(xb_m_awsize[5*3 +: 3]),
        .s_axi_awburst(xb_m_awburst[5*2 +: 2]), .s_axi_awvalid(xb_m_awvalid[5]), .s_axi_awready(xb_m_awready[5]),
        .s_axi_wdata(xb_m_wdata[5*DATA_WIDTH +: DATA_WIDTH]), .s_axi_wstrb(xb_m_wstrb[5*STRB_WIDTH +: STRB_WIDTH]),
        .s_axi_wlast(xb_m_wlast[5]), .s_axi_wvalid(xb_m_wvalid[5]), .s_axi_wready(xb_m_wready[5]),
        .s_axi_bid(xb_m_bid[5*ID_WIDTH +: ID_WIDTH]), .s_axi_bresp(xb_m_bresp[5*2 +: 2]),
        .s_axi_bvalid(xb_m_bvalid[5]), .s_axi_bready(xb_m_bready[5]),
        .s_axi_arid(xb_m_arid[5*ID_WIDTH +: ID_WIDTH]), .s_axi_araddr(xb_m_araddr[5*ADDR_WIDTH +: ADDR_WIDTH]),
        .s_axi_arlen(xb_m_arlen[5*8 +: 8]), .s_axi_arsize(xb_m_arsize[5*3 +: 3]),
        .s_axi_arburst(xb_m_arburst[5*2 +: 2]), .s_axi_arvalid(xb_m_arvalid[5]), .s_axi_arready(xb_m_arready[5]),
        .s_axi_rid(xb_m_rid[5*ID_WIDTH +: ID_WIDTH]), .s_axi_rdata(xb_m_rdata[5*DATA_WIDTH +: DATA_WIDTH]),
        .s_axi_rresp(xb_m_rresp[5*2 +: 2]), .s_axi_rlast(xb_m_rlast[5]),
        .s_axi_rvalid(xb_m_rvalid[5]), .s_axi_rready(xb_m_rready[5])
    );

endmodule
