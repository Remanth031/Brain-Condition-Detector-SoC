// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Full Agent
// Encapsulates Sequencer, Driver, and Monitor
// =============================================================================

`ifndef AXI4_AGENT_SV
`define AXI4_AGENT_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../seq_item/axi4_seq_item.sv"
`include "../driver/axi4_driver.sv"
`include "../monitor/axi4_monitor.sv"

class axi4_agent extends uvm_agent;
    `uvm_component_utils(axi4_agent)

    uvm_sequencer #(axi4_transaction) sqr;
    axi4_driver                       drv;
    axi4_monitor                      mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = axi4_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = uvm_sequencer #(axi4_transaction)::type_id::create("sqr", this);
            drv = axi4_driver::type_id::create("drv", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction
endclass

`endif // AXI4_AGENT_SV
