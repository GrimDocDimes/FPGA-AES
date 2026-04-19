##==============================================================================
## build.tcl
## Synthesis, Implementation and Bitstream generation for AES-128
## Nexys 4 DDR (Artix-7 XC7A100T-1CSG324C)
##
## Usage:
##   cd /home/jhush/aesgit/scripts
##   source build.tcl      <- from Vivado Tcl Console
##
##   OR from OS terminal:
##   vivado -mode batch -source /home/jhush/aesgit/scripts/build.tcl
##==============================================================================

## Source project creation (handles both cd scripts + source build.tcl,
## and source scripts/build.tcl from the repo root)
if { [file exists "[file dirname [info script]]/create_project.tcl"] } {
    source "[file dirname [info script]]/create_project.tcl"
} elseif { [file exists "create_project.tcl"] } {
    source "create_project.tcl"
} else {
    error "ERROR: Cannot find create_project.tcl"
}

puts "\n=========================================="
puts " Starting Synthesis..."
puts "==========================================\n"

## Create reports directory
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

puts "\n=========================================="
puts " Synthesis Complete!"
puts "==========================================\n"

open_run synth_1 -name synth_1
report_timing_summary -file "$project_dir/reports/post_synth_timing.rpt"
report_utilization    -file "$project_dir/reports/post_synth_utilization.rpt"
report_power          -file "$project_dir/reports/post_synth_power.rpt"

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

puts "\n=========================================="
puts " Implementation Complete!"
puts "==========================================\n"

open_run impl_1
report_timing_summary -file "$project_dir/reports/post_route_timing.rpt"
report_utilization    -file "$project_dir/reports/post_route_utilization.rpt"
report_power          -file "$project_dir/reports/post_route_power.rpt"
report_drc            -file "$project_dir/reports/post_route_drc.rpt"

set slack [get_property SLACK [get_timing_paths]]
if { $slack < 0 } {
    puts "WARNING: Timing not met! Slack = $slack ns"
} else {
    puts "SUCCESS: Timing met! Slack = $slack ns"
}

## --------------------------------------------------------------------------
## Bitstream — write directly so this session's constraints are used
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
puts " Bitstream written!"
puts "==========================================\n"

## --------------------------------------------------------------------------
## Export hardware platform (.xsa) for Vitis (2019.2: positional arg)
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
puts ""
puts " Next: Open Vitis IDE"
puts "   1. New Platform Project -> aes_system.xsa"
puts "   2. New Application Project -> Empty C"
puts "   3. Add VitisIDE/aes_encryption.c to src/"
puts "   4. Build and Run on Nexys 4 DDR (9600 baud UART)"
puts "=========================================="
