// ==============================================================================
// Filelist for AXI4 Interconnect & Crossbar Testbench (tb_bcd_soc_axi)
// ==============================================================================
+incdir+rtl

// Header Package
rtl/bcd_soc_pkg.vh

// Interconnect & Memory Slaves
rtl/axi_crossbar_6x6.v
rtl/axi_firewall.v
rtl/axi_master_agent.v
rtl/axi_slave_rom.v
rtl/axi_slave_sram.v
rtl/axi_slave_scratchpad.v
rtl/axi_slave_nvm.v
rtl/axi_slave_lpddr.v
rtl/axi_to_axilite_bridge.v
rtl/axilite_csr_cluster.v
rtl/rtl_threshold_engine.v
rtl/bcd_soc_axi_top.v

// Testbench
tb/tb_bcd_soc_axi.v
