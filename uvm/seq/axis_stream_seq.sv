// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Stream Sequences
// Generates continuous sample frames, backpressure stress, and frame sync
// =============================================================================

`ifndef AXIS_STREAM_SEQ_SV
`define AXIS_STREAM_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../vip/axi4_stream_vip.sv"

class axis_stream_seq #(parameter DATA_WIDTH = 32) extends uvm_sequence #(axis_transaction #(DATA_WIDTH));
    `uvm_object_param_utils(axis_stream_seq #(DATA_WIDTH))

    rand int unsigned num_trans;
    constraint c_trans { num_trans inside {[10:50]}; }

    function new(string name = "axis_stream_seq");
        super.new(name);
    endfunction

    virtual task body();
        axis_transaction #(DATA_WIDTH) req;
        for (int i = 0; i < num_trans; i++) begin
            req = axis_transaction #(DATA_WIDTH)::type_id::create("req");
            start_item(req);
            if (!req.randomize() with {
                tlast == (i == num_trans - 1);
            }) begin
                `uvm_error("AXIS_SEQ", "Randomization failed")
            end
            finish_item(req);
        end
    endtask
endclass

`endif // AXIS_STREAM_SEQ_SV
