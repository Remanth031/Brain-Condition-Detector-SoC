// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Stream Verification IP (VIP)
// Standard UVM Verification Component for AMBA AXI4-Stream Protocol
// Includes: Transaction Item, Driver, Monitor, Sequencer, Agent
// Supports: TDATA (24/32-bit), TID (channel 0-31), TUSER (lead-off/sat), TLAST
// =============================================================================

`ifndef AXI4_STREAM_VIP_SV
`define AXI4_STREAM_VIP_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

// -----------------------------------------------------------------------------
// 1. AXI4-Stream Transaction Sequence Item
// -----------------------------------------------------------------------------
class axis_transaction #(parameter DATA_WIDTH = 32) extends uvm_sequence_item;
    rand bit [DATA_WIDTH-1:0] tdata;
    rand bit [4:0]            tid;      // Channel ID (0 to 31)
    rand bit [1:0]            tuser;    // Bit 0: Lead-off, Bit 1: Saturation
    rand bit                  tlast;    // End of frame / window
    rand int unsigned         delay;    // Inter-beat cycle delay

    constraint c_delay { delay inside {[0:10]}; }
    constraint c_tid   { tid inside {[0:31]}; }

    `uvm_object_utils_begin(axis_transaction)
        `uvm_field_int(tdata, UVM_ALL_ON)
        `uvm_field_int(tid,   UVM_ALL_ON)
        `uvm_field_int(tuser, UVM_ALL_ON)
        `uvm_field_int(tlast, UVM_ALL_ON)
        `uvm_field_int(delay, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axis_transaction");
        super.new(name);
    endfunction
endclass

// -----------------------------------------------------------------------------
// 2. AXI4-Stream Driver
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// 3. AXI4-Stream Monitor
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// 4. AXI4-Stream Agent
// -----------------------------------------------------------------------------
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

`endif // AXI4_STREAM_VIP_SV
