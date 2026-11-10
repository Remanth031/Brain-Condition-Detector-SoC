// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Lite CSR Sequences
// Programs threshold registers, filter modes, NPU weight pointers, Swin parameters
// =============================================================================

`ifndef AXIL_CSR_SEQ_SV
`define AXIL_CSR_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../vip/axi4_lite_vip.sv"

class axil_csr_seq extends uvm_sequence #(axil_transaction);
    `uvm_object_utils(axil_csr_seq)

    function new(string name = "axil_csr_seq");
        super.new(name);
    endfunction

    virtual task write_reg(bit [31:0] addr, bit [31:0] data);
        axil_transaction req;
        req = axil_transaction::type_id::create("req_wr");
        start_item(req);
        req.dir  = axil_transaction::AXIL_WRITE;
        req.addr = addr;
        req.data = data;
        req.strb = 4'b1111;
        finish_item(req);
    endtask

    virtual task read_reg(bit [31:0] addr, output bit [31:0] data);
        axil_transaction req;
        req = axil_transaction::type_id::create("req_rd");
        start_item(req);
        req.dir  = axil_transaction::AXIL_READ;
        req.addr = addr;
        finish_item(req);
        data = req.data;
    endtask

    virtual task body();
        bit [31:0] rdata;
        `uvm_info("CSR_SEQ", "Starting CSR register configuration sequence", UVM_LOW)

        // 1. Configure Threshold Engine Line-Length (0x4002_000C)
        write_reg(32'h4002_000C, 32'h0000_0028);
        read_reg(32'h4002_000C, rdata);

        // 2. Configure Band-Power Ratio (0x4002_0010)
        write_reg(32'h4002_0010, 32'h0000_0064);

        // 3. Configure N-of-M Voting (0x4002_0018): 3 of 5 channels
        write_reg(32'h4002_0018, 32'h0003_0005);

        // 4. Configure Wake-up Targets (0x4002_002C): Wake both NPU & Swin
        write_reg(32'h4002_002C, 32'h0000_0003);

        // 5. Configure NPU Weight Base (0x4005_0008)
        write_reg(32'h4005_0008, 32'h6000_0000);

        // 6. Configure Swin Weight Base (0x4006_0008)
        write_reg(32'h4006_0008, 32'h8000_0000);

        `uvm_info("CSR_SEQ", "CSR register configuration complete", UVM_LOW)
    endtask
endclass

`endif // AXIL_CSR_SEQ_SV
