// =============================================================================
// Brain Condition Detector (BCD) SoC - UVM Virtual Sequencer
// Aggregates sequencer handles across all Verification IPs:
// - AXI4-Stream Sequencer (DSP & Sample fabric)
// - AXI4-Full Sequencer (Crossbar memory bursts)
// - AXI4-Lite Sequencer (CSR register programming)
// - Biopotential ADC Sensor Sequencer (32-ch EEG ingestion)
// =============================================================================

`ifndef BCD_SOC_VIRTUAL_SEQUENCER_SV
`define BCD_SOC_VIRTUAL_SEQUENCER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../vip/axi4_stream_vip.sv"
`include "../vip/axi4_full_vip.sv"
`include "../vip/axi4_lite_vip.sv"
`include "../vip/adc_biopotential_vip.sv"

class bcd_soc_virtual_sequencer extends uvm_sequencer;
    `uvm_component_utils(bcd_soc_virtual_sequencer)

    uvm_sequencer #(axis_transaction #(32)) axis_sqr;
    uvm_sequencer #(axi4_transaction)       axi4_sqr;
    uvm_sequencer #(axil_transaction)       axil_sqr;
    uvm_sequencer #(eeg_sample_item)        adc_sqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

`endif // BCD_SOC_VIRTUAL_SEQUENCER_SV
