// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Lite Monitor
// Monitors both CSR read responses and write acknowledgments for UVM RAL checking
// =============================================================================

`ifndef AXIL_MONITOR_SV
`define AXIL_MONITOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../seq_item/axil_seq_item.sv"

class axil_monitor extends uvm_monitor;
    `uvm_component_utils(axil_monitor)

    virtual interface axil_if vif;
    uvm_analysis_port #(axil_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual interface axil_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXIL_MON", "Virtual interface not found in config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        axil_transaction item;
        forever begin
            @(posedge vif.clk);
            if (vif.rvalid && vif.rready) begin
                item = axil_transaction::type_id::create("item_rd");
                item.dir  = axil_transaction::AXIL_READ;
                item.addr = vif.araddr;
                item.data = vif.rdata;
                item.resp = vif.rresp;
                ap.write(item);
            end
            if (vif.bvalid && vif.bready) begin
                item = axil_transaction::type_id::create("item_wr");
                item.dir  = axil_transaction::AXIL_WRITE;
                item.addr = vif.awaddr;
                item.data = vif.wdata;
                item.resp = vif.bresp;
                ap.write(item);
            end
        end
    endtask
endclass

`endif // AXIL_MONITOR_SV
