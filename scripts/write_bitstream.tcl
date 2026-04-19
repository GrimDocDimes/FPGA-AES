##==============================================================================
## write_bitstream.tcl
## Opens the existing routed checkpoint, applies UART pin constraints inline,
## writes the bitstream, and exports the .xsa for Vitis.
##
## Use this when impl_1 is already routed and only bitstream gen was failing.
##
## Usage (from OS terminal — NOT from inside Vivado GUI):
##   vivado -mode batch -source /home/jhush/aesgit/scripts/write_bitstream.tcl
##==============================================================================

set project_name "aes_nexys4"
set project_dir  [file normalize "/home/jhush/vivado_projects/$project_name"]
set bd_name      "aes_system"
set dcp_file     "$project_dir/${project_name}.runs/impl_1/aes_system_wrapper_routed.dcp"
set bit_file     "$project_dir/${project_name}.runs/impl_1/aes_system_wrapper.bit"

puts "\n=========================================="
puts " Opening routed checkpoint..."
puts "==========================================\n"

open_checkpoint $dcp_file

## ---- Apply constraints inline (they are NOT in the routed checkpoint) ------
puts "INFO: Applying I/O constraints..."

## UART pins — BD exports these as UART_rxd / UART_txd
set_property PACKAGE_PIN  C4       [get_ports UART_rxd]
set_property IOSTANDARD   LVCMOS33 [get_ports UART_rxd]
set_property PACKAGE_PIN  D4       [get_ports UART_txd]
set_property IOSTANDARD   LVCMOS33 [get_ports UART_txd]

## Board configuration voltage (suppress CFGBVS-1 DRC warning)
set_property CFGBVS        VCCO    [current_design]
set_property CONFIG_VOLTAGE 3.3    [current_design]

## ---- Write bitstream --------------------------------------------------------
puts "\n=========================================="
puts " Generating Bitstream..."
puts "==========================================\n"

write_bitstream -force -bin_file $bit_file

puts "\n=========================================="
puts " Bitstream written:"
puts "   $bit_file"
puts "==========================================\n"

## ---- Export .xsa for Vitis (Vivado 2019.2 positional-arg syntax) -----------
file mkdir "$project_dir/export"
set xsa_file "$project_dir/export/aes_system.xsa"

write_hw_platform \
    -fixed       \
    -include_bit \
    -force       \
    $xsa_file

puts "\n=========================================="
puts " Export Complete!"
puts "=========================================="
puts " Bitstream : $bit_file"
puts " .bin file : [file rootname $bit_file].bin"
puts " XSA file  : $xsa_file"
puts "=========================================="
