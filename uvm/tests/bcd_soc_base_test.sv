// =============================================================================
// Brain Condition Detector (BCD) SoC - UVM Base Test
// Base class for all UVM tests:
// - Instantiates and builds the top-level bcd_soc_env
// - Configures simulation timeouts and reporting verbosity
// - Manages phase objections
// =============================================================================

`ifndef BCD_SOC_BASE_TEST_SV
`define BCD_SOC_BASE_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../env/bcd_soc_env.sv"

class bcd_soc_base_test extends uvm_test;
    `uvm_component_utils(bcd_soc_base_test)

    bcd_soc_env env;

    function new(string name = "bcd_soc_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = bcd_soc_env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    virtual task run_phase(uvm_phase phase);
        // Base run phase placeholder
    endtask
endclass

`endif // BCD_SOC_BASE_TEST_SV
