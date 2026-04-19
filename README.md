# FPGA-AES: AES-128 Hardware Accelerator on Nexys 4 DDR

An FPGA implementation of AES-128 encryption on the **Digilent Nexys 4 DDR** (Artix-7 XC7A100T), controlled directly over **JTAG-to-AXI** — no MicroBlaze, no Vitis, no firmware required.

Verified against **FIPS 197 Appendix B** and **NIST known-answer test vectors**.

---

## Table of Contents

- [Overview](#overview)
- [Hardware](#hardware)
- [Project Structure](#project-structure)
- [AES Algorithm](#aes-algorithm)
- [Block Design](#block-design)
- [AXI Register Map](#axi-register-map)
- [Build Instructions](#build-instructions)
- [Testing on FPGA via JTAG](#testing-on-fpga-via-jtag)
- [Verification Results](#verification-results)
- [Avalanche Effect Analysis](#avalanche-effect-analysis)
- [Performance Summary](#performance-summary)

---

## Overview

This project implements the **AES-128 encryption algorithm** entirely in hardware (Verilog RTL) and exposes it as an **AXI4-Lite slave peripheral**. A **JTAG-to-AXI Master** IP bridges Vivado's Hardware Manager TCL console directly to the AES registers over the JTAG cable — no CPU, no SDK, no operating system on the FPGA.

```
Vivado TCL Console
       │  JTAG (USB-PROG port)
       ▼
┌─────────────────────────────────────────────┐
│  FPGA (Artix-7 XC7A100T)                   │
│                                             │
│  sys_clk ──► clk_wiz_1 (100 MHz)           │
│                   │                         │
│             proc_sys_reset                  │
│                   │                         │
│  jtag_axi_0 ──► axi_interconnect ──► AES IP│
│  (JTAG Master)                   (AXI Slave)│
└─────────────────────────────────────────────┘
```

---

## Hardware

| Item | Specification |
|---|---|
| Board | Digilent Nexys 4 DDR |
| FPGA | Artix-7 XC7A100T-1CSG324C |
| Clock | 100 MHz (single-ended, Pin E3) |
| AES Interface | AXI4-Lite (32-bit data, 32-bit address) |
| Control Method | JTAG-to-AXI via Vivado Hardware Manager |
| Vivado Version | 2019.2 |

---

## Project Structure

```
FPGA-AES/
│
├── ip_repo/
│   └── myip_aes_bram_1.0/          # Custom AES AXI IP
│       ├── hdl/
│       │   ├── myip_aes_bram_v1_0.v          # Top AXI wrapper
│       │   └── myip_aes_bram_v1_0_S00_AXI.v  # AXI slave + AES instantiation
│       └── src/
│           ├── aes_top.v             # AES128 top module
│           ├── round_iteration.v     # 10 AES round pipeline
│           ├── generate_key.v        # Key expansion
│           ├── sub_bytes.v           # SubBytes (S-box)
│           ├── shift_rows.v          # ShiftRows
│           ├── mix_columns.v         # MixColumns (GF(2⁸))
│           ├── last_round.v          # Final round (no MixColumns)
│           └── forward_substitution_box.v  # S-box BRAM LUT
│
├── constraints/
│   └── nexys4_ddr_jtag.xdc          # XDC (sys_clk only — no UART needed)
│
├── scripts/
│   ├── run_all.tcl    # ⭐ Single script: create project + synth + impl + bitstream + program + test
│   ├── sim.tcl        # Vivado behavioral simulation
│   └── sim_aes.tcl    # AES-specific simulation
│
├── export/
│   └── aes_system.xsa               # Hardware platform (for Vitis if needed)
│
├── Baseline-AES/                    # Original AES Verilog + testbench
├── Modified-AES-V1/                 # Modified AES variant 1 (key schedule mod)
├── Modified-AES-V2/                 # Modified AES variant 2 (SubBytes mod)
├── Hamming_Data/                    # Avalanche effect analysis data
└── VitisIDE/
    └── aes_encryption.c             # MicroBlaze C firmware (alternative flow)
```

---

## AES Algorithm

AES-128 encrypts 128-bit blocks using a 128-bit key in **10 rounds**, each comprising:

| Step | Operation |
|---|---|
| **SubBytes** | Non-linear byte substitution via S-box (BRAM) |
| **ShiftRows** | Cyclic row shifts (0, 1, 2, 3 positions) |
| **MixColumns** | Column mixing in GF(2⁸) (skipped in round 10) |
| **AddRoundKey** | XOR with round-derived subkey |

The S-box is implemented in **Block RAM** (not LUTs) to achieve a critical path of ~7 ns at 100 MHz.

---

## Block Design

```
sys_clk (100 MHz, Pin E3)
    │
    ▼
clk_wiz_1 ──────────────────────────────────────────────────┐
    │ clk_out1 (100 MHz)                                     │
    │                                                        │
    ├──► rst_clk_wiz_1_100M                                  │
    │       │ peripheral_aresetn                             │
    │       │ interconnect_aresetn                           │
    │       │                                                │
    ├──► jtag_axi_0 (JTAG-to-AXI Master)                   │
    │       │ M_AXI                                          │
    │       ▼                                                │
    ├──► axi_interconnect_0 (1M × 1S)                       │
    │       │ M00_AXI                                        │
    │       ▼                                                │
    └──► myip_aes_bram_0 (S00_AXI @ 0x44A00000)            │
              │                                              │
              └─── AES128 core ◄──────────────────────────-─┘
                   (slv_reg0–11)
```

---

## AXI Register Map

Base address: **`0x44A00000`**

| Offset | Register | Direction | Description |
|---|---|---|---|
| `0x00` | slv_reg0 | Write | Plaintext word 0 `[31:0]` |
| `0x04` | slv_reg1 | Write | Plaintext word 1 `[63:32]` |
| `0x08` | slv_reg2 | Write | Plaintext word 2 `[95:64]` |
| `0x0C` | slv_reg3 | Write | Plaintext word 3 `[127:96]` |
| `0x10` | slv_reg4 | Write | Key word 0 `[31:0]` |
| `0x14` | slv_reg5 | Write | Key word 1 `[63:32]` |
| `0x18` | slv_reg6 | Write | Key word 2 `[95:64]` |
| `0x1C` | slv_reg7 | Write | Key word 3 `[127:96]` |
| `0x20` | slv_reg8 | Read | Ciphertext word 0 `[31:0]` |
| `0x24` | slv_reg9 | Read | Ciphertext word 1 `[63:32]` |
| `0x28` | slv_reg10 | Read | Ciphertext word 2 `[95:64]` |
| `0x2C` | slv_reg11 | Read | Ciphertext word 3 `[127:96]` |

The AES core is fully **combinational/pipelined** — ciphertext is available immediately after writing inputs (no start/done handshake needed).

---

## Build Instructions

### Prerequisites
- Vivado 2019.2 (only — no Vitis, no SDK, no firmware needed)
- Nexys 4 DDR connected via USB-PROG (JTAG)

### One command does everything:

```bash
vivado -mode batch -source /path/to/FPGA-AES/scripts/run_all.tcl
```

`run_all.tcl` does all of this automatically:

| Step | Action |
|---|---|
| 1 | Creates Vivado project + JTAG-to-AXI block design |
| 2 | Runs Synthesis |
| 3 | Runs Implementation |
| 4 | Generates Bitstream |
| 5 | Programs the FPGA (if connected) |
| 6 | Runs FIPS-197 AES test vectors over JTAG |

### Build bitstream only (no FPGA needed)

Edit `run_all.tcl` line 18:
```tcl
set PROGRAM_AND_TEST 0
```
Then run the same command. Bitstream will be at:
```
vivado_projects/aes_nexys4_jtag/aes_nexys4_jtag.runs/impl_1/aes_jtag_system_wrapper.bit
```

### Program manually afterwards

Open Vivado → Hardware Manager → Auto Connect → Program Device → select the `.bit` file above.

Then in the **Vivado Tcl Console**, run any custom AES encryption:

```tcl
# Write plaintext words (LSB first)
create_hw_axi_txn w0 [get_hw_axis hw_axi_1] -type WRITE -address 0x44A00000 -data E0370734 -len 1 -force
run_hw_axi w0
# ... repeat for other words, then read back:
create_hw_axi_txn r0 [get_hw_axis hw_axi_1] -type READ -address 0x44A00020 -len 1 -force
run_hw_axi r0
get_property DATA [get_hw_axi_txns r0]
```

---

## Verification Results

All three test vectors verified on hardware:

### Test 1 — FIPS 197 Appendix B

| | Value |
|---|---|
| **Plaintext** | `3243F6A8 885A308D 313198A2 E0370734` |
| **Key** | `2B7E1516 28AED2A6 ABF71588 09CF4F3C` |
| **Expected** | `3925841D 02DC09FB DC118597 196A0B32` |
| **Hardware** | ✅ `3925841D 02DC09FB DC118597 196A0B32` |

### Test 2 — All zeros

| | Value |
|---|---|
| **Plaintext** | `00000000 00000000 00000000 00000000` |
| **Key** | `00000000 00000000 00000000 00000000` |
| **Expected** | `66E94BD4 EF8A2C3B 884CFA59 CA342B2E` |
| **Hardware** | ✅ Verified |

### Test 3 — All-ones key

| | Value |
|---|---|
| **Plaintext** | `00000000 00000000 00000000 00000000` |
| **Key** | `FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF` |
| **Expected** | `A1F6258C 877D604D 7056911F 57180521` |
| **Hardware** | ✅ Verified |

---

## Avalanche Effect Analysis

Three AES variants were implemented and compared for the avalanche effect (sensitivity to input bit flips):

| Method | Average Avalanche Effect |
|:---:|:---:|
| Baseline AES | 63.94 % |
| Modified AES V1 | 64.20 % |
| Modified AES V2 | 63.99 % |

**Modified AES V1** (modified key schedule + cipher round) shows the most improvement in avalanche effect over baseline.

---

## Performance Summary

| Metric | Value |
|---|---|
| Clock frequency | 100 MHz |
| Timing slack | +1.1 ns (timing met) |
| LUT utilization | ~3% of XC7A100T |
| BRAM utilization | S-box stored in BRAM |
| Encryption latency | Combinational (single-cycle read after write) |
| Interface | AXI4-Lite, 32-bit |

---

## References

1. FIPS 197 — AES Standard: https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.197.pdf
2. Modified AES V1: https://www.researchgate.net/publication/332557093
3. Modified AES V2: https://pdfs.semanticscholar.org/7ee8/572e5457eb6bc043ecbefc933dda52f98875.pdf
4. Online AES Calculator: http://testprotect.com/appendix/AEScalc
