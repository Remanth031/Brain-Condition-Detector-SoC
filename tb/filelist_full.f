// ==============================================================================
// Filelist for Full SoC Top-Level System Testbench (tb_bcd_soc_full_top)
// ==============================================================================
+incdir+rtl

// Header Package
rtl/bcd_soc_pkg.vh

// All RTL Files
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
rtl/bcd_soc_axi_top.v
rtl/bcd_veer_core_wrapper.v
rtl/bcd_soc_core_top.v
rtl/ip_adc_deserializer.v
rtl/ip_dsp_async_fifo.v
rtl/ip_digital_filter_bank.v
rtl/ip_streaming_feature_extractor.v
rtl/ip_spectrogram_generator.v
rtl/rtl_threshold_engine.v
rtl/ip_normal_compressor.v
rtl/ip_axis_broadcaster.v
rtl/ip_imaging_ingest.v
rtl/ip_edge_ai_npu.v
rtl/ip_swin_transformer_engine.v
rtl/ip_output_fusion.v
rtl/ip_pmu_power_sequencer.v
rtl/ip_crypto_engine.v
rtl/bcd_soc_full_top.v

// Testbench Top
tb/tb_bcd_soc_full_top.v
