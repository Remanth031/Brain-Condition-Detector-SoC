// =============================================================================
// Brain Condition Detector (BCD) SoC - Biopotential ADC Sensor Driver
// Drives 32-channel scalp EEG samples on the 4 MHz ADC clock domain
// =============================================================================

`ifndef ADC_BIOPOTENTIAL_DRIVER_SV
`define ADC_BIOPOTENTIAL_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../seq_item/adc_seq_item.sv"

class adc_biopotential_driver extends uvm_driver #(eeg_sample_item);
    `uvm_component_utils(adc_biopotential_driver)

    virtual interface adc_sensor_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual interface adc_sensor_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("ADC_DRV", "Virtual interface not found in config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        eeg_sample_item req;
        vif.sample_valid <= 1'b0;
        vif.channel_id   <= '0;
        vif.raw_data     <= '0;
        vif.lead_off     <= 1'b0;
        vif.saturation   <= 1'b0;

        forever begin
            seq_item_port.get_next_item(req);
            @(posedge vif.clk_adc);
            vif.sample_valid <= 1'b1;
            vif.channel_id   <= req.channel_id;
            vif.raw_data     <= req.sample;
            vif.lead_off     <= req.lead_off;
            vif.saturation   <= req.saturation;

            @(posedge vif.clk_adc);
            vif.sample_valid <= 1'b0;
            seq_item_port.item_done();
        end
    endtask
endclass

`endif // ADC_BIOPOTENTIAL_DRIVER_SV
