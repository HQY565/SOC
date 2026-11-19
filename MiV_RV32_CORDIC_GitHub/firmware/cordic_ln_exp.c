#include <stdint.h>

/* Minimal bare-metal integration demo. Compile with the project's
 * RISC-V GCC, original Mi-V RTL, and a linker script for 0x60000000.
 * Firmware is for the two fixed demonstration inputs only.
 */

void __attribute__((naked, section(".init"))) _start(void)
{
    __asm__ volatile (
        "la sp, _stack_top\n\t"
        "j main\n\t"
    );
}

/* CUSTOM-0 opcode=0x0B, funct3=0x5, funct7=0x03. */
#define CORDIC_END(rd, rs1, rs2) \
    __asm__ volatile ( \
        ".insn r 0x0B, 0x5, 0x03, %0, %1, %2\n\t" \
        : "=r"(rd) : "r"(rs1), "r"(rs2) : "memory" \
    )

/* atanH(2^-i) in Q12 for i=1..12, rounded as in the test program. */
static const int32_t lut_h[12] = {
    2250, 1046, 515, 256, 128, 64,
    32, 16, 8, 4, 2, 1
};

static void hw_step(int32_t *x, int32_t *y, uint32_t dir, uint32_t shift)
{
    uint32_t rs1 = ((uint32_t)(uint16_t)(*x) << 16) | (uint16_t)(*y);
    uint32_t rs2 = (dir << 31) | (shift << 24);
    uint32_t rd;
    CORDIC_END(rd, rs1, rs2);
    *x = (int16_t)(rd >> 16);
    *y = (int16_t)(rd & 0xFFFFu);
}

/* Hyperbolic vectoring: ln(1.5) = 2 * atanh(0.2). */
static int32_t test_ln_hw(void)
{
    int32_t x = 10240;  /* Q12: 1.5 + 1 = 2.5 */
    int32_t y = 2048;   /* Q12: 1.5 - 1 = 0.5 */
    int32_t z = 0;

    for (int i = 1; i <= 12; ++i) {
        int reps = (i == 4) ? 2 : 1;
        for (int r = 0; r < reps; ++r) {
            uint32_t dir = (y >= 0) ? 1u : 0u;
            hw_step(&x, &y, dir, (uint32_t)i);
            z += dir ? lut_h[i - 1] : -lut_h[i - 1];
        }
    }
    return 2 * z;
}

/* Hyperbolic rotation with range reduction: exp(1)=2*exp(1-ln(2)). */
static int32_t test_exp_hw(void)
{
    int32_t x = 4946; /* compensation for hyperbolic CORDIC gain, Q12 */
    int32_t y = 0;
    int32_t z = 4096 - 2839;

    for (int i = 1; i <= 12; ++i) {
        int reps = (i == 4) ? 2 : 1;
        for (int r = 0; r < reps; ++r) {
            uint32_t positive = (z >= 0) ? 1u : 0u;
            uint32_t dir = positive ? 0u : 1u;
            hw_step(&x, &y, dir, (uint32_t)i);
            z -= positive ? lut_h[i - 1] : -lut_h[i - 1];
        }
    }
    return (x + y) * 2;
}

int main(void)
{
    volatile uint32_t *ln_result  = (volatile uint32_t *)0x60001000u;
    volatile uint32_t *exp_result = (volatile uint32_t *)0x60001004u;
    volatile uint32_t *done       = (volatile uint32_t *)0x60001008u;

    *done = 0u;
    *ln_result = (uint32_t)test_ln_hw();
    *exp_result = (uint32_t)test_exp_hw();
    *done = 0xC0DE0002u;

    for (;;) {
        __asm__ volatile ("nop");
    }
}
