// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Full Memory Burst Sequences
// Generates INCR bursts across all slave memories (SRAM, Scratchpad, NVM, LPDDR)
// =============================================================================

`ifndef AXI4_BURST_SEQ_SV
`define AXI4_BURST_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../vip/axi4_full_vip.sv"

class axi4_burst_seq extends uvm_sequence #(axi4_transaction);
    `uvm_object_utils(axi4_burst_seq)

    rand bit [31:0] target_addr;
    rand bit [7:0]  burst_len;
    rand bit        is_write;

    constraint c_burst {
        burst_len inside {3, 7, 15}; // 4, 8, or 16 beats
        target_addr inside {
            [32'h1000_0000 : 32'h100F_0000], // SRAM
            [32'h1100_0000 : 32'h111F_0000], // Scratchpad
            [32'h8000_0000 : 32'h800F_0000]  // LPDDR
        };
    }

    function new(string name = "axi4_burst_seq");
        super.new(name);
    endfunction

    virtual task body();
        axi4_transaction req;
        req = axi4_transaction::type_id::create("req");

        start_item(req);
        if (!req.randomize() with {
            trans_type == (is_write ? axi4_transaction::AXI_WRITE : axi4_transaction::AXI_READ);
            addr       == target_addr;
            len        == burst_len;
        }) begin
            `uvm_error("AXI4_SEQ", "Randomization failed")
        end
        finish_item(req);
    endtask
endclass

`endif // AXI4_BURST_SEQ_SV
