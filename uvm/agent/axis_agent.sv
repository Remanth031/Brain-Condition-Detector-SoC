// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Stream Agent
// Encapsulates Sequencer, Driver, and Monitor
// =============================================================================

`ifndef AXIS_AGENT_SV
`define AXIS_AGENT_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../seq_item/axis_seq_item.sv"
`include "../driver/axis_driver.sv"
`include "../monitor/axis_monitor.sv"

class axis_agent #(parameter DATA_WIDTH = 32) extends uvm_agent;
    `uvm_component_param_utils(axis_agent #(DATA_WIDTH))

    uvm_sequencer #(axis_transaction #(DATA_WIDTH)) sqr;
    axis_driver   #(DATA_WIDTH)                    drv;
    axis_monitor  #(DATA_WIDTH)                    mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = axis_monitor #(DATA_WIDTH)::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = uvm_sequencer #(axis_transaction #(DATA_WIDTH))::type_id::create("sqr", this);
            drv = axis_driver   #(DATA_WIDTH)::type_id::create("drv", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction
endclass

`endif // AXIS_AGENT_SV
