// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Stream Monitor
// Captures streaming samples from the bus and writes to analysis port
// =============================================================================

`ifndef AXIS_MONITOR_SV
`define AXIS_MONITOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../seq_item/axis_seq_item.sv"

class axis_monitor #(parameter DATA_WIDTH = 32) extends uvm_monitor;
    `uvm_component_param_utils(axis_monitor #(DATA_WIDTH))

    virtual interface axis_if #(DATA_WIDTH) vif;
    uvm_analysis_port #(axis_transaction #(DATA_WIDTH)) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual interface axis_if #(DATA_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXIS_MON", "Virtual interface not found in config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        axis_transaction #(DATA_WIDTH) item;
        forever begin
            @(posedge vif.clk);
            if (vif.tvalid && vif.tready) begin
                item = axis_transaction #(DATA_WIDTH)::type_id::create("item");
                item.tdata = vif.tdata;
                item.tid   = vif.tid;
                item.tuser = vif.tuser;
                item.tlast = vif.tlast;
                ap.write(item);
            end
        end
    endtask
endclass

`endif // AXIS_MONITOR_SV
