##==============================================================================
## build_jtag.tcl
## Full build (synth → impl → bitstream) for the JTAG-to-AXI AES design.
## No MicroBlaze, no firmware, no Vitis required.
##
## Usage (from OS terminal):
##   vivado -mode batch -source /home/jhush/aesgit/scripts/build_jtag.tcl
##==============================================================================

source "[file dirname [file normalize [info script]]]/create_project_jtag.tcl"

puts "\n=========================================="
puts " Starting Synthesis..."
puts "==========================================\n"

file mkdir "$project_dir/reports"

## --------------------------------------------------------------------------
## Synthesis
## --------------------------------------------------------------------------
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if { [get_property PROGRESS [get_runs synth_1]] != "100%" } {
    puts "ERROR: Synthesis failed!"
    puts "Check: $project_dir/${project_name}.runs/synth_1/runme.log"
    exit 1
}
puts "\n==========================================\n Synthesis Complete!\n==========================================\n"

open_run synth_1 -name synth_1
report_utilization -file "$project_dir/reports/post_synth_utilization.rpt"

## --------------------------------------------------------------------------
## Implementation
## --------------------------------------------------------------------------
puts "\n=========================================="
puts " Starting Implementation..."
puts "==========================================\n"

launch_runs impl_1 -jobs 4
wait_on_run impl_1

if { [get_property PROGRESS [get_runs impl_1]] != "100%" } {
    puts "ERROR: Implementation failed!"
    puts "Check: $project_dir/${project_name}.runs/impl_1/runme.log"
    exit 1
}
puts "\n==========================================\n Implementation Complete!\n==========================================\n"

open_run impl_1
report_timing_summary -file "$project_dir/reports/post_route_timing.rpt"
report_utilization    -file "$project_dir/reports/post_route_utilization.rpt"

set slack [get_property SLACK [get_timing_paths]]
if { $slack < 0 } {
    puts "WARNING: Timing not met! Slack = $slack ns"
} else {
    puts "SUCCESS: Timing met! Slack = $slack ns"
}

## --------------------------------------------------------------------------
## Bitstream — write directly in this session (constraints stay live)
## --------------------------------------------------------------------------
puts "\n=========================================="
puts " Generating Bitstream..."
puts "==========================================\n"

open_run impl_1 -name impl_1_bit
write_bitstream \
    -force    \
    -bin_file \
    "$project_dir/${project_name}.runs/impl_1/${bd_name}_wrapper.bit"

puts "\n=========================================="
puts " Build Complete!"
puts "=========================================="
puts " Bitstream : $project_dir/${project_name}.runs/impl_1/${bd_name}_wrapper.bit"
puts " Reports   : $project_dir/reports/"
puts ""
puts " Next steps:"
puts "   1. Open Vivado Hardware Manager"
puts "   2. Connect to the Nexys 4 DDR"
puts "   3. Program with the bitstream above"
puts "   4. Run: source /home/jhush/aesgit/scripts/run_aes_jtag.tcl"
puts "=========================================="
