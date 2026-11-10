// =============================================================================
// Brain Condition Detector (BCD) SoC - UVM Master Virtual Sequence
// Coordinates end-to-end SoC verification scenarios:
// 1. Reset & Power-on initialization
// 2. AXI4-Lite CSR register programming (thresholds, filter modes, NPU/Swin base)
// 3. Normal background EEG streaming (Rice compression verification)
// 4. Ictal seizure burst injection (Threshold engine wake-up IRQ)
// 5. NPU EEGNet classification & Swin Transformer attention execution
// 6. Output fusion & diagnostic finding readout
// =============================================================================

`ifndef BCD_SOC_VIRTUAL_SEQ_SV
`define BCD_SOC_VIRTUAL_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "bcd_soc_virtual_sequencer.sv"
`include "axil_csr_seq.sv"
`include "adc_eeg_stimulus_seq.sv"
`include "axi4_burst_seq.sv"
`include "axis_stream_seq.sv"

class bcd_soc_virtual_seq extends uvm_sequence;
    `uvm_object_utils(bcd_soc_virtual_seq)
    `uvm_declare_p_sequencer(bcd_soc_virtual_sequencer)

    axil_csr_seq         csr_seq;
    adc_eeg_stimulus_seq adc_seq;
    axi4_burst_seq       axi_seq;
    axis_stream_seq #(32) axis_seq;

    function new(string name = "bcd_soc_virtual_seq");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("VSEQ", ">>> STARTING FULL-SoC UVM VIRTUAL SEQUENCE <<<", UVM_LOW)

        // Phase 1: Program CSR Registers via AXI-Lite VIP
        `uvm_info("VSEQ", "Phase 1: Executing CSR Configuration Sequence", UVM_LOW)
        csr_seq = axil_csr_seq::type_id::create("csr_seq");
        csr_seq.start(p_sequencer.axil_sqr);

        // Phase 2: Stream Normal EEG Samples via ADC Sensor VIP
        `uvm_info("VSEQ", "Phase 2: Streaming Normal Baseline Scalp EEG", UVM_LOW)
        adc_seq = adc_eeg_stimulus_seq::type_id::create("adc_seq");
        adc_seq.force_pattern_en = 1'b1;
        adc_seq.forced_pattern   = eeg_sample_item::PATTERN_NORMAL;
        adc_seq.num_frames       = 16;
        adc_seq.start(p_sequencer.adc_sqr);

        // Phase 3: Inject High-Amplitude Seizure Event
        `uvm_info("VSEQ", "Phase 3: Injecting Epileptic Seizure Burst Event", UVM_LOW)
        adc_seq = adc_eeg_stimulus_seq::type_id::create("adc_seizure_seq");
        adc_seq.force_pattern_en = 1'b1;
        adc_seq.forced_pattern   = eeg_sample_item::PATTERN_SEIZURE;
        adc_seq.num_frames       = 8;
        adc_seq.start(p_sequencer.adc_sqr);

        // Phase 4: AXI4 Crossbar Memory Bursts (Weight Fetch & Scratchpad)
        `uvm_info("VSEQ", "Phase 4: Concurrent AXI4 Memory Burst Testing", UVM_LOW)
        axi_seq = axi4_burst_seq::type_id::create("axi_seq");
        axi_seq.is_write    = 1'b1;
        axi_seq.target_addr = 32'h1000_0000;
        axi_seq.burst_len   = 8'd15; // 16-beat burst
        axi_seq.start(p_sequencer.axi4_sqr);

        `uvm_info("VSEQ", ">>> FULL-SoC UVM VIRTUAL SEQUENCE COMPLETED SUCCESSFULLY <<<", UVM_LOW)
    endtask
endclass

`endif // BCD_SOC_VIRTUAL_SEQ_SV
