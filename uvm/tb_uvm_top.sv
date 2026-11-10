// =============================================================================
// Brain Condition Detector (BCD) SoC - Top-Level UVM Testbench Top
// Connects the System-on-Chip Top-Level DUT to all UVM VIP Virtual Interfaces
// Executes constrained-random and directed UVM tests via run_test()
// =============================================================================

`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../rtl/bcd_soc_pkg.vh"
`include "env/bcd_soc_env.sv"
`include "tests/bcd_soc_regression_test.sv"

// -----------------------------------------------------------------------------
// SystemVerilog Interfaces
// -----------------------------------------------------------------------------
interface axis_if #(parameter DATA_WIDTH = 32)(input logic clk);
    logic [DATA_WIDTH-1:0] tdata;
    logic [4:0]            tid;
    logic [1:0]            tuser;
    logic                  tlast;
    logic                  tvalid;
    logic                  tready;
endinterface

interface axi4_if(input logic clk);
    logic [3:0]  awid;
    logic [31:0] awaddr;
    logic [7:0]  awlen;
    logic [2:0]  awsize;
    logic [1:0]  awburst;
    logic [3:0]  awqos;
    logic        awvalid;
    logic        awready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wlast;
    logic        wvalid;
    logic        wready;
    logic [3:0]  bid;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    logic [3:0]  arid;
    logic [31:0] araddr;
    logic [7:0]  arlen;
    logic [2:0]  arsize;
    logic [1:0]  arburst;
    logic [3:0]  arqos;
    logic        arvalid;
    logic        arready;
    logic [3:0]  rid;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rlast;
    logic        rvalid;
    logic        rready;
endinterface

interface axil_if(input logic clk);
    logic [31:0] awaddr;
    logic        awvalid;
    logic        awready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    logic [31:0] araddr;
    logic        arvalid;
    logic        arready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;
endinterface

interface adc_sensor_if(input logic clk_adc);
    logic                  sample_valid;
    logic signed [23:0]    raw_data;
    logic [4:0]            channel_id;
    logic                  lead_off;
    logic                  saturation;
endinterface

// -----------------------------------------------------------------------------
// UVM Testbench Top Module
// -----------------------------------------------------------------------------
module tb_uvm_top;

    logic clk_ao;
    logic rst_ao_n;
    logic clk_adc;
    logic rst_adc_n;

    // Clock Generation
    initial begin
        clk_ao = 0;
        forever #5 clk_ao = ~clk_ao;   // 100 MHz Always-On Clock
    end

    initial begin
        clk_adc = 0;
        forever #125 clk_adc = ~clk_adc; // 4 MHz ADC Clock
    end

    // Interface Instantiations
    axis_if #(32)   intf_axis (clk_ao);
    axi4_if         intf_axi4 (clk_ao);
    axil_if         intf_axil (clk_ao);
    adc_sensor_if   intf_adc  (clk_adc);

    // DUT Instantiation
    bcd_soc_full_top #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32),
        .ID_WIDTH   (4)
    ) dut (
        .clk_ao                   (clk_ao),
        .rst_ao_n                 (rst_ao_n),
        .clk_adc                  (clk_adc),
        .rst_adc_n                (rst_adc_n),
        .adc_sample_valid         (intf_adc.sample_valid),
        .adc_raw_data             (intf_adc.raw_data),
        .adc_channel_id           (intf_adc.channel_id),
        .adc_lead_off_flag        (intf_adc.lead_off),
        .adc_saturation_flag      (intf_adc.saturation),
        .host_pixel_valid         (1'b0),
        .host_pixel_data          (16'd0),
        .host_pixel_ready         (),
        .cpu_halt_req             (1'b0),
        .cpu_halt_ack             (),
        .cpu_run_req              (1'b1),
        .cpu_run_ack              (),
        .firewall_en              (1'b1),
        .production_mode          (1'b0),
        .jtag_cmd_start           (1'b0),
        .jtag_cmd_is_write        (1'b0),
        .jtag_cmd_addr            (32'd0),
        .jtag_cmd_len             (8'd0),
        .jtag_cmd_wdata           (32'd0),
        .jtag_cmd_done            (),
        .jtag_cmd_rdata           (),
        .compressed_normal_word   (),
        .compressed_bit_length    (),
        .compressed_valid         (),
        .clinical_event_label     (),
        .clinical_confidence      (),
        .diagnostic_heatmap_pixel (),
        .clinical_report_ascii    (),
        .system_alarm_irq         ()
    );

    // Testbench Control & Configuration DB Registration
    initial begin
        rst_ao_n  = 1'b0;
        rst_adc_n = 1'b0;
        #100;
        @(posedge clk_ao);
        rst_ao_n  <= 1'b1;
        @(posedge clk_adc);
        rst_adc_n <= 1'b1;

        // Register Virtual Interfaces
        uvm_config_db#(virtual axis_if #(32))::set(null, "*", "vif", intf_axis);
        uvm_config_db#(virtual axi4_if)::set(null, "*", "vif", intf_axi4);
        uvm_config_db#(virtual axil_if)::set(null, "*", "vif", intf_axil);
        uvm_config_db#(virtual adc_sensor_if)::set(null, "*", "vif", intf_adc);

        // Run UVM Test Suite
        run_test("bcd_soc_regression_test");
    end

endmodule
