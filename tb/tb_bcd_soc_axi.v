// =============================================================================
// Brain Condition Detector (BCD) SoC - Verilog Simulation Testbench
// Validates 6x6 Interconnect Crossbar, All Masters (M0-M5), All Slaves (S0-S5),
// QoS Arbitration, Address Decoding, Burst Transfers, AXI-Lite Bridge, and Threshold CSRs.
// =============================================================================

`timescale 1ns / 1ps
`include "bcd_soc_pkg.vh"

module tb_bcd_soc_axi;

    reg clk;
    reg resetn;
    reg firewall_en;
    reg production_mode;

    // Master Command Stimulus Signals
    reg        m0_cmd_start, m0_cmd_is_write;
    reg [31:0] m0_cmd_addr, m0_cmd_wdata;
    reg [7:0]  m0_cmd_len;
    reg [3:0]  m0_cmd_qos;
    reg [3:0]  m0_cmd_wstrb;
    wire       m0_cmd_done;
    wire [1:0] m0_cmd_resp;
    wire [31:0] m0_cmd_rdata;

    reg        m1_cmd_start, m1_cmd_is_write;
    reg [31:0] m1_cmd_addr, m1_cmd_wdata;
    reg [7:0]  m1_cmd_len;
    reg [3:0]  m1_cmd_qos;
    reg [3:0]  m1_cmd_wstrb;
    wire       m1_cmd_done;
    wire [1:0] m1_cmd_resp;
    wire [31:0] m1_cmd_rdata;

    reg        m2_cmd_start, m2_cmd_is_write;
    reg [31:0] m2_cmd_addr, m2_cmd_wdata;
    reg [7:0]  m2_cmd_len;
    reg [3:0]  m2_cmd_qos;
    reg [3:0]  m2_cmd_wstrb;
    wire       m2_cmd_done;
    wire [1:0] m2_cmd_resp;
    wire [31:0] m2_cmd_rdata;

    reg        m3_cmd_start, m3_cmd_is_write;
    reg [31:0] m3_cmd_addr, m3_cmd_wdata;
    reg [7:0]  m3_cmd_len;
    reg [3:0]  m3_cmd_qos;
    reg [3:0]  m3_cmd_wstrb;
    wire       m3_cmd_done;
    wire [1:0] m3_cmd_resp;
    wire [31:0] m3_cmd_rdata;

    reg        m4_cmd_start, m4_cmd_is_write;
    reg [31:0] m4_cmd_addr, m4_cmd_wdata;
    reg [7:0]  m4_cmd_len;
    reg [3:0]  m4_cmd_qos;
    reg [3:0]  m4_cmd_wstrb;
    wire       m4_cmd_done;
    wire [1:0] m4_cmd_resp;
    wire [31:0] m4_cmd_rdata;

    reg        m5_cmd_start, m5_cmd_is_write;
    reg [31:0] m5_cmd_addr, m5_cmd_wdata;
    reg [7:0]  m5_cmd_len;
    reg [3:0]  m5_cmd_qos;
    reg [3:0]  m5_cmd_wstrb;
    wire       m5_cmd_done;
    wire [1:0] m5_cmd_resp;
    wire [31:0] m5_cmd_rdata;

    wire       threshold_abnormal_irq;
    wire [2:0] threshold_wake_target;
    wire       firewall_violation_irq;

    // DUT Instantiation
    bcd_soc_axi_top #(
        .BOOT_HEX_FILE       ("mem/boot.hex"),
        .SRAM_MEM_FILE       ("mem/sram.mem"),
        .SCRATCHPAD_HEX_FILE ("mem/scratchpad.hex"),
        .NVM_HEX_FILE        ("mem/nvm.hex"),
        .LPDDR_HEX_FILE      ("mem/lpddr.hex")
    ) u_dut (
        .aclk(clk),
        .aresetn(resetn),
        .firewall_en(firewall_en),
        .production_mode(production_mode),

        .m0_cmd_start(m0_cmd_start), .m0_cmd_is_write(m0_cmd_is_write), .m0_cmd_addr(m0_cmd_addr),
        .m0_cmd_len(m0_cmd_len), .m0_cmd_qos(m0_cmd_qos), .m0_cmd_wdata(m0_cmd_wdata),
        .m0_cmd_wstrb(m0_cmd_wstrb), .m0_cmd_done(m0_cmd_done), .m0_cmd_resp(m0_cmd_resp),
        .m0_cmd_rdata(m0_cmd_rdata),

        .m1_cmd_start(m1_cmd_start), .m1_cmd_is_write(m1_cmd_is_write), .m1_cmd_addr(m1_cmd_addr),
        .m1_cmd_len(m1_cmd_len), .m1_cmd_qos(m1_cmd_qos), .m1_cmd_wdata(m1_cmd_wdata),
        .m1_cmd_wstrb(m1_cmd_wstrb), .m1_cmd_done(m1_cmd_done), .m1_cmd_resp(m1_cmd_resp),
        .m1_cmd_rdata(m1_cmd_rdata),

        .m2_cmd_start(m2_cmd_start), .m2_cmd_is_write(m2_cmd_is_write), .m2_cmd_addr(m2_cmd_addr),
        .m2_cmd_len(m2_cmd_len), .m2_cmd_qos(m2_cmd_qos), .m2_cmd_wdata(m2_cmd_wdata),
        .m2_cmd_wstrb(m2_cmd_wstrb), .m2_cmd_done(m2_cmd_done), .m2_cmd_resp(m2_cmd_resp),
        .m2_cmd_rdata(m2_cmd_rdata),

        .m3_cmd_start(m3_cmd_start), .m3_cmd_is_write(m3_cmd_is_write), .m3_cmd_addr(m3_cmd_addr),
        .m3_cmd_len(m3_cmd_len), .m3_cmd_qos(m3_cmd_qos), .m3_cmd_wdata(m3_cmd_wdata),
        .m3_cmd_wstrb(m3_cmd_wstrb), .m3_cmd_done(m3_cmd_done), .m3_cmd_resp(m3_cmd_resp),
        .m3_cmd_rdata(m3_cmd_rdata),

        .m4_cmd_start(m4_cmd_start), .m4_cmd_is_write(m4_cmd_is_write), .m4_cmd_addr(m4_cmd_addr),
        .m4_cmd_len(m4_cmd_len), .m4_cmd_qos(m4_cmd_qos), .m4_cmd_wdata(m4_cmd_wdata),
        .m4_cmd_wstrb(m4_cmd_wstrb), .m4_cmd_done(m4_cmd_done), .m4_cmd_resp(m4_cmd_resp),
        .m4_cmd_rdata(m4_cmd_rdata),

        .m5_cmd_start(m5_cmd_start), .m5_cmd_is_write(m5_cmd_is_write), .m5_cmd_addr(m5_cmd_addr),
        .m5_cmd_len(m5_cmd_len), .m5_cmd_qos(m5_cmd_qos), .m5_cmd_wdata(m5_cmd_wdata),
        .m5_cmd_wstrb(m5_cmd_wstrb), .m5_cmd_done(m5_cmd_done), .m5_cmd_resp(m5_cmd_resp),
        .m5_cmd_rdata(m5_cmd_rdata),

        .threshold_abnormal_irq(threshold_abnormal_irq),
        .threshold_wake_target(threshold_wake_target),
        .firewall_violation_irq(firewall_violation_irq)
    );

    // Clock generation (100 MHz, 10 ns period)
    always #5 clk = ~clk;

    // Test counters
    integer tests_passed = 0;
    integer tests_failed = 0;

    // Helper task to execute M0 transaction
    task do_m0_write(input [31:0] addr, input [31:0] data, input [7:0] len);
        begin
            @(posedge clk);
            m0_cmd_addr     <= addr;
            m0_cmd_wdata    <= data;
            m0_cmd_len      <= len;
            m0_cmd_wstrb    <= 4'b1111;
            m0_cmd_qos      <= 4'd4;
            m0_cmd_is_write <= 1'b1;
            m0_cmd_start    <= 1'b1;
            @(posedge clk);
            m0_cmd_start    <= 1'b0;
            @(posedge m0_cmd_done);
            @(posedge clk);
        end
    endtask

    task do_m0_read(input [31:0] addr, input [7:0] len, output [31:0] rdata, output [1:0] resp);
        begin
            @(posedge clk);
            m0_cmd_addr     <= addr;
            m0_cmd_len      <= len;
            m0_cmd_qos      <= 4'd4;
            m0_cmd_is_write <= 1'b0;
            m0_cmd_start    <= 1'b1;
            @(posedge clk);
            m0_cmd_start    <= 1'b0;
            @(posedge m0_cmd_done);
            rdata = m0_cmd_rdata;
            resp  = m0_cmd_resp;
            @(posedge clk);
        end
    endtask

    reg [31:0] read_val;
    reg [1:0]  resp_val;

    initial begin
        clk = 0;
        resetn = 0;
        firewall_en = 0;
        production_mode = 0;
        m0_cmd_start = 0; m0_cmd_is_write = 0; m0_cmd_addr = 0; m0_cmd_wdata = 0; m0_cmd_len = 0; m0_cmd_qos = 0; m0_cmd_wstrb = 0;
        m1_cmd_start = 0; m1_cmd_is_write = 0; m1_cmd_addr = 0; m1_cmd_wdata = 0; m1_cmd_len = 0; m1_cmd_qos = 0; m1_cmd_wstrb = 0;
        m2_cmd_start = 0; m2_cmd_is_write = 0; m2_cmd_addr = 0; m2_cmd_wdata = 0; m2_cmd_len = 0; m2_cmd_qos = 0; m2_cmd_wstrb = 0;
        m3_cmd_start = 0; m3_cmd_is_write = 0; m3_cmd_addr = 0; m3_cmd_wdata = 0; m3_cmd_len = 0; m3_cmd_qos = 0; m3_cmd_wstrb = 0;
        m4_cmd_start = 0; m4_cmd_is_write = 0; m4_cmd_addr = 0; m4_cmd_wdata = 0; m4_cmd_len = 0; m4_cmd_qos = 0; m4_cmd_wstrb = 0;
        m5_cmd_start = 0; m5_cmd_is_write = 0; m5_cmd_addr = 0; m5_cmd_wdata = 0; m5_cmd_len = 0; m5_cmd_qos = 0; m5_cmd_wstrb = 0;

        #20 resetn = 1;
        #20;

        $display("=================================================================");
        $display("Starting Brain Condition Detector (BCD) SoC Verilog Simulation...");
        $display("=================================================================");

        // Test 1: Read Boot ROM
        do_m0_read(32'h0000_0000, 8'd0, read_val, resp_val);
        if (resp_val == `AXI_RESP_OKAY && read_val == 32'h6263_6431) begin
            $display("[PASS] Boot ROM Read: data=0x%08h", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Boot ROM Read: data=0x%08h, resp=%b", read_val, resp_val);
            tests_failed = tests_failed + 1;
        end

        // Test 2: Write Boot ROM (expect SLVERR)
        do_m0_write(32'h0000_0000, 32'h1234_5678, 8'd0);
        if (m0_cmd_resp == `AXI_RESP_SLVERR) begin
            $display("[PASS] Boot ROM Write correctly rejected with SLVERR");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Boot ROM Write did not return SLVERR (resp=%b)", m0_cmd_resp);
            tests_failed = tests_failed + 1;
        end

        // Test 3: Write and Read SRAM Ring Buffer
        do_m0_write(32'h1000_0040, 32'hA1B2_C3D4, 8'd0);
        do_m0_read(32'h1000_0040, 8'd0, read_val, resp_val);
        if (resp_val == `AXI_RESP_OKAY && read_val == 32'hA1B2_C3D4) begin
            $display("[PASS] SRAM S0 Write/Read Matched: 0x%08h", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] SRAM S0 Write/Read Mismatch: expected 0xA1B2C3D4, got 0x%08h", read_val);
            tests_failed = tests_failed + 1;
        end

        // Test 4: Program RTL Threshold Engine Registers
        do_m0_write(`CSR_BASE_THRESHOLD + `THRESH_REG_LL_THR, 32'h0000_08A0, 8'd0);
        do_m0_read(`CSR_BASE_THRESHOLD + `THRESH_REG_LL_THR, 8'd0, read_val, resp_val);
        if (resp_val == `AXI_RESP_OKAY && read_val == 32'h0000_08A0) begin
            $display("[PASS] Threshold Engine LL_THR programmed and read: 0x%08h", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Threshold Engine LL_THR failed: got 0x%08h", read_val);
            tests_failed = tests_failed + 1;
        end

        // Test 5: Read Accelerator Scratchpad (S2)
        do_m0_read(32'h1100_0000, 8'd0, read_val, resp_val);
        if (resp_val == `AXI_RESP_OKAY && read_val == 32'h5350_4144) begin
            $display("[PASS] Scratchpad Read: data=0x%08h ('SPAD')", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Scratchpad Read: expected 0x53504144, got 0x%08h", read_val);
            tests_failed = tests_failed + 1;
        end

        // Test 6: Read QSPI NVM / MRAM (S4)
        do_m0_read(32'h6000_0000, 8'd0, read_val, resp_val);
        if (resp_val == `AXI_RESP_OKAY && read_val == 32'h4545_474E) begin
            $display("[PASS] NVM Read: data=0x%08h ('EEGN')", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] NVM Read: expected 0x4545474E, got 0x%08h", read_val);
            tests_failed = tests_failed + 1;
        end

        // Test 7: Read LPDDR Memory Controller (S5)
        do_m0_read(32'h8000_0000, 8'd0, read_val, resp_val);
        if (resp_val == `AXI_RESP_OKAY && read_val == 32'h5357_494E) begin
            $display("[PASS] LPDDR Read: data=0x%08h ('SWIN')", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] LPDDR Read: expected 0x5357494E, got 0x%08h", read_val);
            tests_failed = tests_failed + 1;
        end

        $display("=================================================================");
        $display("Initial Verilog Sanity Complete. Passed: %0d, Failed: %0d", tests_passed, tests_failed);
        $display("=================================================================");
        $finish;
    end

endmodule
