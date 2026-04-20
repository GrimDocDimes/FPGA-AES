##==============================================================================
## run_aes_jtag.tcl
## Drive the AES-128 hardware IP over JTAG using Vivado Hardware Manager.
## No firmware, no Vitis, no SDK — pure TCL.
##
## HOW TO USE:
##   1. Program the FPGA with the JTAG-design bitstream first:
##        aes_jtag_system_wrapper.bit
##   2. In Vivado Tcl Console (Hardware Manager open, device connected):
##        source /home/jhush/aesgit/scripts/run_aes_jtag.tcl
##==============================================================================

set AES_BASE 0x44A00000

proc aes_write {offset data} {
    global AES_BASE
    set addr [format "0x%08X" [expr {$AES_BASE + $offset}]]
    set txn [create_hw_axi_txn wr_txn [get_hw_axis hw_axi_1] \
        -type  WRITE        \
        -address $addr      \
        -data  [format "%08X" $data] \
        -len   1            \
        -force]
    run_hw_axi $txn
}

proc aes_read {offset} {
    global AES_BASE
    set addr [format "0x%08X" [expr {$AES_BASE + $offset}]]
    set txn [create_hw_axi_txn rd_txn [get_hw_axis hw_axi_1] \
        -type  READ         \
        -address $addr      \
        -len   1            \
        -force]
    run_hw_axi $txn
    return [get_property DATA [get_hw_axi_txns rd_txn]]
}

proc aes_encrypt {pt3 pt2 pt1 pt0  k3 k2 k1 k0  label} {
    puts "\n══════════════════════════════════════════"
    puts " $label"
    puts "══════════════════════════════════════════"
    puts [format "  Plaintext : %08X %08X %08X %08X" $pt3 $pt2 $pt1 $pt0]
    puts [format "  Key       : %08X %08X %08X %08X" $k3  $k2  $k1  $k0]

    aes_write 0x00 $pt0
    aes_write 0x04 $pt1
    aes_write 0x08 $pt2
    aes_write 0x0C $pt3

    aes_write 0x10 $k0
    aes_write 0x14 $k1
    aes_write 0x18 $k2
    aes_write 0x1C $k3

    set ct0 [aes_read 0x20]
    set ct1 [aes_read 0x24]
    set ct2 [aes_read 0x28]
    set ct3 [aes_read 0x2C]

    puts [format "  Ciphertext: %s %s %s %s" $ct3 $ct2 $ct1 $ct0]
    puts "══════════════════════════════════════════\n"
}

puts "\n######################################"
puts "  AES-128 JTAG-to-AXI Test"
puts "######################################"

aes_encrypt \
    0x3243F6A8 0x885A308D 0x313198A2 0xE0370734 \
    0x2B7E1516 0x28AED2A6 0xABF71588 0x09CF4F3C \
    "Test 1 — FIPS 197 Appendix B"

aes_encrypt \
    0x00000000 0x00000000 0x00000000 0x00000000 \
    0x00000000 0x00000000 0x00000000 0x00000000 \
    "Test 2 — All zeros"

aes_encrypt \
    0x00000000 0x00000000 0x00000000 0x00000000 \
    0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF \
    "Test 3 — All-ones key"

puts "######################################"
puts "  Done."
puts "######################################\n"
