# ==============================================================================
# Brain Condition Detector (BCD) SoC - Vivado Synthesis & Bitstream Flow
# ==============================================================================
# Usage:
#   vivado -mode batch -source scripts/synth.tcl
#   vivado -mode batch -source scripts/synth.tcl -tclargs xc7z020clg400-1
# ==============================================================================

# Parse Target FPGA Device (Default: AMD / Xilinx Zynq-7000 XC7Z020-CLG400-1)
set TARGET_PART "xc7z020clg400-1"
if { $argc > 0 } {
    set TARGET_PART [lindex $argv 0]
}

set TOP_MODULE  "bcd_soc_full_top"
set WORK_DIR    [pwd]
set BUILD_DIR   "$WORK_DIR/build_synth"
set REPORT_DIR  "$WORK_DIR/reports"

puts "================================================================="
puts "    Brain Condition Detector (BCD) SoC FPGA Implementation Flow   "
puts "================================================================="
puts " Target Device : $TARGET_PART"
puts " Top Module    : $TOP_MODULE"
puts " Working Dir   : $WORK_DIR"
puts " Output Dir    : $BUILD_DIR"
puts " Reports Dir   : $REPORT_DIR"
puts "================================================================="

# Create Output and Reports Directories
file mkdir $BUILD_DIR
file mkdir $REPORT_DIR

# Set Multithreading
catch { set_param general.maxThreads 8 }

# ------------------------------------------------------------------------------
# 1. In-Memory Project Creation
# ------------------------------------------------------------------------------
create_project -in_memory -part $TARGET_PART

# ------------------------------------------------------------------------------
# 2. Read Source RTL Files (Packages First, then RTL & Submodules)
# ------------------------------------------------------------------------------
puts "\n[STEP 1/7] Reading SystemVerilog Headers and RTL Sources..."

# Include Directories and Package
read_verilog -sv "$WORK_DIR/rtl/bcd_soc_pkg.vh"
set_property include_dirs "$WORK_DIR/rtl" [current_fileset]

# Read All 28 Core Verilog RTL Files
set rtl_files [glob -nocomplain "$WORK_DIR/rtl/*.v"]
if { [llength $rtl_files] > 0 } {
    read_verilog $rtl_files
    puts "Loaded [llength $rtl_files] Verilog files from rtl/"
} else {
    puts "ERROR: No Verilog files found in $WORK_DIR/rtl/"
    exit 1
}

# Read Western Digital / CHIPS Alliance VeeR EL2 Subsystem from Cores-VeeR-EL2-main
set veer_files [glob -nocomplain "$WORK_DIR/Cores-VeeR-EL2-main/design/*.sv"]
set veer_lib   [glob -nocomplain "$WORK_DIR/Cores-VeeR-EL2-main/design/lib/*.sv"]
if { [llength $veer_files] > 0 } {
    read_verilog -sv $veer_files
    read_verilog -sv $veer_lib
    puts "Loaded VeeR EL2 core subsystem files from Cores-VeeR-EL2-main."
}

# ------------------------------------------------------------------------------
# 3. Read Physical & Timing Constraints (XDC)
# ------------------------------------------------------------------------------
puts "\n[STEP 2/7] Reading Constraints (XDC)..."
set xdc_file "$WORK_DIR/fpga/constraints/bcd_soc_full_top.xdc"
if { [file exists $xdc_file] } {
    read_xdc $xdc_file
    puts "Successfully loaded: $xdc_file"
} else {
    puts "WARNING: Constraints file $xdc_file not found. Running unconstrained."
}

# ------------------------------------------------------------------------------
# 4. Synthesis (synth_design)
# ------------------------------------------------------------------------------
puts "\n[STEP 3/7] Running RTL Synthesis on $TOP_MODULE..."
synth_design -top $TOP_MODULE -part $TARGET_PART -flatten_hierarchy rebuilt \
             -directive AreaOptimized_high -resource_sharing on

write_checkpoint -force "$BUILD_DIR/post_synth.dcp"
report_utilization -file "$REPORT_DIR/utilization_synth.rpt"
report_timing_summary -file "$REPORT_DIR/timing_synth.rpt"

# ------------------------------------------------------------------------------
# 5. Logic Optimization (opt_design)
# ------------------------------------------------------------------------------
puts "\n[STEP 4/7] Running Logic Optimization..."
opt_design -directive Explore
write_checkpoint -force "$BUILD_DIR/post_opt.dcp"

# ------------------------------------------------------------------------------
# 6. Placement & Physical Optimization (place_design & phys_opt_design)
# ------------------------------------------------------------------------------
puts "\n[STEP 5/7] Running Placement & Physical Optimization..."
place_design -directive Explore
phys_opt_design -directive Explore
write_checkpoint -force "$BUILD_DIR/post_place.dcp"

# ------------------------------------------------------------------------------
# 7. Routing (route_design)
# ------------------------------------------------------------------------------
puts "\n[STEP 6/7] Running Routing..."
route_design -directive Explore
write_checkpoint -force "$BUILD_DIR/post_route.dcp"

# ------------------------------------------------------------------------------
# 8. Verification & Comprehensive Reporting
# ------------------------------------------------------------------------------
puts "\n[STEP 7/7] Generating Implementation & Signoff Reports..."
report_timing_summary -file "$REPORT_DIR/timing_summary.rpt" -max_paths 10
report_utilization -file "$REPORT_DIR/utilization.rpt" -hierarchical
report_power -file "$REPORT_DIR/power.rpt"
report_clock_interaction -file "$REPORT_DIR/clock_interaction.rpt"
report_clock_utilization -file "$REPORT_DIR/clock_utilization.rpt"
report_drc -file "$REPORT_DIR/drc.rpt"
report_io -file "$REPORT_DIR/io.rpt"

# Check Timing Closure
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "================================================================="
puts " TIMING SIGN-OFF REPORT:"
puts " Worst Negative Slack (WNS) : $wns ns"
if { $wns >= 0.0 } {
    puts " STATUS: TIMING CONSTRAINTS MET (TIMING CLOSED)"
} else {
    puts " WARNING: TIMING VIOLATION DETECTED (WNS < 0.0)"
}
puts "================================================================="

# ------------------------------------------------------------------------------
# 9. Bitstream Generation
# ------------------------------------------------------------------------------
puts "\nGenerating FPGA Bitstream..."
set bitstream_file "$BUILD_DIR/$TOP_MODULE.bit"
write_bitstream -force $bitstream_file

if { [file exists $bitstream_file] } {
    set bit_size [file size $bitstream_file]
    puts "================================================================="
    puts " SUCCESS: BITSTREAM GENERATED SUCCESSFULLY!"
    puts " File: $bitstream_file ($bit_size bytes)"
    puts " Ready for JTAG / QSPI Flash programming onto $TARGET_PART"
    puts "================================================================="
} else {
    puts "ERROR: Bitstream generation failed."
    exit 1
}

exit
