// =============================================================================
// Brain Condition Detector (BCD) SoC - Biopotential ADC Monitor
// Captures multi-channel scalp EEG samples, lead-off flags, and saturation states
// =============================================================================

`ifndef ADC_BIOPOTENTIAL_MONITOR_SV
`define ADC_BIOPOTENTIAL_MONITOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../seq_item/adc_seq_item.sv"

class adc_biopotential_monitor extends uvm_monitor;
    `uvm_component_utils(adc_biopotential_monitor)

    virtual interface adc_sensor_if vif;
    uvm_analysis_port #(eeg_sample_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual interface adc_sensor_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("ADC_MON", "Virtual interface not found in config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        eeg_sample_item item;
        forever begin
            @(posedge vif.clk_adc);
            if (vif.sample_valid) begin
                item = eeg_sample_item::type_id::create("item");
                item.channel_id = vif.channel_id;
                item.sample     = vif.raw_data;
                item.lead_off   = vif.lead_off;
                item.saturation = vif.saturation;
                ap.write(item);
            end
        end
    endtask
endclass

`endif // ADC_BIOPOTENTIAL_MONITOR_SV
