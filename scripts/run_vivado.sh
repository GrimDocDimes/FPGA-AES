#!/usr/bin/env bash
# =============================================================================
# run_vivado.sh  —  NixOS-safe Vivado launcher
#
# NixOS sets C_INCLUDE_PATH, LIBRARY_PATH, NIX_LDFLAGS, NIX_CFLAGS_COMPILE
# which conflict with Vivado's internal gcc (used by XSim elaboration).
# This wrapper unsets those variables before launching Vivado.
#
# Usage:
#   # Simulation:
#   bash /home/jhush/aesgit/scripts/run_vivado.sh sim
#
#   # Full build (synth + impl + bitstream):
#   bash /home/jhush/aesgit/scripts/run_vivado.sh build
# =============================================================================

VIVADO_BIN="/run/media/jhush/OLDTING/Xilinx/Vivado/2019.2/bin/vivado"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SIM_SCRIPT="$SCRIPT_DIR/sim_aes.tcl"
BUILD_SCRIPT="$SCRIPT_DIR/build_aes_bitstream.tcl"

# ---- Unset NixOS compiler env vars that break Vivado's internal gcc --------
unset C_INCLUDE_PATH
unset LIBRARY_PATH
unset NIX_LDFLAGS
unset NIX_CFLAGS_COMPILE
unset NIX_LDFLAGS_FOR_TARGET
unset NIX_CFLAGS_COMPILE_FOR_TARGET
unset PKG_CONFIG_PATH

echo "INFO: NixOS compiler env vars cleared."
echo "INFO: Vivado binary: $VIVADO_BIN"

# ---- Select mode from argument ---------------------------------------------
MODE="${1:-sim}"

case "$MODE" in
    sim)
        echo "INFO: Running SIMULATION script: $SIM_SCRIPT"
        "$VIVADO_BIN" -mode batch -source "$SIM_SCRIPT"
        ;;
    build)
        echo "INFO: Running BUILD script: $BUILD_SCRIPT"
        "$VIVADO_BIN" -mode batch -source "$BUILD_SCRIPT"
        ;;
    *)
        echo "ERROR: Unknown mode '$MODE'. Use 'sim' or 'build'."
        echo "Usage: bash run_vivado.sh [sim|build]"
        exit 1
        ;;
esac
