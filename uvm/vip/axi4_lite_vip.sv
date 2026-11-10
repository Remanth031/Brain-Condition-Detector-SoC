// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Lite Verification IP (VIP)
// Standard UVM Verification Component for AMBA AXI4-Lite CSR Control Plane
// Supports: Single-beat Register Reads & Writes across 0x4000_0000 - 0x4009_0000
// =============================================================================

`ifndef AXI4_LITE_VIP_SV
`define AXI4_LITE_VIP_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

// -----------------------------------------------------------------------------
// 1. AXI4-Lite Transaction Item
// -----------------------------------------------------------------------------
class axil_transaction extends uvm_sequence_item;
    typedef enum bit { AXIL_READ = 1'b0, AXIL_WRITE = 1'b1 } axil_dir_e;

    rand axil_dir_e dir;
    rand bit [31:0] addr;
    rand bit [31:0] data;
    rand bit [3:0]  strb;
    bit [1:0]       resp;

    constraint c_align { addr[1:0] == 2'b00; } // 32-bit aligned
    constraint c_strb  { strb == 4'b1111; }

    `uvm_object_utils_begin(axil_transaction)
        `uvm_field_enum(axil_dir_e, dir, UVM_ALL_ON)
        `uvm_field_int(addr, UVM_ALL_ON)
        `uvm_field_int(data, UVM_ALL_ON)
        `uvm_field_int(strb, UVM_ALL_ON)
        `uvm_field_int(resp, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axil_transaction");
        super.new(name);
    endfunction
endclass

// -----------------------------------------------------------------------------
// 2. AXI4-Lite Driver
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// 3. AXI4-Lite Monitor & Agent
// -----------------------------------------------------------------------------
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

class axil_agent extends uvm_agent;
    `uvm_component_utils(axil_agent)

    uvm_sequencer #(axil_transaction) sqr;
    axil_driver                       drv;
    axil_monitor                      mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = axil_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = uvm_sequencer #(axil_transaction)::type_id::create("sqr", this);
            drv = axil_driver::type_id::create("drv", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction
endclass

`endif // AXI4_LITE_VIP_SV
