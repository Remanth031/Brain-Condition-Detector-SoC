// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Lite Sequence Item
// =============================================================================

`ifndef AXIL_SEQ_ITEM_SV
`define AXIL_SEQ_ITEM_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

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

`endif // AXIL_SEQ_ITEM_SV
