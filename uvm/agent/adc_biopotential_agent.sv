// =============================================================================
// Brain Condition Detector (BCD) SoC - Biopotential ADC Agent
// Encapsulates Sequencer, Driver, and Monitor
// =============================================================================

`ifndef ADC_BIOPOTENTIAL_AGENT_SV
`define ADC_BIOPOTENTIAL_AGENT_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../seq_item/adc_seq_item.sv"
`include "../driver/adc_biopotential_driver.sv"
`include "../monitor/adc_biopotential_monitor.sv"

class adc_biopotential_agent extends uvm_agent;
    `uvm_component_utils(adc_biopotential_agent)

    uvm_sequencer #(eeg_sample_item) sqr;
    adc_biopotential_driver          drv;
    adc_biopotential_monitor         mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = adc_biopotential_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = uvm_sequencer #(eeg_sample_item)::type_id::create("sqr", this);
            drv = adc_biopotential_driver::type_id::create("drv", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction
endclass

`endif // ADC_BIOPOTENTIAL_AGENT_SV
