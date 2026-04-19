##==============================================================================
## create_project_jtag.tcl
## Creates a Vivado project with JTAG-to-AXI Master → AES IP
## NO MicroBlaze, NO UART, NO firmware required.
## Control the AES core directly from Vivado Hardware Manager via JTAG.
##
## Usage: called by build_jtag.tcl — do not source alone.
##==============================================================================

set script_dir   [file dirname [file normalize [info script]]]
set repo_root    [file normalize "$script_dir/.."]

set project_name "aes_nexys4_jtag"
set project_dir  [file normalize "$repo_root/../vivado_projects/$project_name"]
set bd_name      "aes_jtag_system"
set part         "xc7a100tcsg324-1"
set ip_repo_dir  [file normalize "$repo_root/ip_repo"]
set constraints_dir [file normalize "$repo_root/constraints"]
set xdc_file     "$constraints_dir/nexys4_ddr_jtag.xdc"

puts "=========================================="
puts " AES-128 JTAG-to-AXI — Create Project"
puts "=========================================="
puts " Project : $project_dir"
puts " Part    : $part"
puts " IP Repo : $ip_repo_dir"
puts "=========================================="

## --------------------------------------------------------------------------
## 1. Create Vivado project
## --------------------------------------------------------------------------
create_project $project_name $project_dir -part $part -force
set_property target_language   Verilog [current_project]
set_property simulator_language Mixed   [current_project]

## --------------------------------------------------------------------------
## 2. Register custom AES IP repository
## --------------------------------------------------------------------------
set_property ip_repo_paths [list $ip_repo_dir] [current_project]
update_ip_catalog -rebuild

set aes_vlnv [lindex [get_ipdefs -filter {VLNV =~ *myip_aes_bram*}] 0]
if { $aes_vlnv eq "" } {
    error "ERROR: myip_aes_bram IP not found in: $ip_repo_dir"
}
puts "INFO: AES IP found: $aes_vlnv"

## --------------------------------------------------------------------------
## 3. Write XDC — only sys_clk needed (no UART for JTAG design)
## --------------------------------------------------------------------------
file mkdir $constraints_dir
set fh [open $xdc_file w]
puts $fh {## Nexys 4 DDR — AES JTAG-to-AXI design
## 100 MHz single-ended system clock (Pin E3)
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports sys_clk]
create_clock -add -name sys_clk_pin -period 10.000 \
             -waveform {0.000 5.000} [get_ports sys_clk]
## Board configuration voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]}
close $fh
puts "INFO: XDC written -> $xdc_file"

## --------------------------------------------------------------------------
## 4. Create Block Design
## --------------------------------------------------------------------------
create_bd_design $bd_name
current_bd_design $bd_name

## ---- Clocking Wizard (single-ended 100 MHz → 100 MHz) --------------------
puts "INFO: Adding Clocking Wizard..."
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_1
set_property -dict {
    CONFIG.PRIM_SOURCE          Single_ended_clock_capable_pin
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 100.000
    CONFIG.USE_LOCKED           true
    CONFIG.USE_RESET            false
} [get_bd_cells clk_wiz_1]

create_bd_port -dir I -type clk -freq_hz 100000000 sys_clk
connect_bd_net [get_bd_pins clk_wiz_1/clk_in1] [get_bd_ports sys_clk]

## ---- Processor System Reset -----------------------------------------------
puts "INFO: Adding Proc Sys Reset..."
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_clk_wiz_1_100M
connect_bd_net [get_bd_pins clk_wiz_1/clk_out1]  \
               [get_bd_pins rst_clk_wiz_1_100M/slowest_sync_clk]
connect_bd_net [get_bd_pins clk_wiz_1/locked]     \
               [get_bd_pins rst_clk_wiz_1_100M/dcm_locked]

## Tie ext_reset_in HIGH to keep design out of reset (active-low input)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_reset
set_property CONFIG.CONST_VAL 1 [get_bd_cells const_reset]
connect_bd_net [get_bd_pins const_reset/dout] \
               [get_bd_pins rst_clk_wiz_1_100M/ext_reset_in]

## ---- JTAG-to-AXI Master ---------------------------------------------------
puts "INFO: Adding JTAG-to-AXI Master..."
create_bd_cell -type ip -vlnv xilinx.com:ip:jtag_axi:1.2 jtag_axi_0
connect_bd_net [get_bd_pins jtag_axi_0/aclk]   [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net [get_bd_pins jtag_axi_0/aresetn] \
               [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]

## ---- AES Custom IP --------------------------------------------------------
puts "INFO: Adding AES IP ($aes_vlnv)..."
create_bd_cell -type ip -vlnv $aes_vlnv myip_aes_bram_0
connect_bd_net [get_bd_pins myip_aes_bram_0/S00_AXI_ACLK] \
               [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net [get_bd_pins myip_aes_bram_0/S00_AXI_ARESETN] \
               [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]

## ---- Connect AXI: JTAG Master → AXI Interconnect → AES Slave ------------
puts "INFO: Connecting AXI bus..."
apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config {
        Master     "/jtag_axi_0"
        Slave      "/myip_aes_bram_0/S00_AXI"
        Clk_master "/clk_wiz_1/clk_out1"
        Clk_slave  "Auto"
        Clk_xbar   "Auto"
        intc_ip    "New AXI Interconnect"
        master_apm "0"
    } \
    [get_bd_intf_pins myip_aes_bram_0/S00_AXI]

## ---- Assign address to AES IP --------------------------------------------
## Fixed at 0x44A00000 so run_aes_jtag.tcl addresses match
assign_bd_address
set_property offset 0x44A00000 \
    [get_bd_addr_segs {jtag_axi_0/Data/SEG_myip_aes_bram_0_reg0}]
set_property range 64K \
    [get_bd_addr_segs {jtag_axi_0/Data/SEG_myip_aes_bram_0_reg0}]

## --------------------------------------------------------------------------
## 5. Validate and save
## --------------------------------------------------------------------------
puts "INFO: Validating block design..."
validate_bd_design
save_bd_design

## --------------------------------------------------------------------------
## 6. Generate output products and HDL wrapper
## --------------------------------------------------------------------------
puts "INFO: Generating output products..."
generate_target all \
    [get_files "$project_dir/${project_name}.srcs/sources_1/bd/$bd_name/$bd_name.bd"]

puts "INFO: Creating HDL wrapper..."
make_wrapper \
    -files [get_files \
        "$project_dir/${project_name}.srcs/sources_1/bd/$bd_name/$bd_name.bd"] \
    -top

add_files -norecurse \
    "$project_dir/${project_name}.srcs/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.v"
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

## --------------------------------------------------------------------------
## 7. Add XDC constraints
## --------------------------------------------------------------------------
puts "INFO: Adding constraints..."
add_files    -fileset [get_filesets constrs_1] -norecurse $xdc_file
import_files -fileset [get_filesets constrs_1] $xdc_file

puts ""
puts "=========================================="
puts " JTAG project created successfully."
puts "=========================================="
