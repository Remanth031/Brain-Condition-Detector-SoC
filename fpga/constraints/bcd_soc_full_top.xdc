# ==============================================================================
# Brain Condition Detector (BCD) SoC - Master XDC Constraints File
# Target Device : AMD / Xilinx Zynq-7000 (XC7Z020-CLG400-1) / Artix-7 Compatible
# Top Module    : bcd_soc_full_top
# ==============================================================================

# ==============================================================================
# 1. PRIMARY CLOCK CONSTRAINTS
# ==============================================================================

# 1.1 Always-On Subsystem Clock (clk_ao): 100 MHz (Period: 10.000 ns)
create_clock -period 10.000 -name clk_ao -waveform {0.000 5.000} [get_ports clk_ao]

# 1.2 Medical ADC Biopotential Ingestion Clock (clk_adc): 4.096 MHz (Period: 244.140 ns)
create_clock -period 244.140 -name clk_adc -waveform {0.000 122.070} [get_ports clk_adc]

# Set Clock Uncertainty for Jitter and Duty-Cycle Distortion
set_clock_uncertainty 0.200 [get_clocks clk_ao]
set_clock_uncertainty 0.500 [get_clocks clk_adc]

# ==============================================================================
# 2. CLOCK DOMAIN CROSSING (CDC) & FALSE PATHS
# ==============================================================================

# clk_ao and clk_adc are asynchronous clock domains synchronized by ip_dsp_async_fifo
set_clock_groups -asynchronous \
    -group [get_clocks clk_ao] \
    -group [get_clocks clk_adc]

# Asynchronous Active-Low Resets
set_false_path -from [get_ports rst_ao_n]
set_false_path -from [get_ports rst_adc_n]

# Static Hardware Configuration Pins (Switches / Jumpers)
set_false_path -from [get_ports firewall_en]
set_false_path -from [get_ports production_mode]
set_false_path -from [get_ports cpu_halt_req]
set_false_path -from [get_ports cpu_run_req]

# Static Status Flag Outputs
set_false_path -to [get_ports cpu_halt_ack]
set_false_path -to [get_ports cpu_run_ack]
set_false_path -to [get_ports system_alarm_irq]

# ==============================================================================
# 3. INPUT / OUTPUT DELAY CONSTRAINTS
# ==============================================================================

# 3.1 ADC Biopotential Sensor Ingestion Delays (Referenced to clk_adc)
set_input_delay -clock clk_adc -max 15.000 [get_ports {adc_sample_valid adc_lead_off_flag adc_saturation_flag}]
set_input_delay -clock clk_adc -min  2.000 [get_ports {adc_sample_valid adc_lead_off_flag adc_saturation_flag}]
set_input_delay -clock clk_adc -max 15.000 [get_ports {adc_raw_data[*] adc_channel_id[*]}]
set_input_delay -clock clk_adc -min  2.000 [get_ports {adc_raw_data[*] adc_channel_id[*]}]

# 3.2 Host Medical Imaging Slice Ingest (Referenced to clk_ao)
set_input_delay -clock clk_ao -max 4.000 [get_ports {host_pixel_valid host_pixel_data[*]}]
set_input_delay -clock clk_ao -min 1.000 [get_ports {host_pixel_valid host_pixel_data[*]}]
set_output_delay -clock clk_ao -max 3.500 [get_ports host_pixel_ready]
set_output_delay -clock clk_ao -min 0.500 [get_ports host_pixel_ready]

# 3.3 JTAG Debug Interface (Referenced to clk_ao)
set_input_delay -clock clk_ao -max 4.500 [get_ports {jtag_cmd_start jtag_cmd_is_write jtag_cmd_addr[*] jtag_cmd_len[*] jtag_cmd_wdata[*]}]
set_input_delay -clock clk_ao -min 1.000 [get_ports {jtag_cmd_start jtag_cmd_is_write jtag_cmd_addr[*] jtag_cmd_len[*] jtag_cmd_wdata[*]}]
set_output_delay -clock clk_ao -max 4.000 [get_ports {jtag_cmd_done jtag_cmd_rdata[*]}]
set_output_delay -clock clk_ao -min 0.500 [get_ports {jtag_cmd_done jtag_cmd_rdata[*]}]

# 3.4 Telemetry, Clinical Classification & Compressed Outputs (Referenced to clk_ao)
set_output_delay -clock clk_ao -max 4.000 [get_ports {compressed_normal_word[*] compressed_bit_length[*] compressed_valid}]
set_output_delay -clock clk_ao -min 0.500 [get_ports {compressed_normal_word[*] compressed_bit_length[*] compressed_valid}]
set_output_delay -clock clk_ao -max 4.000 [get_ports {clinical_event_label[*] clinical_confidence[*]}]
set_output_delay -clock clk_ao -min 0.500 [get_ports {clinical_event_label[*] clinical_confidence[*]}]
set_output_delay -clock clk_ao -max 4.000 [get_ports {diagnostic_heatmap_pixel[*] clinical_report_ascii[*]}]
set_output_delay -clock clk_ao -min 0.500 [get_ports {diagnostic_heatmap_pixel[*] clinical_report_ascii[*]}]

# ==============================================================================
# 4. PHYSICAL PIN ASSIGNMENTS & I/O STANDARDS (Zynq-7000 / PYNQ-Z2 Example)
# ==============================================================================

# 4.1 Clocks & Resets
set_property PACKAGE_PIN H16 [get_ports clk_ao]
set_property IOSTANDARD LVCMOS33 [get_ports clk_ao]

set_property PACKAGE_PIN K17 [get_ports clk_adc]
set_property IOSTANDARD LVCMOS33 [get_ports clk_adc]

set_property PACKAGE_PIN D19 [get_ports rst_ao_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_ao_n]

set_property PACKAGE_PIN D20 [get_ports rst_adc_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_adc_n]

# 4.2 Hardware Security & Control Pins
set_property PACKAGE_PIN M20 [get_ports firewall_en]
set_property IOSTANDARD LVCMOS33 [get_ports firewall_en]

set_property PACKAGE_PIN M19 [get_ports production_mode]
set_property IOSTANDARD LVCMOS33 [get_ports production_mode]

set_property PACKAGE_PIN L19 [get_ports cpu_halt_req]
set_property IOSTANDARD LVCMOS33 [get_ports cpu_halt_req]

set_property PACKAGE_PIN R19 [get_ports cpu_run_req]
set_property IOSTANDARD LVCMOS33 [get_ports cpu_run_req]

set_property PACKAGE_PIN B19 [get_ports cpu_halt_ack]
set_property IOSTANDARD LVCMOS33 [get_ports cpu_halt_ack]

set_property PACKAGE_PIN C20 [get_ports cpu_run_ack]
set_property IOSTANDARD LVCMOS33 [get_ports cpu_run_ack]

# 4.3 Alarm & Critical Clinical Diagnostic Outputs (LEDs & Telemetry Headers)
set_property PACKAGE_PIN R14 [get_ports system_alarm_irq]
set_property IOSTANDARD LVCMOS33 [get_ports system_alarm_irq]
set_property DRIVE 8 [get_ports system_alarm_irq]
set_property SLEW FAST [get_ports system_alarm_irq]

set_property PACKAGE_PIN M14 [get_ports {clinical_event_label[0]}]
set_property PACKAGE_PIN M15 [get_ports {clinical_event_label[1]}]
set_property PACKAGE_PIN G14 [get_ports {clinical_event_label[2]}]
set_property PACKAGE_PIN D18 [get_ports {clinical_event_label[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {clinical_event_label[*]}]

set_property PACKAGE_PIN P14 [get_ports compressed_valid]
set_property IOSTANDARD LVCMOS33 [get_ports compressed_valid]

set_property PACKAGE_PIN N16 [get_ports host_pixel_ready]
set_property IOSTANDARD LVCMOS33 [get_ports host_pixel_ready]

set_property PACKAGE_PIN L15 [get_ports jtag_cmd_done]
set_property IOSTANDARD LVCMOS33 [get_ports jtag_cmd_done]

# 4.4 Multi-Pin Sensor & Imaging Bus I/O Configurations
set_property IOSTANDARD LVCMOS33 [get_ports {adc_sample_valid adc_lead_off_flag adc_saturation_flag}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_raw_data[*] adc_channel_id[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {host_pixel_valid host_pixel_data[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {jtag_cmd_start jtag_cmd_is_write jtag_cmd_addr[*] jtag_cmd_len[*] jtag_cmd_wdata[*] jtag_cmd_rdata[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {compressed_normal_word[*] compressed_bit_length[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {clinical_confidence[*] diagnostic_heatmap_pixel[*] clinical_report_ascii[*]}]

# Set Default Slew and Drive for Wide Data Busses
set_property SLEW SLOW [get_ports {compressed_normal_word[*] clinical_report_ascii[*] diagnostic_heatmap_pixel[*]}]
set_property DRIVE 4 [get_ports {compressed_normal_word[*] clinical_report_ascii[*] diagnostic_heatmap_pixel[*]}]

# ==============================================================================
# 5. BITSTREAM & CONFIGURATION SETTINGS
# ==============================================================================
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
