// =============================================================================
// Brain Condition Detector (BCD) SoC - UVM Full Regression Test
// Executes the master virtual sequence across all VIP agents:
// - AXI4-Lite CSR configuration
// - Multi-channel Scalp EEG streaming
// - Ictal seizure burst injection
// - NPU EEGNet & Swin Transformer acceleration
// - AXI4-Full memory burst verification
// =============================================================================

`ifndef BCD_SOC_REGRESSION_TEST_SV
`define BCD_SOC_REGRESSION_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "bcd_soc_base_test.sv"
`include "../seq/bcd_soc_virtual_seq.sv"

class bcd_soc_regression_test extends bcd_soc_base_test;
    `uvm_component_utils(bcd_soc_regression_test)

    bcd_soc_virtual_seq vseq;

    function new(string name = "bcd_soc_regression_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("TEST", "===================================================================", UVM_LOW)
        `uvm_info("TEST", "   STARTING BCD SoC FULL-SYSTEM UVM REGRESSION TEST SUITE         ", UVM_LOW)
        `uvm_info("TEST", "===================================================================", UVM_LOW)

        vseq = bcd_soc_virtual_seq::type_id::create("vseq");
        vseq.start(env.v_sqr);

        #1000;
        `uvm_info("TEST", "===================================================================", UVM_LOW)
        `uvm_info("TEST", "   BCD SoC UVM REGRESSION TEST SUITE COMPLETED SUCCESSFULLY!       ", UVM_LOW)
        `uvm_info("TEST", "===================================================================", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

`endif // BCD_SOC_REGRESSION_TEST_SV
