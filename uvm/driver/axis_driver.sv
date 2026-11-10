// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Stream Driver
// Drives AXI4-Stream master transactions onto the pin-level interface
// =============================================================================

`ifndef AXIS_DRIVER_SV
`define AXIS_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../seq_item/axis_seq_item.sv"

class axis_driver #(parameter DATA_WIDTH = 32) extends uvm_driver #(axis_transaction #(DATA_WIDTH));
    `uvm_component_param_utils(axis_driver #(DATA_WIDTH))

    virtual interface axis_if #(DATA_WIDTH) vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual interface axis_if #(DATA_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXIS_DRV", "Virtual interface not found in config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        axis_transaction #(DATA_WIDTH) req;
        vif.tvalid <= 1'b0;
        vif.tdata  <= '0;
        vif.tlast  <= 1'b0;
        vif.tid    <= '0;
        vif.tuser  <= '0;

        forever begin
            seq_item_port.get_next_item(req);
            repeat (req.delay) @(posedge vif.clk);

            @(posedge vif.clk);
            vif.tvalid <= 1'b1;
            vif.tdata  <= req.tdata;
            vif.tid    <= req.tid;
            vif.tuser  <= req.tuser;
            vif.tlast  <= req.tlast;

            do begin
                @(posedge vif.clk);
            end while (!vif.tready);

            vif.tvalid <= 1'b0;
            seq_item_port.item_done();
        end
    endtask
endclass

`endif // AXIS_DRIVER_SV
