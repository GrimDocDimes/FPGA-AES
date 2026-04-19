##==============================================================================
## run_all.tcl  —  AES-128 FPGA-AES Complete Build + Test Script
##
## Does everything in one shot:
##   1. Create Vivado project (JTAG-to-AXI block design, no MicroBlaze)
##   2. Synthesise
##   3. Implement
##   4. Generate bitstream
##   5. Program the FPGA (if connected)
##   6. Run FIPS-197 AES test vectors over JTAG
##
## Usage (from OS terminal):
##   vivado -mode batch -source /home/jhush/aesgit/scripts/run_all.tcl
##
## Usage (from Vivado Tcl Console):
##   source /home/jhush/aesgit/scripts/run_all.tcl
##==============================================================================

## ============================================================
## CONFIGURATION — edit these if your paths differ
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
set AES_BASE     0x44A00000

## Set to 0 to skip programming + JTAG test (build bitstream only)
set PROGRAM_AND_TEST 1

## ============================================================
proc banner {msg} {
    puts "\n=========================================="
    puts "  $msg"
    puts "==========================================\n"
}

## ============================================================
## STEP 1 — Create Project & Block Design
## ============================================================
banner "STEP 1: Creating Project"

## Clean up any previous failed attempt
if { [file exists $PROJECT_DIR] } {
    puts "INFO: Removing existing project at $PROJECT_DIR"
    file delete -force $PROJECT_DIR
}
file mkdir $PROJECTS_DIR

create_project $PROJECT_NAME $PROJECT_DIR -part $PART -force
set_property target_language   Verilog [current_project]
set_property simulator_language Mixed   [current_project]

## Register custom AES IP
set_property ip_repo_paths [list $IP_REPO] [current_project]
update_ip_catalog -rebuild

set aes_vlnv [lindex [get_ipdefs -filter {VLNV =~ *myip_aes_bram*}] 0]
if { $aes_vlnv eq "" } {
    error "ERROR: myip_aes_bram IP not found in: $IP_REPO"
}
puts "INFO: AES IP found: $aes_vlnv"

## Write XDC
file mkdir $CONSTRAINTS
set fh [open $XDC_FILE w]
puts $fh {## Nexys 4 DDR — AES JTAG-to-AXI Design
## 100 MHz single-ended system clock (Pin E3)
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports sys_clk]
create_clock -add -name sys_clk_pin -period 10.000 \
             -waveform {0.000 5.000} [get_ports sys_clk]
## Board configuration voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]}
close $fh

## ---- Block Design --------------------------------------------------------
create_bd_design $BD_NAME
current_bd_design $BD_NAME

## Clocking Wizard — single-ended 100 MHz → 100 MHz
puts "INFO: Adding Clocking Wizard..."
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_1
set_property -dict {
    CONFIG.PRIM_SOURCE                Single_ended_clock_capable_pin
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 100.000
    CONFIG.USE_LOCKED                 true
    CONFIG.USE_RESET                  false
} [get_bd_cells clk_wiz_1]
create_bd_port -dir I -type clk -freq_hz 100000000 sys_clk
connect_bd_net [get_bd_pins clk_wiz_1/clk_in1] [get_bd_ports sys_clk]

## Processor System Reset
puts "INFO: Adding Proc Sys Reset..."
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_clk_wiz_1_100M
connect_bd_net [get_bd_pins clk_wiz_1/clk_out1] \
               [get_bd_pins rst_clk_wiz_1_100M/slowest_sync_clk]
connect_bd_net [get_bd_pins clk_wiz_1/locked] \
               [get_bd_pins rst_clk_wiz_1_100M/dcm_locked]
## Tie ext_reset_in HIGH — keeps design out of reset permanently
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_reset
set_property CONFIG.CONST_VAL 1 [get_bd_cells const_reset]
connect_bd_net [get_bd_pins const_reset/dout] \
               [get_bd_pins rst_clk_wiz_1_100M/ext_reset_in]

## JTAG-to-AXI Master
puts "INFO: Adding JTAG-to-AXI Master..."
create_bd_cell -type ip -vlnv xilinx.com:ip:jtag_axi:1.2 jtag_axi_0
connect_bd_net [get_bd_pins jtag_axi_0/aclk]   [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net [get_bd_pins jtag_axi_0/aresetn] \
               [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]

## Custom AES IP
puts "INFO: Adding AES IP ($aes_vlnv)..."
create_bd_cell -type ip -vlnv $aes_vlnv myip_aes_bram_0
connect_bd_net [get_bd_pins myip_aes_bram_0/S00_AXI_ACLK] \
               [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net [get_bd_pins myip_aes_bram_0/S00_AXI_ARESETN] \
               [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]

## AXI Interconnect (1 master / 1 slave)
puts "INFO: Adding AXI Interconnect..."
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property CONFIG.NUM_MI 1 [get_bd_cells axi_interconnect_0]
connect_bd_net [get_bd_pins axi_interconnect_0/ACLK]        [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net [get_bd_pins axi_interconnect_0/ARESETN]     [get_bd_pins rst_clk_wiz_1_100M/interconnect_aresetn]
connect_bd_net [get_bd_pins axi_interconnect_0/S00_ACLK]    [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net [get_bd_pins axi_interconnect_0/S00_ARESETN] [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]
connect_bd_net [get_bd_pins axi_interconnect_0/M00_ACLK]    [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net [get_bd_pins axi_interconnect_0/M00_ARESETN] [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]

## Wire AXI: JTAG → Interconnect → AES
connect_bd_intf_net [get_bd_intf_pins jtag_axi_0/M_AXI]          \
                    [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] \
                    [get_bd_intf_pins myip_aes_bram_0/S00_AXI]

## Assign AES IP to fixed address 0x44A00000
puts "INFO: Assigning addresses..."
assign_bd_address
set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces jtag_axi_0/Data]]
if { $seg ne "" } {
    set_property offset 0x44A00000 $seg
    set_property range  64K        $seg
    puts "INFO: AES IP mapped at 0x44A00000"
}

## Validate and save
puts "INFO: Validating block design..."
validate_bd_design
save_bd_design

## Generate wrapper
puts "INFO: Generating output products..."
generate_target all \
    [get_files "$PROJECT_DIR/${PROJECT_NAME}.srcs/sources_1/bd/$BD_NAME/$BD_NAME.bd"]
make_wrapper \
    -files [get_files \
        "$PROJECT_DIR/${PROJECT_NAME}.srcs/sources_1/bd/$BD_NAME/$BD_NAME.bd"] \
    -top
add_files -norecurse \
    "$PROJECT_DIR/${PROJECT_NAME}.srcs/sources_1/bd/$BD_NAME/hdl/${BD_NAME}_wrapper.v"
set_property top ${BD_NAME}_wrapper [current_fileset]
update_compile_order -fileset sources_1

## Add constraints
add_files    -fileset [get_filesets constrs_1] -norecurse $XDC_FILE
import_files -fileset [get_filesets constrs_1] $XDC_FILE

puts "INFO: Project and block design created."

## ============================================================
## STEP 2 — Synthesis
## ============================================================
banner "STEP 2: Synthesis"

file mkdir "$PROJECT_DIR/reports"
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if { [get_property PROGRESS [get_runs synth_1]] != "100%" } {
    error "ERROR: Synthesis failed! Check: $PROJECT_DIR/${PROJECT_NAME}.runs/synth_1/runme.log"
}
puts "INFO: Synthesis complete."
open_run synth_1 -name synth_1
report_utilization -file "$PROJECT_DIR/reports/post_synth_utilization.rpt"

## ============================================================
## STEP 3 — Implementation
## ============================================================
banner "STEP 3: Implementation"

launch_runs impl_1 -jobs 4
wait_on_run impl_1

if { [get_property PROGRESS [get_runs impl_1]] != "100%" } {
    error "ERROR: Implementation failed! Check: $PROJECT_DIR/${PROJECT_NAME}.runs/impl_1/runme.log"
}
puts "INFO: Implementation complete."
open_run impl_1
report_timing_summary -file "$PROJECT_DIR/reports/post_route_timing.rpt"
report_utilization    -file "$PROJECT_DIR/reports/post_route_utilization.rpt"

set slack [get_property SLACK [get_timing_paths]]
if { $slack < 0 } {
    puts "WARNING: Timing not met! Slack = $slack ns"
} else {
    puts "SUCCESS: Timing met! Slack = $slack ns"
}

## ============================================================
## STEP 4 — Bitstream
## ============================================================
banner "STEP 4: Generating Bitstream"

set BIT_FILE "$PROJECT_DIR/${PROJECT_NAME}.runs/impl_1/${BD_NAME}_wrapper.bit"
open_run impl_1 -name impl_1_bit
write_bitstream -force -bin_file $BIT_FILE
puts "INFO: Bitstream written -> $BIT_FILE"

## ============================================================
## STEP 5 — Program FPGA + Run JTAG Test (if PROGRAM_AND_TEST=1)
## ============================================================
if { $PROGRAM_AND_TEST == 0 } {
    banner "Build Complete (skipped programming)"
    puts " Bitstream : $BIT_FILE"
    puts " To program: open Vivado Hardware Manager and program manually."
    puts " To test   : source /home/jhush/aesgit/scripts/run_aes_jtag.tcl"
    return
}

banner "STEP 5: Programming FPGA"

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set hw_dev [lindex [get_hw_devices] 0]
if { $hw_dev eq "" } {
    puts "WARNING: No hardware device found. Skipping programming and test."
    puts "         Connect the Nexys 4 DDR and run manually:"
    puts "           source /home/jhush/aesgit/scripts/run_aes_jtag.tcl"
} else {
    current_hw_device $hw_dev
    set_property PROGRAM.FILE $BIT_FILE [current_hw_device]
    program_hw_devices [current_hw_device]
    refresh_hw_device  [current_hw_device]
    puts "INFO: FPGA programmed successfully."

    ## ============================================================
    ## STEP 6 — AES JTAG Test
    ## ============================================================
    banner "STEP 6: Running AES JTAG Test"

    ## Helper procs
    proc aes_write {offset data} {
        global AES_BASE
        set addr [format "0x%08X" [expr {$AES_BASE + $offset}]]
        set txn [create_hw_axi_txn wr_txn [get_hw_axis hw_axi_1] \
            -type WRITE -address $addr \
            -data [format "%08X" $data] -len 1 -force]
        run_hw_axi $txn
    }
    proc aes_read {offset} {
        global AES_BASE
        set addr [format "0x%08X" [expr {$AES_BASE + $offset}]]
        set txn [create_hw_axi_txn rd_txn [get_hw_axis hw_axi_1] \
            -type READ -address $addr -len 1 -force]
        run_hw_axi $txn
        return [get_property DATA [get_hw_axi_txns rd_txn]]
    }
    proc aes_encrypt {pt3 pt2 pt1 pt0 k3 k2 k1 k0 label} {
        global AES_BASE
        puts "\n══════════════════════════════════════════"
        puts " $label"
        puts "══════════════════════════════════════════"
        puts [format "  Plaintext : %08X %08X %08X %08X" $pt3 $pt2 $pt1 $pt0]
        puts [format "  Key       : %08X %08X %08X %08X" $k3  $k2  $k1  $k0]
        aes_write 0x00 $pt0 ; aes_write 0x04 $pt1
        aes_write 0x08 $pt2 ; aes_write 0x0C $pt3
        aes_write 0x10 $k0  ; aes_write 0x14 $k1
        aes_write 0x18 $k2  ; aes_write 0x1C $k3
        set ct0 [aes_read 0x20] ; set ct1 [aes_read 0x24]
        set ct2 [aes_read 0x28] ; set ct3 [aes_read 0x2C]
        puts [format "  Ciphertext: %s %s %s %s" $ct3 $ct2 $ct1 $ct0]
        puts "══════════════════════════════════════════"
    }

    ## FIPS 197 Appendix B — expected: 3925841D 02DC09FB DC118597 196A0B32
    aes_encrypt \
        0x3243F6A8 0x885A308D 0x313198A2 0xE0370734 \
        0x2B7E1516 0x28AED2A6 0xABF71588 0x09CF4F3C \
        "Test 1 — FIPS 197 Appendix B (expect: 3925841D 02DC09FB DC118597 196A0B32)"

    ## All zeros — expected: 66E94BD4 EF8A2C3B 884CFA59 CA342B2E
    aes_encrypt \
        0x00000000 0x00000000 0x00000000 0x00000000 \
        0x00000000 0x00000000 0x00000000 0x00000000 \
        "Test 2 — All zeros (expect: 66E94BD4 EF8A2C3B 884CFA59 CA342B2E)"

    ## All-ones key — expected: A1F6258C 877D604D 7056911F 57180521
    aes_encrypt \
        0x00000000 0x00000000 0x00000000 0x00000000 \
        0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF \
        "Test 3 — All-ones key (expect: A1F6258C 877D604D 7056911F 57180521)"
}

## ============================================================
banner "ALL DONE!"
puts " Bitstream : $BIT_FILE"
puts " Reports   : $PROJECT_DIR/reports/"
puts "=========================================="
