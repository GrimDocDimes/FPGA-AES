# =============================================================================
# sim_aes.tcl
# Behavioral Simulation of Baseline AES-128
# Target : Artix-7 (XC7A100T-1CSG324C) – Nexys 4 DDR
# Vivado : 2019.2
#
# HOW TO RUN
# ----------
#   FROM the OS terminal (bash):
#     vivado -mode batch -source /home/jhush/aesgit/scripts/sim_aes.tcl
#
#   FROM inside Vivado Tcl Console:
#     source /home/jhush/aesgit/scripts/sim_aes.tcl
#
#   !! DO NOT type 'vivado -mode batch ...' inside the Vivado Tcl console !!
# =============================================================================

# --------------------------------------------------------------------------
# 0. User-configurable paths
# --------------------------------------------------------------------------
set SCRIPT_DIR  [file dirname [file normalize [info script]]]
set AES_DIR     [file normalize "$SCRIPT_DIR/../Baseline-AES"]
set PROJ_DIR    [file normalize "$SCRIPT_DIR/../vivado_sim"]
set PROJ_NAME   "aes_sim"
set TOP_SIM     "testbench"
set PART        "xc7a100tcsg324-1"

puts "INFO: AES source directory  : $AES_DIR"
puts "INFO: Project location      : $PROJ_DIR/$PROJ_NAME"

# --------------------------------------------------------------------------
# 1. Create project
# --------------------------------------------------------------------------
create_project $PROJ_NAME $PROJ_DIR/$PROJ_NAME -part $PART -force
set_property target_language Verilog [current_project]

# --------------------------------------------------------------------------
# 2. Add ONLY testbench.v to the sim_1 fileset
#
#    IMPORTANT: testbench.v already uses `include for all RTL files.
#    Adding RTL files separately would cause "module already defined" errors.
#    Instead, set include_dirs so the simulator resolves `include paths.
# --------------------------------------------------------------------------
add_files -fileset [get_filesets sim_1] -norecurse [list $AES_DIR/testbench.v]

# Resolve relative `include paths inside testbench.v
set_property include_dirs [list $AES_DIR] [get_filesets sim_1]

# --------------------------------------------------------------------------
# 3. Set simulation top
# --------------------------------------------------------------------------
set_property top        $TOP_SIM       [get_filesets sim_1]
set_property top_lib    xil_defaultlib [get_filesets sim_1]

update_compile_order -fileset sim_1

# --------------------------------------------------------------------------
# 4. XSim options — NixOS workaround
#    Vivado already passes --mt 8 to xelab internally.
#    Use xsim.elaborate.mt_level (not xelab.more_options) to override it.
#    Setting mt_level to 0 disables multi-thread C compilation in xelab.
# --------------------------------------------------------------------------
set_property -name {xsim.elaborate.mt_level} \
             -value {off} \
             -objects [get_filesets sim_1]

# --------------------------------------------------------------------------
# 5. Launch behavioral simulation and run
# --------------------------------------------------------------------------
puts "INFO: Launching behavioral simulation..."
launch_simulation -simset sim_1 -mode behavioral

# testbench.v: #300 $display (encrypted output), #100 $finish -> 400ns total
run 500ns

puts ""
puts "======================================================================"
puts "  Simulation complete."
puts "  Look for the line in the Tcl console output:"
puts "    Encrypted value: <hex_cipher_text>"
puts ""
puts "  Input key  : 000102030405060708090a0b0c0d0e0f"
puts "  Plain text : 4142434445464748494a4b4c4d4e4f43"
puts "  Verify at  : http://testprotect.com/appendix/AEScalc"
puts "======================================================================"
