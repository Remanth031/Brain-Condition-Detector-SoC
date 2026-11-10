// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Full Monitor
// Concurrently captures Write response completions and Read data bursts
// =============================================================================

`ifndef AXI4_MONITOR_SV
`define AXI4_MONITOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../seq_item/axi4_seq_item.sv"

class axi4_monitor extends uvm_monitor;
    `uvm_component_utils(axi4_monitor)

    virtual interface axi4_if vif;
    uvm_analysis_port #(axi4_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual interface axi4_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXI4_MON", "Virtual interface not found in config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        axi4_transaction item;
        forever begin
            @(posedge vif.clk);
            // Detect Write Response Completion
            if (vif.bvalid && vif.bready) begin
                item = axi4_transaction::type_id::create("item_wr");
                item.trans_type = axi4_transaction::AXI_WRITE;
                item.id   = vif.bid;
                item.resp = vif.bresp;
                ap.write(item);
            end

            // Detect Read Data Completion
            if (vif.rvalid && vif.rready && vif.rlast) begin
                item = axi4_transaction::type_id::create("item_rd");
                item.trans_type = axi4_transaction::AXI_READ;
                item.id   = vif.rid;
                item.resp = vif.rresp;
                ap.write(item);
            end
        end
    endtask
endclass

`endif // AXI4_MONITOR_SV
