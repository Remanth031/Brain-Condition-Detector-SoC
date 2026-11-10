// =============================================================================
// Brain Condition Detector (BCD) SoC - Biopotential ADC Stimulus Sequences
// Generates continuous 32-channel scalp EEG frames, baseline rhythms,
// high-amplitude seizure bursts, sleep spindles, and lead-off disconnections
// =============================================================================

`ifndef ADC_EEG_STIMULUS_SEQ_SV
`define ADC_EEG_STIMULUS_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../vip/adc_biopotential_vip.sv"

class adc_eeg_stimulus_seq extends uvm_sequence #(eeg_sample_item);
    `uvm_object_utils(adc_eeg_stimulus_seq)

    rand int unsigned num_frames;
    rand eeg_sample_item::pattern_e forced_pattern;
    rand bit force_pattern_en;

    constraint c_frames { num_frames inside {[32:128]}; }

    function new(string name = "adc_eeg_stimulus_seq");
        super.new(name);
        force_pattern_en = 1'b0;
    endfunction

    virtual task body();
        eeg_sample_item req;
        for (int f = 0; f < num_frames; f++) begin
            for (int ch = 0; ch < 32; ch++) begin
                req = eeg_sample_item::type_id::create("eeg_sample");
                start_item(req);
                if (force_pattern_en) begin
                    req.pattern    = forced_pattern;
                    req.channel_id = ch[4:0];
                    req.post_randomize();
                end else begin
                    if (!req.randomize() with {
                        channel_id == ch[4:0];
                    }) begin
                        `uvm_error("ADC_SEQ", "Randomization failed")
                    end
                end
                finish_item(req);
            end
        end
    endtask
endclass

`endif // ADC_EEG_STIMULUS_SEQ_SV
