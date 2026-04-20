##==============================================================================
## build_jtag.tcl
## Full build (synth → impl → bitstream) for the JTAG-to-AXI AES design.
## No MicroBlaze, no firmware, no Vitis required.
##
## Usage (from OS terminal):
##   vivado -mode batch -source /home/jhush/aesgit/scripts/build_jtag.tcl
##==============================================================================

## ============================================================
## CONFIGURATION
## ============================================================
set REPO_ROOT    [file normalize "[file dirname [file normalize [info script]]]/.."]
set PROJECT_NAME "aes_nexys4_jtag"
set PROJECTS_DIR [file normalize "$REPO_ROOT/../vivado_projects"]
set PROJECT_DIR  "$PROJECTS_DIR/$PROJECT_NAME"
set BD_NAME      "aes_jtag_system"
set PART         "xc7a100tcsg324-1"
set IP_REPO      "$REPO_ROOT/ip_repo"
set CONSTRAINTS  "$REPO_ROOT/constraints"
set XDC_FILE     "$CONSTRAINTS/nexys4_ddr_jtag.xdc"

proc banner {msg} {
    puts "\n=========================================="
    puts "  $msg"
    puts "==========================================\n"
}

## ============================================================
## STEP 1 — Create Project & Block Design
## ============================================================
banner "STEP 1: Creating Project"

if { [file exists $PROJECT_DIR] } {
    puts "INFO: Removing existing project at $PROJECT_DIR"
    file delete -force $PROJECT_DIR
}
file mkdir $PROJECTS_DIR

create_project $PROJECT_NAME $PROJECT_DIR -part $PART -force
set_property target_language   Verilog [current_project]
set_property simulator_language Mixed   [current_project]

set_property ip_repo_paths [list $IP_REPO] [current_project]
update_ip_catalog -rebuild

set aes_vlnv [lindex [get_ipdefs -filter {VLNV =~ *myip_aes_bram*}] 0]
if { $aes_vlnv eq "" } {
    error "ERROR: myip_aes_bram IP not found in: $IP_REPO"
}
puts "INFO: AES IP found: $aes_vlnv"

file mkdir $CONSTRAINTS
set fh [open $XDC_FILE w]
puts $fh {## Nexys 4 DDR — AES JTAG-to-AXI Design
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports sys_clk]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0.000 5.000} [get_ports sys_clk]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]}
close $fh

create_bd_design $BD_NAME
current_bd_design $BD_NAME

create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_1
set_property -dict {CONFIG.PRIM_SOURCE Single_ended_clock_capable_pin CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 100.000 CONFIG.USE_LOCKED true CONFIG.USE_RESET false} [get_bd_cells clk_wiz_1]
create_bd_port -dir I -type clk -freq_hz 100000000 sys_clk
connect_bd_net [get_bd_pins clk_wiz_1/clk_in1] [get_bd_ports sys_clk]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_clk_wiz_1_100M
connect_bd_net [get_bd_pins clk_wiz_1/clk_out1] [get_bd_pins rst_clk_wiz_1_100M/slowest_sync_clk]
connect_bd_net [get_bd_pins clk_wiz_1/locked] [get_bd_pins rst_clk_wiz_1_100M/dcm_locked]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_reset
set_property CONFIG.CONST_VAL 1 [get_bd_cells const_reset]
connect_bd_net [get_bd_pins const_reset/dout] [get_bd_pins rst_clk_wiz_1_100M/ext_reset_in]

create_bd_cell -type ip -vlnv xilinx.com:ip:jtag_axi:1.2 jtag_axi_0
connect_bd_net [get_bd_pins jtag_axi_0/aclk] [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net [get_bd_pins jtag_axi_0/aresetn] [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]

create_bd_cell -type ip -vlnv $aes_vlnv myip_aes_bram_0
connect_bd_net [get_bd_pins myip_aes_bram_0/S00_AXI_ACLK] [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net [get_bd_pins myip_aes_bram_0/S00_AXI_ARESETN] [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property CONFIG.NUM_MI 1 [get_bd_cells axi_interconnect_0]
connect_bd_net [get_bd_pins axi_interconnect_0/ACLK] [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net [get_bd_pins axi_interconnect_0/ARESETN] [get_bd_pins rst_clk_wiz_1_100M/interconnect_aresetn]
connect_bd_net [get_bd_pins axi_interconnect_0/S00_ACLK] [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net [get_bd_pins axi_interconnect_0/S00_ARESETN] [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]
connect_bd_net [get_bd_pins axi_interconnect_0/M00_ACLK] [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net [get_bd_pins axi_interconnect_0/M00_ARESETN] [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]

connect_bd_intf_net [get_bd_intf_pins jtag_axi_0/M_AXI] [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_pins myip_aes_bram_0/S00_AXI]

assign_bd_address
set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces jtag_axi_0/Data]]
if { $seg ne "" } {
    set_property offset 0x44A00000 $seg
    set_property range  64K        $seg
}

validate_bd_design
save_bd_design

generate_target all [get_files "$PROJECT_DIR/${PROJECT_NAME}.srcs/sources_1/bd/$BD_NAME/$BD_NAME.bd"]
make_wrapper -files [get_files "$PROJECT_DIR/${PROJECT_NAME}.srcs/sources_1/bd/$BD_NAME/$BD_NAME.bd"] -top
add_files -norecurse "$PROJECT_DIR/${PROJECT_NAME}.srcs/sources_1/bd/$BD_NAME/hdl/${BD_NAME}_wrapper.v"
set_property top ${BD_NAME}_wrapper [current_fileset]
update_compile_order -fileset sources_1

add_files -fileset [get_filesets constrs_1] -norecurse $XDC_FILE
import_files -fileset [get_filesets constrs_1] $XDC_FILE

## ============================================================
## STEP 2 — Synthesis
## ============================================================
banner "STEP 2: Synthesis"
file mkdir "$PROJECT_DIR/reports"
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if { [get_property PROGRESS [get_runs synth_1]] != "100%" } { error "Synthesis failed!" }
open_run synth_1 -name synth_1
report_utilization -file "$PROJECT_DIR/reports/post_synth_utilization.rpt"

## ============================================================
## STEP 3 — Implementation
## ============================================================
banner "STEP 3: Implementation"
launch_runs impl_1 -jobs 4
wait_on_run impl_1
if { [get_property PROGRESS [get_runs impl_1]] != "100%" } { error "Implementation failed!" }
open_run impl_1
report_timing_summary -file "$PROJECT_DIR/reports/post_route_timing.rpt"
report_utilization -file "$PROJECT_DIR/reports/post_route_utilization.rpt"

## ============================================================
## STEP 4 — Bitstream
## ============================================================
banner "STEP 4: Generating Bitstream"
set BIT_FILE "$PROJECT_DIR/${PROJECT_NAME}.runs/impl_1/${BD_NAME}_wrapper.bit"
open_run impl_1 -name impl_1_bit
write_bitstream -force -bin_file $BIT_FILE

banner "ALL DONE!"
puts " Bitstream : $BIT_FILE"
puts " Next: Open Vivado Hardware Manager, program the board, and run:"
puts "       source $REPO_ROOT/scripts/run_aes_jtag.tcl"
puts "==========================================\n"
