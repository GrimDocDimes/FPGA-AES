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
##
## AXI Register Map (base = 0x44A00000):
##   0x00  slv_reg0  IN_DATA[31:0]    plaintext  word 0
##   0x04  slv_reg1  IN_DATA[63:32]   plaintext  word 1
##   0x08  slv_reg2  IN_DATA[95:64]   plaintext  word 2
##   0x0C  slv_reg3  IN_DATA[127:96]  plaintext  word 3
##   0x10  slv_reg4  IN_KEY[31:0]     key        word 0
##   0x14  slv_reg5  IN_KEY[63:32]    key        word 1
##   0x18  slv_reg6  IN_KEY[95:64]    key        word 2
##   0x1C  slv_reg7  IN_KEY[127:96]   key        word 3
##   0x20  slv_reg8  OUT_DATA[31:0]   ciphertext word 0 (read-only)
##   0x24  slv_reg9  OUT_DATA[63:32]  ciphertext word 1 (read-only)
##   0x28  slv_reg10 OUT_DATA[95:64]  ciphertext word 2 (read-only)
##   0x2C  slv_reg11 OUT_DATA[127:96] ciphertext word 3 (read-only)
##==============================================================================

set AES_BASE 0x44A00000

## ── Helper: write a 32-bit word to an AES register ─────────────────────────
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

## ── Helper: read a 32-bit word from an AES register ─────────────────────────
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

## ── Encrypt: write plaintext + key, read ciphertext ─────────────────────────
proc aes_encrypt {pt3 pt2 pt1 pt0  k3 k2 k1 k0  label} {
    puts "\n══════════════════════════════════════════"
    puts " $label"
    puts "══════════════════════════════════════════"
    puts [format "  Plaintext : %08X %08X %08X %08X" $pt3 $pt2 $pt1 $pt0]
    puts [format "  Key       : %08X %08X %08X %08X" $k3  $k2  $k1  $k0]

    ## Write plaintext (word 3 = MSB at offset 0x0C, word 0 = LSB at 0x00)
    aes_write 0x00 $pt0
    aes_write 0x04 $pt1
    aes_write 0x08 $pt2
    aes_write 0x0C $pt3

    ## Write key
    aes_write 0x10 $k0
    aes_write 0x14 $k1
    aes_write 0x18 $k2
    aes_write 0x1C $k3

    ## The AES core is combinational — read back immediately
    set ct0 [aes_read 0x20]
    set ct1 [aes_read 0x24]
    set ct2 [aes_read 0x28]
    set ct3 [aes_read 0x2C]

    puts [format "  Ciphertext: %s %s %s %s" $ct3 $ct2 $ct1 $ct0]
    puts "══════════════════════════════════════════\n"
}

## ═══════════════════════════════════════════════════════════════════════════
## Run test vectors
## ═══════════════════════════════════════════════════════════════════════════

puts "\n######################################"
puts "  AES-128 JTAG-to-AXI Test"
puts "######################################"

## ── Test 1: FIPS 197 Appendix B ────────────────────────────────────────────
## Plaintext : 3243F6A8 885A308D 313198A2 E0370734
## Key       : 2B7E1516 28AED2A6 ABF71588 09CF4F3C
## Expected  : 3925841D 02DC09FB DC118597 196A0B32
aes_encrypt \
    0x3243F6A8 0x885A308D 0x313198A2 0xE0370734 \
    0x2B7E1516 0x28AED2A6 0xABF71588 0x09CF4F3C \
    "Test 1 — FIPS 197 Appendix B"

## ── Test 2: All zeros ───────────────────────────────────────────────────────
## Plaintext : 00000000 00000000 00000000 00000000
## Key       : 00000000 00000000 00000000 00000000
## Expected  : 66E94BD4 EF8A2C3B 884CFA59 CA342B2E
aes_encrypt \
    0x00000000 0x00000000 0x00000000 0x00000000 \
    0x00000000 0x00000000 0x00000000 0x00000000 \
    "Test 2 — All zeros"

## ── Test 3: NIST AES-128 Known Answer Test ─────────────────────────────────
## Plaintext : 00000000 00000000 00000000 00000000
## Key       : FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF
## Expected  : A1F6258C 877D604D 7056911F 57180521
aes_encrypt \
    0x00000000 0x00000000 0x00000000 0x00000000 \
    0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF \
    "Test 3 — All-ones key"

puts "######################################"
puts "  Done. Compare output with Expected"
puts "  values above to verify correctness."
puts "######################################\n"
