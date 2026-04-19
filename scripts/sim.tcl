##==============================================================================
## sim.tcl
## AES-128 Behavioral Simulation using iverilog (NixOS compatible)
## XSim (Vivado's built-in simulator) fails on NixOS due to C compilation
## issues with the non-FHS dynamic linker. iverilog works cleanly.
##
## Usage:
##   cd /home/jhush/aesgit/scripts
##   source sim.tcl         <- from Vivado Tcl Console
##
##   OR without Vivado (pure iverilog):
##   cd /home/jhush/aesgit/scripts
##   tclsh sim.tcl
##
## Install iverilog on NixOS if not present:
##   nix-env -iA nixpkgs.iverilog
##   OR add to your shell.nix / nix-shell -p iverilog
##==============================================================================

set script_dir [file dirname [file normalize [info script]]]
set aes_dir    [file normalize "$script_dir/../Baseline-AES"]
set sim_out    "/tmp/aes_sim_out"

puts "=========================================="
puts " AES-128 Simulation (iverilog)"
puts "=========================================="
puts " Source dir : $aes_dir"
puts " Output     : $sim_out"
puts "=========================================="

## --------------------------------------------------------------------------
## Check iverilog is available
## --------------------------------------------------------------------------
if { [catch {exec which iverilog} iverilog_path] } {
    puts ""
    puts "ERROR: iverilog not found on PATH."
    puts ""
    puts "Install it on NixOS with ONE of:"
    puts "  nix-env -iA nixpkgs.iverilog"
    puts "  nix-shell -p iverilog"
    puts ""
    puts "Then re-open Vivado from that shell:"
    puts "  nix-shell -p iverilog --run \\"
    puts "  '/run/media/jhush/OLDTING/Xilinx/Vivado/2019.2/bin/vivado'"
    error "iverilog not found"
}
puts "INFO: iverilog found at: [string trim $iverilog_path]"

## --------------------------------------------------------------------------
## Compile with iverilog
## (testbench.v uses `include so we pass -I to set include search path)
## --------------------------------------------------------------------------
puts "INFO: Compiling..."

set compile_cmd "iverilog -g2005 -Wall -I $aes_dir -o $sim_out $aes_dir/testbench.v"
puts "CMD : $compile_cmd"

if { [catch {exec {*}[split $compile_cmd]} compile_out] } {
    puts "ERROR: Compilation failed:"
    puts $compile_out
    error "iverilog compile failed"
}

if { $compile_out ne "" } {
    puts "COMPILE OUTPUT: $compile_out"
}
puts "INFO: Compilation successful."

## --------------------------------------------------------------------------
## Run simulation with vvp
## --------------------------------------------------------------------------
puts "INFO: Running simulation..."

if { [catch {exec vvp $sim_out} sim_out_text] } {
    ## vvp exits 0 normally; catch is for actual errors
    puts "SIM ERROR: $sim_out_text"
    error "vvp simulation failed"
}

puts ""
puts "=========================================="
puts " SIMULATION OUTPUT:"
puts "=========================================="
puts $sim_out_text
puts "=========================================="
puts ""
puts " Input     : 4142434445464748494a4b4c4d4e4f43"
puts " Key       : 000102030405060708090a0b0c0d0e0f"
puts " Verify at : http://testprotect.com/appendix/AEScalc"
puts "=========================================="
