// =============================================================================
// Brain Condition Detector (BCD) SoC - Biopotential ADC Sensor Verification IP (VIP)
// Standard UVM Verification Component for Multi-Channel Scalp EEG Simulation
// Includes: eeg_sample_item, adc_biopotential_sequencer, adc_biopotential_driver,
//           adc_biopotential_monitor, adc_biopotential_agent
// Simulates: 32 Channels, 24-bit delta-sigma, lead-off detection, electrode pop,
// normal rhythm (alpha/beta), and ictal seizure spike-and-wave discharges
// =============================================================================

`ifndef ADC_BIOPOTENTIAL_VIP_SV
`define ADC_BIOPOTENTIAL_VIP_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

// -----------------------------------------------------------------------------
// 1. EEG Sample Sequence Item
// -----------------------------------------------------------------------------
class eeg_sample_item extends uvm_sequence_item;
    typedef enum { PATTERN_NORMAL, PATTERN_SEIZURE, PATTERN_SPINDLE, PATTERN_LEAD_OFF, PATTERN_SATURATION } pattern_e;

    rand pattern_e pattern;
    rand bit [4:0] channel_id;      // 0 to 31
    rand bit signed [23:0] sample;  // 24-bit biopotential data
    bit lead_off;
    bit saturation;

    constraint c_pattern {
        pattern dist {
            PATTERN_NORMAL     := 60,
            PATTERN_SEIZURE    := 20,
            PATTERN_SPINDLE    := 10,
            PATTERN_LEAD_OFF   := 5,
            PATTERN_SATURATION := 5
        };
    }

    `uvm_object_utils_begin(eeg_sample_item)
        `uvm_field_enum(pattern_e, pattern, UVM_ALL_ON)
        `uvm_field_int(channel_id, UVM_ALL_ON)
        `uvm_field_int(sample,     UVM_ALL_ON)
        `uvm_field_int(lead_off,   UVM_ALL_ON)
        `uvm_field_int(saturation, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "eeg_sample_item");
        super.new(name);
    endfunction

    function void post_randomize();
        case (pattern)
            PATTERN_NORMAL: begin
                sample = $urandom_range(24'h00_0800, 24'h00_1800);
                lead_off = 1'b0;
                saturation = 1'b0;
            end
            PATTERN_SEIZURE: begin
                // Large amplitude spike burst (>3x baseline)
                sample = $urandom_range(24'h70_0000, 24'h7F_0000);
                lead_off = 1'b0;
                saturation = 1'b0;
            end
            PATTERN_SPINDLE: begin
                // 11-16 Hz sigma rhythm
                sample = $urandom_range(24'h00_2000, 24'h00_4000);
                lead_off = 1'b0;
                saturation = 1'b0;
            end
            PATTERN_LEAD_OFF: begin
                sample = 24'h00_0000;
                lead_off = 1'b1;
                saturation = 1'b0;
            end
            PATTERN_SATURATION: begin
                sample = 24'h7F_FFFF; // Rail positive
                lead_off = 1'b0;
                saturation = 1'b1;
            end
        endcase
    endfunction
endclass

// -----------------------------------------------------------------------------
// 2. Biopotential ADC Driver
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// 3. Biopotential ADC Monitor
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// 4. Biopotential ADC Agent
// -----------------------------------------------------------------------------
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

`endif // ADC_BIOPOTENTIAL_VIP_SV
