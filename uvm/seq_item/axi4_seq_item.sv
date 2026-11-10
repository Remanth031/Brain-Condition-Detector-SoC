// =============================================================================
// Brain Condition Detector (BCD) SoC - AXI4-Full Sequence Item
// =============================================================================

`ifndef AXI4_SEQ_ITEM_SV
`define AXI4_SEQ_ITEM_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

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

`endif // AXI4_SEQ_ITEM_SV
