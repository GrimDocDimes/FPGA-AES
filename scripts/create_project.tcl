##==============================================================================
## create_project.tcl
## Creates the Vivado project, adds custom IP, builds the MicroBlaze
## block design for the AES-128 FPGA implementation on Nexys 4 DDR
##
## Usage (called by build.tcl — do not run this alone):
##   cd /home/jhush/aesgit/scripts
##   source build.tcl
##==============================================================================

## --------------------------------------------------------------------------
## Global variables (shared with build.tcl)
## --------------------------------------------------------------------------
set script_dir   [file dirname [file normalize [info script]]]
set repo_root    [file normalize "$script_dir/.."]

set project_name "aes_nexys4"
set project_dir  [file normalize "$repo_root/../vivado_projects/$project_name"]
set bd_name      "aes_system"
set part         "xc7a100tcsg324-1"
set ip_repo_dir  [file normalize "$repo_root/ip_repo"]
set constraints_dir [file normalize "$repo_root/constraints"]
set xdc_file     "$constraints_dir/nexys4_ddr_aes.xdc"

puts "=========================================="
puts " AES-128 Nexys 4 DDR — Create Project"
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
## 3. Write XDC constraints file
## --------------------------------------------------------------------------
file mkdir $constraints_dir
set fh [open $xdc_file w]
puts $fh {## Nexys 4 DDR — Artix-7 XC7A100T-1CSG324C
## 100 MHz single-ended system clock (Pin E3)
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports sys_clk]
create_clock -add -name sys_clk_pin -period 10.000 \
             -waveform {0.000 5.000} [get_ports sys_clk]
## USB-UART — BD exports as UART_rxd / UART_txd after make_bd_intf_pins_external
set_property -dict { PACKAGE_PIN C4  IOSTANDARD LVCMOS33 } [get_ports UART_rxd]
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports UART_txd]
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

## ---- MicroBlaze ----------------------------------------------------------
puts "INFO: Adding MicroBlaze..."
create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze:11.0 microblaze_0

apply_bd_automation \
    -rule xilinx.com:bd_rule:microblaze \
    -config {
        axi_intc     "0"
        axi_periph   "Enabled"
        cache        "None"
        clk          "New Clocking Wizard"
        debug_module "Debug Only"
        ecc          "None"
        local_mem    "32KB"
        preset       "None"
    } \
    [get_bd_cells microblaze_0]

## ---- Fix: Clocking Wizard differential → single-ended -------------------
## MicroBlaze automation creates CLK_IN1_D (differential) by default.
## Nexys 4 DDR uses a single-ended 100 MHz clock on pin E3.
puts "INFO: Switching clocking wizard to single-ended 100 MHz input..."
set_property CONFIG.PRIM_SOURCE Single_ended_clock_capable_pin \
    [get_bd_cells clk_wiz_1]
create_bd_port -dir I -type clk -freq_hz 100000000 sys_clk
set_property CONFIG.FREQ_HZ 100000000 [get_bd_ports sys_clk]
connect_bd_net [get_bd_pins clk_wiz_1/clk_in1] [get_bd_ports sys_clk]

## ---- AXI UART Lite -------------------------------------------------------
puts "INFO: Adding AXI UART Lite..."
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 axi_uartlite_0
set_property -dict {
    CONFIG.C_BAUDRATE   9600
    CONFIG.C_DATA_BITS  8
    CONFIG.C_USE_PARITY 0
} [get_bd_cells axi_uartlite_0]

apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config {
        Master     "/microblaze_0 (Periph)"
        Slave      "/axi_uartlite_0/S_AXI"
        Clk_master "/clk_wiz_1/clk_out1"
        Clk_slave  "Auto"
        Clk_xbar   "Auto"
        intc_ip    "Auto"
        master_apm "0"
    } \
    [get_bd_intf_pins axi_uartlite_0/S_AXI]

## ---- Custom AES IP -------------------------------------------------------
puts "INFO: Adding AES IP ($aes_vlnv)..."
create_bd_cell -type ip -vlnv $aes_vlnv myip_aes_bram_0

apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config {
        Master     "/microblaze_0 (Periph)"
        Slave      "/myip_aes_bram_0/S00_AXI"
        Clk_master "/clk_wiz_1/clk_out1"
        Clk_slave  "Auto"
        Clk_xbar   "Auto"
        intc_ip    "Auto"
        master_apm "0"
    } \
    [get_bd_intf_pins myip_aes_bram_0/S00_AXI]

## ---- Expose UART as external port ----------------------------------------
make_bd_intf_pins_external [get_bd_intf_pins axi_uartlite_0/UART]
set_property name UART [get_bd_intf_ports UART_0]

## --------------------------------------------------------------------------
## 5. Validate and save block design
## --------------------------------------------------------------------------
puts "INFO: Validating block design..."
validate_bd_design
save_bd_design
puts "INFO: Block design saved."

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
puts " Project created successfully."
puts "=========================================="
