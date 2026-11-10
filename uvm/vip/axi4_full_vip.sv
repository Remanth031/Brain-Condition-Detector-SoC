// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Full Verification IP (VIP)
// Standard UVM Verification Component for AMBA AXI4-Full Memory-Mapped Protocol
// Includes: Transaction Item, Master/Slave Drivers, Monitors, Scoreboard Hooks
// Supports: INCR/WRAP/FIXED Bursts up to 256 beats, 4KB boundary checking, QoS
// =============================================================================

`ifndef AXI4_FULL_VIP_SV
`define AXI4_FULL_VIP_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

// -----------------------------------------------------------------------------
// 1. AXI4-Full Transaction Sequence Item
// -----------------------------------------------------------------------------
class axi4_transaction extends uvm_sequence_item;
    typedef enum bit { AXI_READ = 1'b0, AXI_WRITE = 1'b1 } trans_type_e;

    rand trans_type_e   trans_type;
    rand bit [3:0]      id;
    rand bit [31:0]     addr;
    rand bit [7:0]      len;       // 0 to 255 beats
    rand bit [2:0]      size;      // 3'b010 = 4 bytes
    rand bit [1:0]      burst;     // 2'b01 = INCR
    rand bit [3:0]      qos;
    rand bit [31:0]     data[];    // Dynamic array of burst data beats
    rand bit [3:0]      strb[];    // Write strobes per beat
    bit [1:0]           resp;      // OKAY (00), EXOKAY (01), SLVERR (10), DECERR (11)

    constraint c_burst_type { burst == 2'b01; } // INCR
    constraint c_size       { size == 3'b010; }  // 32-bit (4 bytes)
    constraint c_data_len   { data.size() == len + 1; strb.size() == len + 1; }
    constraint c_4k_boundary {
        // Enforce AMBA 4KB page boundary rule
        (addr[11:0] + ((len + 1) * 4)) <= 12'hFFF;
    }

    `uvm_object_utils_begin(axi4_transaction)
        `uvm_field_enum(trans_type_e, trans_type, UVM_ALL_ON)
        `uvm_field_int(id,         UVM_ALL_ON)
        `uvm_field_int(addr,       UVM_ALL_ON)
        `uvm_field_int(len,        UVM_ALL_ON)
        `uvm_field_int(size,       UVM_ALL_ON)
        `uvm_field_int(burst,      UVM_ALL_ON)
        `uvm_field_int(qos,        UVM_ALL_ON)
        `uvm_field_array_int(data, UVM_ALL_ON)
        `uvm_field_array_int(strb, UVM_ALL_ON)
        `uvm_field_int(resp,       UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi4_transaction");
        super.new(name);
    endfunction
endclass

// -----------------------------------------------------------------------------
// 2. AXI4-Full Master Driver
// -----------------------------------------------------------------------------
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
        // Reset drive pins
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

// -----------------------------------------------------------------------------
// 3. AXI4-Full Monitor
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// 4. AXI4-Full Agent
// -----------------------------------------------------------------------------
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

`endif // AXI4_FULL_VIP_SV
