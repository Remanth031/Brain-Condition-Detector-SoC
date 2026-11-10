// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Stream Sequence Item
// =============================================================================

`ifndef AXIS_SEQ_ITEM_SV
`define AXIS_SEQ_ITEM_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

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

`endif // AXIS_SEQ_ITEM_SV
