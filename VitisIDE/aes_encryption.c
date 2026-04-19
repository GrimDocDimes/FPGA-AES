/*
 * aes_encryption.c
 * MicroBlaze firmware for AES-128 hardware accelerator on Nexys 4 DDR
 *
 * AXI Register Map (base = XPAR_MYIP_AES_BRAM_0_S00_AXI_BASEADDR):
 *   Offset 0x00–0x0F : slv_reg0–3  → IN_DATA[127:0]  (plaintext,  byte 15..0)
 *   Offset 0x10–0x1F : slv_reg4–7  → IN_KEY[127:0]   (key,        byte 15..0)
 *   Offset 0x20–0x2F : slv_reg8–11 → OUT_DATA[127:0] (ciphertext, read-only)
 *
 * The AES core is fully combinational (11-stage pipeline clocked by S_AXI_ACLK).
 * Output is ready after a few cycles — a short delay is inserted before reading.
 *
 * Build: Vitis 2019.2+ with MicroBlaze BSP
 * UART : 9600 baud, 8N1 (connect via USB-UART on Nexys 4 DDR)
 */

#include <stdio.h>
#include "platform.h"
#include "xil_types.h"
#include "xil_io.h"
#include "xparameters.h"

/* ── AES IP base address from xparameters.h ─────────────────────────────── */
#define AES_BASE  XPAR_MYIP_AES_BRAM_0_S00_AXI_BASEADDR

/* ── Register offsets (each slv_reg is 32-bit / 4 bytes) ────────────────── */
#define REG_DATA0  (AES_BASE + 0x00)   /* plaintext  word 0 [31:0]   */
#define REG_DATA1  (AES_BASE + 0x04)   /* plaintext  word 1 [63:32]  */
#define REG_DATA2  (AES_BASE + 0x08)   /* plaintext  word 2 [95:64]  */
#define REG_DATA3  (AES_BASE + 0x0C)   /* plaintext  word 3 [127:96] */
#define REG_KEY0   (AES_BASE + 0x10)   /* key        word 0 [31:0]   */
#define REG_KEY1   (AES_BASE + 0x14)   /* key        word 1 [63:32]  */
#define REG_KEY2   (AES_BASE + 0x18)   /* key        word 2 [95:64]  */
#define REG_KEY3   (AES_BASE + 0x1C)   /* key        word 3 [127:96] */
#define REG_OUT0   (AES_BASE + 0x20)   /* ciphertext word 0 [31:0]   */
#define REG_OUT1   (AES_BASE + 0x24)   /* ciphertext word 1 [63:32]  */
#define REG_OUT2   (AES_BASE + 0x28)   /* ciphertext word 2 [95:64]  */
#define REG_OUT3   (AES_BASE + 0x2C)   /* ciphertext word 3 [127:96] */

/* ── Short busy-wait to let AES pipeline flush (~20 cycles @ 100 MHz) ───── */
static void aes_wait(void)
{
    volatile int i;
    for (i = 0; i < 100; i++) { __asm__("nop"); }
}

/* ── Print a 128-bit value as hex (4 x 32-bit words, MSB first) ─────────── */
static void print128(const char *label, u32 w3, u32 w2, u32 w1, u32 w0)
{
    xil_printf("%s: %08X %08X %08X %08X\r\n", label, w3, w2, w1, w0);
}

/* ── Run one AES-128 encryption and print result ─────────────────────────── */
static void aes_encrypt(u32 pt3, u32 pt2, u32 pt1, u32 pt0,
                        u32 k3,  u32 k2,  u32 k1,  u32 k0)
{
    /* Write plaintext */
    Xil_Out32(REG_DATA3, pt3);
    Xil_Out32(REG_DATA2, pt2);
    Xil_Out32(REG_DATA1, pt1);
    Xil_Out32(REG_DATA0, pt0);

    /* Write key */
    Xil_Out32(REG_KEY3, k3);
    Xil_Out32(REG_KEY2, k2);
    Xil_Out32(REG_KEY1, k1);
    Xil_Out32(REG_KEY0, k0);

    /* Wait for pipeline */
    aes_wait();

    /* Read ciphertext */
    u32 ct0 = Xil_In32(REG_OUT0);
    u32 ct1 = Xil_In32(REG_OUT1);
    u32 ct2 = Xil_In32(REG_OUT2);
    u32 ct3 = Xil_In32(REG_OUT3);

    print128("Plaintext ", pt3, pt2, pt1, pt0);
    print128("Key       ", k3,  k2,  k1,  k0);
    print128("Ciphertext", ct3, ct2, ct1, ct0);
    xil_printf("--\r\n");
}

/* ── Main ────────────────────────────────────────────────────────────────── */
int main(void)
{
    init_platform();

    xil_printf("\r\n==========================================\r\n");
    xil_printf(" AES-128 Hardware Accelerator — Nexys 4 DDR\r\n");
    xil_printf("==========================================\r\n\r\n");

    /*
     * FIPS 197 Appendix B test vector
     *   Plaintext : 3243F6A8 885A308D 313198A2 E0370734
     *   Key       : 2B7E1516 28AED2A6 ABF71588 09CF4F3C
     *   Expected  : 3925841D 02DC09FB DC118597 196A0B32
     */
    xil_printf("Test 1 — FIPS 197 Appendix B:\r\n");
    aes_encrypt(
        0x3243F6A8, 0x885A308D, 0x313198A2, 0xE0370734,  /* plaintext */
        0x2B7E1516, 0x28AED2A6, 0xABF71588, 0x09CF4F3C   /* key       */
    );

    /*
     * All-zeros test vector
     *   Plaintext : 00000000 00000000 00000000 00000000
     *   Key       : 00000000 00000000 00000000 00000000
     *   Expected  : 66E94BD4 EF8A2C3B 884CFA59 CA342B2E
     */
    xil_printf("Test 2 — All zeros:\r\n");
    aes_encrypt(
        0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000
    );

    xil_printf("==========================================\r\n");
    xil_printf(" Done. Connect at 9600 baud to see output.\r\n");
    xil_printf("==========================================\r\n");

    cleanup_platform();
    return 0;
}
