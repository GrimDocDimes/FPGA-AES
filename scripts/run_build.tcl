##==============================================================================
## run_build.tcl
## Open existing project and run Synthesis → Implementation → Bitstream
##
## Usage (from OS terminal — NOT from inside Vivado GUI):
##   /run/media/jhush/OLDTING/Xilinx/Vivado/2019.2/bin/vivado \
##       -mode batch -source /home/jhush/aesgit/scripts/run_build.tcl
##==============================================================================

set project_name "aes_nexys4"
set project_dir  [file normalize "/home/jhush/vivado_projects/$project_name"]
set bd_name      "aes_system"

puts "\n=========================================="
puts " Opening project: $project_dir"
puts "==========================================\n"

open_project "$project_dir/${project_name}.xpr"

file mkdir "$project_dir/reports"

## --------------------------------------------------------------------------
## Synthesis
## --------------------------------------------------------------------------
puts "\n=========================================="
puts " Starting Synthesis..."
puts "==========================================\n"

reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1

if { [get_property PROGRESS [get_runs synth_1]] != "100%" } {
    puts "ERROR: Synthesis failed!"
    puts "Check: $project_dir/${project_name}.runs/synth_1/runme.log"
    exit 1
}

puts "\n=========================================="
puts " Synthesis Complete!"
puts "==========================================\n"

open_run synth_1 -name synth_1
report_timing_summary -file "$project_dir/reports/post_synth_timing.rpt"
report_utilization    -file "$project_dir/reports/post_synth_utilization.rpt"

## --------------------------------------------------------------------------
## Implementation
## --------------------------------------------------------------------------
puts "\n=========================================="
puts " Starting Implementation..."
puts "==========================================\n"

launch_runs impl_1 -jobs 2
wait_on_run impl_1

if { [get_property PROGRESS [get_runs impl_1]] != "100%" } {
    puts "ERROR: Implementation failed!"
    puts "Check: $project_dir/${project_name}.runs/impl_1/runme.log"
    exit 1
}

puts "\n=========================================="
puts " Implementation Complete!"
puts "==========================================\n"

open_run impl_1
report_timing_summary -file "$project_dir/reports/post_route_timing.rpt"
report_utilization    -file "$project_dir/reports/post_route_utilization.rpt"
report_drc            -file "$project_dir/reports/post_route_drc.rpt"

set slack [get_property SLACK [get_timing_paths]]
if { $slack < 0 } {
    puts "WARNING: Timing not met! Slack = $slack ns"
} else {
    puts "SUCCESS: Timing met! Slack = $slack ns"
}

## --------------------------------------------------------------------------
## Bitstream
## --------------------------------------------------------------------------
puts "\n=========================================="
puts " Generating Bitstream..."
puts "==========================================\n"

set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1

## --------------------------------------------------------------------------
## Export .xsa for Vitis
## --------------------------------------------------------------------------
file mkdir "$project_dir/export"
write_hw_platform \
    -fixed       \
    -include_bit \
    -force       \
    "$project_dir/export/aes_system.xsa"

puts "\n=========================================="
puts " Build Complete!"
puts "=========================================="
puts " Bitstream : $project_dir/${project_name}.runs/impl_1/${bd_name}_wrapper.bit"
puts " XSA file  : $project_dir/export/aes_system.xsa"
puts " Reports   : $project_dir/reports/"
puts "=========================================="
