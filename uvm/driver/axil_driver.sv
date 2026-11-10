// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Lite Driver
// Drives single-beat CSR register read/write transactions (0x4000_0000 - 0x4009_0000)
// =============================================================================

`ifndef AXIL_DRIVER_SV
`define AXIL_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../seq_item/axil_seq_item.sv"

class axil_driver extends uvm_driver #(axil_transaction);
    `uvm_component_utils(axil_driver)

    virtual interface axil_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual interface axil_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXIL_DRV", "Virtual interface not found in config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        axil_transaction req;
        vif.awvalid <= 1'b0;
        vif.wvalid  <= 1'b0;
        vif.bready  <= 1'b1;
        vif.arvalid <= 1'b0;
        vif.rready  <= 1'b1;

        forever begin
            seq_item_port.get_next_item(req);
            if (req.dir == axil_transaction::AXIL_WRITE) begin
                // Write Address & Data
                @(posedge vif.clk);
                vif.awaddr  <= req.addr;
                vif.awvalid <= 1'b1;
                vif.wdata   <= req.data;
                vif.wstrb   <= req.strb;
                vif.wvalid  <= 1'b1;

                do begin
                    @(posedge vif.clk);
                end while (!vif.awready || !vif.wready);

                vif.awvalid <= 1'b0;
                vif.wvalid  <= 1'b0;

                do begin
                    @(posedge vif.clk);
                end while (!vif.bvalid);
                req.resp = vif.bresp;
            end else begin
                // Read Address
                @(posedge vif.clk);
                vif.araddr  <= req.addr;
                vif.arvalid <= 1'b1;

                do begin
                    @(posedge vif.clk);
                end while (!vif.arready);
                vif.arvalid <= 1'b0;

                do begin
                    @(posedge vif.clk);
                end while (!vif.rvalid);
                req.data = vif.rdata;
                req.resp = vif.rresp;
            end
            seq_item_port.item_done();
        end
    endtask
endclass

`endif // AXIL_DRIVER_SV
