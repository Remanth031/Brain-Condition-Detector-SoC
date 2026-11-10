// =============================================================================
// Brain Condition Detector (BCD) SoC - Biopotential ADC Sequence Item
// =============================================================================

`ifndef ADC_SEQ_ITEM_SV
`define ADC_SEQ_ITEM_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class eeg_sample_item extends uvm_sequence_item;
    typedef enum { PATTERN_NORMAL, PATTERN_SEIZURE, PATTERN_SPINDLE, PATTERN_LEAD_OFF, PATTERN_SATURATION } pattern_e;

    rand pattern_e pattern;
    rand bit [4:0] channel_id;      // 0 to 31
    rand bit signed [23:0] sample;  // 24-bit biopotential data
    bit lead_off;
    bit saturation;

    constraint c_pattern {
        pattern dist {
            PATTERN_NORMAL     := 60,
            PATTERN_SEIZURE    := 20,
            PATTERN_SPINDLE    := 10,
            PATTERN_LEAD_OFF   := 5,
            PATTERN_SATURATION := 5
        };
    }

    `uvm_object_utils_begin(eeg_sample_item)
        `uvm_field_enum(pattern_e, pattern, UVM_ALL_ON)
        `uvm_field_int(channel_id, UVM_ALL_ON)
        `uvm_field_int(sample,     UVM_ALL_ON)
        `uvm_field_int(lead_off,   UVM_ALL_ON)
        `uvm_field_int(saturation, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "eeg_sample_item");
        super.new(name);
    endfunction

    function void post_randomize();
        case (pattern)
            PATTERN_NORMAL: begin
                sample = $urandom_range(24'h00_0800, 24'h00_1800);
                lead_off = 1'b0;
                saturation = 1'b0;
            end
            PATTERN_SEIZURE: begin
                // Large amplitude spike burst (>3x baseline)
                sample = $urandom_range(24'h70_0000, 24'h7F_0000);
                lead_off = 1'b0;
                saturation = 1'b0;
            end
            PATTERN_SPINDLE: begin
                // 11-16 Hz sigma rhythm
                sample = $urandom_range(24'h00_2000, 24'h00_4000);
                lead_off = 1'b0;
                saturation = 1'b0;
            end
            PATTERN_LEAD_OFF: begin
                sample = 24'h00_0000;
                lead_off = 1'b1;
                saturation = 1'b0;
            end
            PATTERN_SATURATION: begin
                sample = 24'h7F_FFFF; // Rail positive
                lead_off = 1'b0;
                saturation = 1'b1;
            end
        endcase
    endfunction
endclass

`endif // ADC_SEQ_ITEM_SV
