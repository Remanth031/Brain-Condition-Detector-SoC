# ==============================================================================
# Brain Condition Detector (BCD) SoC - ASIC SDC Timing Constraints
# Compatibility : Synopsys Design Compiler, Cadence Genus, OpenLane / Yosys
# Target Node   : TSMC 28nm HPC+ / SkyWater 130nm / GF 22FDX
# Top Module    : bcd_soc_full_top
# ==============================================================================

# Time unit: ns, Capacitance unit: pF
set_units -time ns -capacitance pF

# 1. Primary Clock Definitions
create_clock -name clk_ao  -period 10.000 [get_ports clk_ao]
create_clock -name clk_adc -period 244.140 [get_ports clk_adc]

# Set Clock Latency and Transition
set_clock_latency -source 0.500 [get_clocks clk_ao]
set_clock_latency -source 1.000 [get_clocks clk_adc]
set_clock_transition 0.150 [get_clocks clk_ao]
set_clock_transition 0.300 [get_clocks clk_adc]

# Clock Uncertainty (Jitter + Margin)
set_clock_uncertainty -setup 0.250 [get_clocks clk_ao]
set_clock_uncertainty -hold  0.080 [get_clocks clk_ao]
set_clock_uncertainty -setup 0.500 [get_clocks clk_adc]
set_clock_uncertainty -hold  0.150 [get_clocks clk_adc]

# 2. Clock Domain Crossing (Asynchronous Groups)
set_clock_groups -asynchronous \
    -group [get_clocks clk_ao] \
    -group [get_clocks clk_adc]

# 3. False Paths (Static / Configuration / Reset Ports)
set_false_path -from [get_ports rst_ao_n]
set_false_path -from [get_ports rst_adc_n]
set_false_path -from [get_ports firewall_en]
set_false_path -from [get_ports production_mode]
set_false_path -from [get_ports cpu_halt_req]
set_false_path -from [get_ports cpu_run_req]
set_false_path -to   [get_ports cpu_halt_ack]
set_false_path -to   [get_ports cpu_run_ack]
set_false_path -to   [get_ports system_alarm_irq]

# 4. Input / Output Constraints
set_input_delay  -clock clk_adc -max 10.0 [get_ports {adc_sample_valid adc_raw_data[*] adc_channel_id[*] adc_lead_off_flag adc_saturation_flag}]
set_input_delay  -clock clk_adc -min  1.5 [get_ports {adc_sample_valid adc_raw_data[*] adc_channel_id[*] adc_lead_off_flag adc_saturation_flag}]

set_input_delay  -clock clk_ao  -max  3.5 [get_ports {host_pixel_valid host_pixel_data[*] jtag_cmd_*}]
set_input_delay  -clock clk_ao  -min  0.5 [get_ports {host_pixel_valid host_pixel_data[*] jtag_cmd_*}]

set_output_delay -clock clk_ao  -max  3.5 [get_ports {host_pixel_ready jtag_cmd_done jtag_cmd_rdata[*]}]
set_output_delay -clock clk_ao  -min  0.5 [get_ports {host_pixel_ready jtag_cmd_done jtag_cmd_rdata[*]}]

set_output_delay -clock clk_ao  -max  4.0 [get_ports {compressed_normal_word[*] compressed_bit_length[*] compressed_valid clinical_event_label[*] clinical_confidence[*] diagnostic_heatmap_pixel[*] clinical_report_ascii[*]}]
set_output_delay -clock clk_ao  -min  0.5 [get_ports {compressed_normal_word[*] compressed_bit_length[*] compressed_valid clinical_event_label[*] clinical_confidence[*] diagnostic_heatmap_pixel[*] clinical_report_ascii[*]}]

# 5. Environmental & Driving Cell Constraints
set_max_fanout 16 [current_design]
set_max_transition 0.350 [current_design]
