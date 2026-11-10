// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Full Master Driver
// Drives 5-channel burst transactions (AW, W, B, AR, R) on the crossbar fabric
// =============================================================================

`ifndef AXI4_DRIVER_SV
`define AXI4_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../seq_item/axi4_seq_item.sv"

class axi4_driver extends uvm_driver #(axi4_transaction);
    `uvm_component_utils(axi4_driver)

    virtual interface axi4_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual interface axi4_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXI4_DRV", "Virtual interface not found in config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        axi4_transaction req;
        vif.awvalid <= 1'b0;
        vif.wvalid  <= 1'b0;
        vif.bready  <= 1'b1;
        vif.arvalid <= 1'b0;
        vif.rready  <= 1'b1;

        forever begin
            seq_item_port.get_next_item(req);

            if (req.trans_type == axi4_transaction::AXI_WRITE) begin
                drive_write(req);
            end else begin
                drive_read(req);
            end

            seq_item_port.item_done();
        end
    endtask

    virtual task drive_write(axi4_transaction req);
        // 1. Address Write Channel (AW)
        @(posedge vif.clk);
        vif.awid    <= req.id;
        vif.awaddr  <= req.addr;
        vif.awlen   <= req.len;
        vif.awsize  <= req.size;
        vif.awburst <= req.burst;
        vif.awqos   <= req.qos;
        vif.awvalid <= 1'b1;

        do begin
            @(posedge vif.clk);
        end while (!vif.awready);
        vif.awvalid <= 1'b0;

        // 2. Write Data Channel (W)
        for (int i = 0; i <= req.len; i++) begin
            vif.wdata  <= req.data[i];
            vif.wstrb  <= req.strb[i];
            vif.wlast  <= (i == req.len);
            vif.wvalid <= 1'b1;
            do begin
                @(posedge vif.clk);
            end while (!vif.wready);
        end
        vif.wvalid <= 1'b0;
        vif.wlast  <= 1'b0;

        // 3. Write Response Channel (B)
        vif.bready <= 1'b1;
        do begin
            @(posedge vif.clk);
        end while (!vif.bvalid);
        req.resp = vif.bresp;
    endtask

    virtual task drive_read(axi4_transaction req);
        // 1. Address Read Channel (AR)
        @(posedge vif.clk);
        vif.arid    <= req.id;
        vif.araddr  <= req.addr;
        vif.arlen   <= req.len;
        vif.arsize  <= req.size;
        vif.arburst <= req.burst;
        vif.arqos   <= req.qos;
        vif.arvalid <= 1'b1;

        do begin
            @(posedge vif.clk);
        end while (!vif.arready);
        vif.arvalid <= 1'b0;

        // 2. Read Data Channel (R)
        req.data = new[req.len + 1];
        for (int i = 0; i <= req.len; i++) begin
            do begin
                @(posedge vif.clk);
            end while (!vif.rvalid);
            req.data[i] = vif.rdata;
            req.resp    = vif.rresp;
        end
    endtask
endclass

`endif // AXI4_DRIVER_SV
