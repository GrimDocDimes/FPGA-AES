# =============================================================================
# build_aes_bitstream.tcl
# Full Vivado Build: Project → IP → Block Design → Synth → Impl → Bitstream
# Target : Artix-7 (XC7A100T-1CSG324C) – Nexys 4 DDR
# Vivado : 2019.2
#
# HOW TO RUN
# ----------
#   FROM the OS terminal (bash):
#     vivado -mode batch -source /home/jhush/aesgit/scripts/build_aes_bitstream.tcl
#
#   FROM inside Vivado Tcl Console:
#     source /home/jhush/aesgit/scripts/build_aes_bitstream.tcl
#
#   !! DO NOT type 'vivado -mode batch ...' inside the Vivado Tcl console !!
#
# NOTE: XCounter HLS IP (cycle counter) must be exported from Vitis HLS first.
#       Set XCOUNTER_READY 1 once that IP is available in ip_repo/.
#       Set XCOUNTER_READY 0 (default) to skip it and still get a working AES.
# =============================================================================

# --------------------------------------------------------------------------
# 0. User-configurable settings — edit these if needed
# --------------------------------------------------------------------------
set SCRIPT_DIR       [file dirname [file normalize [info script]]]
set REPO_ROOT        [file normalize "$SCRIPT_DIR/.."]

set PROJ_NAME        "aes_nexys4"
set PROJ_DIR         [file normalize "$REPO_ROOT/../vivado_projects/$PROJ_NAME"]
set BD_NAME          "aes_system"
set PART             "xc7a100tcsg324-1"
set XCOUNTER_READY   0

set IP_REPO_DIR      [file normalize "$REPO_ROOT/ip_repo"]
set CONSTRAINTS_DIR  [file normalize "$REPO_ROOT/constraints"]
set XDC_FILE         "$CONSTRAINTS_DIR/nexys4_ddr_aes.xdc"
set REPORTS_DIR      "$PROJ_DIR/reports"

puts "INFO: ============================================================="
puts "INFO:  AES FPGA Build Script  |  Vivado 2019.2"
puts "INFO:  Project    : $PROJ_DIR"
puts "INFO:  Part       : $PART"
puts "INFO:  IP Repo    : $IP_REPO_DIR"
puts "INFO: ============================================================="

# --------------------------------------------------------------------------
# 1. Create Vivado project
# --------------------------------------------------------------------------
create_project $PROJ_NAME $PROJ_DIR -part $PART -force
set_property target_language   Verilog [current_project]
set_property simulator_language Mixed   [current_project]

# --------------------------------------------------------------------------
# 2. Register custom IP repository and refresh catalog
# --------------------------------------------------------------------------
set_property ip_repo_paths [list $IP_REPO_DIR] [current_project]
update_ip_catalog -rebuild

# Verify the AES IP is visible
set aes_vlnv [lindex [get_ipdefs -filter {VLNV =~ *myip_aes_bram*}] 0]
if { $aes_vlnv eq "" } {
    error "ERROR: myip_aes_bram IP not found!\
           Check that ip_repo/ exists at: $IP_REPO_DIR"
}
puts "INFO: Found AES IP: $aes_vlnv"

# --------------------------------------------------------------------------
# 3. Create minimal XDC constraints for Nexys 4 DDR
# --------------------------------------------------------------------------
file mkdir $CONSTRAINTS_DIR

set xdc_fh [open $XDC_FILE w]
puts $xdc_fh {## ============================================================
## nexys4_ddr_aes.xdc  — Nexys 4 DDR  |  Artix-7 XC7A100T-1CSG324C
## ============================================================

## 100 MHz system clock on pin E3
set_property -dict { PACKAGE_PIN E3   IOSTANDARD LVCMOS33 } [get_ports sys_clk]
create_clock -add -name sys_clk_pin \
             -period 10.000 -waveform {0.000 5.000} [get_ports sys_clk]

## USB-UART (virtual COM over micro-USB JTAG cable)
set_property -dict { PACKAGE_PIN C4   IOSTANDARD LVCMOS33 } [get_ports usb_uart_rxd]
set_property -dict { PACKAGE_PIN D4   IOSTANDARD LVCMOS33 } [get_ports usb_uart_txd]
}
close $xdc_fh
puts "INFO: XDC written to $XDC_FILE"

# --------------------------------------------------------------------------
# 4. Create Block Design
# --------------------------------------------------------------------------
create_bd_design $BD_NAME
current_bd_design $BD_NAME

# ---- 4a. MicroBlaze -------------------------------------------------------
puts "INFO: Adding MicroBlaze..."
create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze:11.0 microblaze_0

apply_bd_automation \
    -rule xilinx.com:bd_rule:microblaze \
    -config {
        axi_intc        "0"
        axi_periph      "Enabled"
        cache           "None"
        clk             "New Clocking Wizard"
        debug_module    "Debug Only"
        ecc             "None"
        local_mem       "32KB"
        preset          "None"
    } \
    [get_bd_cells microblaze_0]

# ---- Fix: Switch Clocking Wizard from Differential to Single-Ended --------
# MicroBlaze automation defaults to differential clock input (CLK_IN1_D).
# Nexys 4 DDR provides a single-ended 100 MHz clock on pin E3.
puts "INFO: Configuring clocking wizard for single-ended 100 MHz input..."

set_property CONFIG.PRIM_SOURCE Single_ended_clock_capable_pin \
    [get_bd_cells clk_wiz_1]

# Create a single-ended board clock input port and connect to wizard
create_bd_port -dir I -type clk -freq_hz 100000000 sys_clk
set_property CONFIG.FREQ_HZ 100000000 [get_bd_ports sys_clk]
connect_bd_net [get_bd_pins clk_wiz_1/clk_in1] [get_bd_ports sys_clk]
puts "INFO: sys_clk port connected to clk_wiz_1/clk_in1"

# After automation the clocking wizard is named clk_wiz_1 by default.
# Confirm it exists before proceeding.
if { [get_bd_cells -quiet clk_wiz_1] eq "" } {
    puts "WARNING: clk_wiz_1 not found. Using Auto clock setting for connections."
    set CLK_SRC "Auto"
} else {
    set CLK_SRC "/clk_wiz_1/clk_out1"
    puts "INFO: Clocking Wizard found: $CLK_SRC"
}

# ---- 4b. AXI UART Lite (for xil_printf / UART output) -------------------
puts "INFO: Adding AXI UART Lite (9600 baud)..."
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 axi_uartlite_0
set_property -dict [list \
    CONFIG.C_BAUDRATE   {9600}  \
    CONFIG.C_DATA_BITS  {8}     \
    CONFIG.C_USE_PARITY {0}     \
] [get_bd_cells axi_uartlite_0]

apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config [list \
        Master     "/microblaze_0 (Periph)" \
        Slave      "/axi_uartlite_0/S_AXI"  \
        Clk_master "$CLK_SRC"               \
        Clk_slave  "Auto"                    \
        Clk_xbar   "Auto"                    \
        intc_ip    "Auto"                    \
        master_apm "0"                       \
    ] \
    [get_bd_intf_pins axi_uartlite_0/S_AXI]

# ---- 4c. Custom AES IP ---------------------------------------------------
puts "INFO: Adding AES IP: $aes_vlnv"
create_bd_cell -type ip -vlnv $aes_vlnv myip_aes_bram_0

apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config [list \
        Master     "/microblaze_0 (Periph)"        \
        Slave      "/myip_aes_bram_0/S00_AXI"      \
        Clk_master "$CLK_SRC"                      \
        Clk_slave  "Auto"                           \
        Clk_xbar   "Auto"                           \
        intc_ip    "Auto"                           \
        master_apm "0"                              \
    ] \
    [get_bd_intf_pins myip_aes_bram_0/S00_AXI]

# ---- 4d. XCounter HLS IP (optional cycle counter) ------------------------
if { $XCOUNTER_READY } {
    set xc_vlnv [lindex [get_ipdefs -filter {VLNV =~ *xcounter*}] 0]
    if { $xc_vlnv eq "" } {
        puts "WARNING: XCounter IP not found in catalog. Skipping."
    } else {
        puts "INFO: Adding XCounter IP: $xc_vlnv"
        create_bd_cell -type ip -vlnv $xc_vlnv xcounter_0
        apply_bd_automation \
            -rule xilinx.com:bd_rule:axi4 \
            -config [list \
                Master     "/microblaze_0 (Periph)"   \
                Slave      "/xcounter_0/s_axi_HLSCore" \
                Clk_master "$CLK_SRC"                  \
                Clk_slave  "Auto"                       \
                Clk_xbar   "Auto"                       \
                intc_ip    "Auto"                       \
                master_apm "0"                          \
            ] \
            [get_bd_intf_pins xcounter_0/s_axi_HLSCore]
    }
} else {
    puts "INFO: Skipping XCounter IP (XCOUNTER_READY = 0)."
}

# ---- 4e. Expose UART pins as external ports -------------------------------
make_bd_intf_pins_external [get_bd_intf_pins axi_uartlite_0/UART]
set_property name UART [get_bd_intf_ports UART_0]

# --------------------------------------------------------------------------
# 5. Validate and save block design
# --------------------------------------------------------------------------
puts "INFO: Validating block design..."
validate_bd_design
save_bd_design

# --------------------------------------------------------------------------
# 6. Generate output products and create HDL wrapper
# --------------------------------------------------------------------------
puts "INFO: Generating output products..."
generate_target all \
    [get_files [file normalize \
        "$PROJ_DIR/${PROJ_NAME}.srcs/sources_1/bd/$BD_NAME/$BD_NAME.bd"]]

puts "INFO: Creating HDL wrapper..."
make_wrapper \
    -files [get_files [file normalize \
        "$PROJ_DIR/${PROJ_NAME}.srcs/sources_1/bd/$BD_NAME/$BD_NAME.bd"]] \
    -top

add_files -norecurse \
    [file normalize \
        "$PROJ_DIR/${PROJ_NAME}.srcs/sources_1/bd/$BD_NAME/hdl/${BD_NAME}_wrapper.v"]

set_property top ${BD_NAME}_wrapper [current_fileset]
update_compile_order -fileset sources_1

# --------------------------------------------------------------------------
# 7. Add XDC constraints
# --------------------------------------------------------------------------
puts "INFO: Adding constraints file: $XDC_FILE"
add_files    -fileset [get_filesets constrs_1] -norecurse $XDC_FILE
import_files -fileset [get_filesets constrs_1] $XDC_FILE

# --------------------------------------------------------------------------
# 8. Synthesis
# --------------------------------------------------------------------------
puts "INFO: ============================================================="
puts "INFO: Running Synthesis..."
puts "INFO: ============================================================="

launch_runs synth_1 -jobs 4
wait_on_run synth_1

if { [get_property PROGRESS [get_runs synth_1]] ne "100%" } {
    error "ERROR: Synthesis FAILED.\nCheck log: $PROJ_DIR/${PROJ_NAME}.runs/synth_1/runme.log"
}
puts "INFO: Synthesis PASSED."

open_run synth_1 -name synth_1

file mkdir $REPORTS_DIR
report_timing_summary -file $REPORTS_DIR/timing_synth.rpt
report_utilization    -file $REPORTS_DIR/utilization_synth.rpt
puts "INFO: Synthesis reports written to $REPORTS_DIR/"

# --------------------------------------------------------------------------
# 9. Implementation
# --------------------------------------------------------------------------
puts "INFO: ============================================================="
puts "INFO: Running Implementation..."
puts "INFO: ============================================================="

launch_runs impl_1 -jobs 4
wait_on_run impl_1

if { [get_property PROGRESS [get_runs impl_1]] ne "100%" } {
    error "ERROR: Implementation FAILED.\nCheck log: $PROJ_DIR/${PROJ_NAME}.runs/impl_1/runme.log"
}
puts "INFO: Implementation PASSED."

open_run impl_1

report_timing_summary -file $REPORTS_DIR/timing_impl.rpt
report_utilization    -file $REPORTS_DIR/utilization_impl.rpt
report_power          -file $REPORTS_DIR/power_impl.rpt
puts "INFO: Implementation reports written to $REPORTS_DIR/"

# --------------------------------------------------------------------------
# 10. Bitstream Generation
# --------------------------------------------------------------------------
puts "INFO: ============================================================="
puts "INFO: Generating Bitstream..."
puts "INFO: ============================================================="

set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Locate the bitstream
set BIT_FILE [glob -nocomplain \
    "$PROJ_DIR/${PROJ_NAME}.runs/impl_1/${BD_NAME}_wrapper.bit"]

if { $BIT_FILE eq "" } {
    error "ERROR: Bitstream file not found after write_bitstream step."
}
puts "INFO: Bitstream generated: $BIT_FILE"

# --------------------------------------------------------------------------
# 11. Export Hardware Platform (.xsa) for Vitis IDE
# --------------------------------------------------------------------------
file mkdir "$PROJ_DIR/export"

write_hw_platform \
    -fixed      \
    -include_bit \
    -force      \
    -output     "$PROJ_DIR/export/aes_system.xsa"

puts ""
puts "======================================================================"
puts "  BUILD COMPLETE"
puts ""
puts "  Bitstream : $BIT_FILE"
puts "  XSA file  : $PROJ_DIR/export/aes_system.xsa"
puts ""
puts "  NEXT STEPS:"
puts "  1. Open Vitis IDE"
puts "  2. Create Platform Project from: $PROJ_DIR/export/aes_system.xsa"
puts "  3. Create Application Project -> Empty C"
puts "  4. Copy VitisIDE/aes_encryption.c into src/"
puts "  5. Build and Run on Nexys 4 DDR"
puts "  6. Open Serial Terminal at 9600 baud to see cipher text output"
puts "======================================================================"
