#include <stdint.h>
// Reference SoftConsole source reconstructed from the verified MMIO workflow.
// Not asserted to be byte-identical to the original SoftConsole mivuse.c build.
#define REG32(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define INPUT_BASE  0x60010000u
#define CMD_START   0x60010080u
#define STATUS      0x60010084u
#define INVALID     0x60010088u
#define RESULT_BASE 0x60010100u
#define RAM_RESULT  0x60001000u
#define RAM_DONE    0x60001040u
#define DONE_TIMEOUT  0xBAD00001u
#define DONE_MISMATCH 0xBAD00002u
#define DONE_INVALID  0xBAD00003u
#define N 10u
void __attribute__((naked, section(".init"))) _start(void) {
    __asm__ volatile("la sp, _stack_top\n\t" "j main\n\t");
}
#define DONE_OK 0xC0DE100Au
static const uint32_t inputs[N] = {2048, 2560, 3072, 3584, 4096, 4608, 5120, 5632, 6144, 8192};
static const int32_t expected[N] = {-2839, -1925, -1178, -547, 0, 482, 914, 1304, 1661, 2839};

int main(void) {
    uint32_t s=0, mismatch=0;
    REG32(RAM_DONE)=0;
    for(uint32_t ch=0;ch<N;ch++) REG32(RAM_RESULT+4u*ch)=0;
    for(uint32_t ch=0;ch<N;ch++) REG32(INPUT_BASE+4u*ch)=(uint32_t)inputs[ch];
    REG32(CMD_START)=1;
    for(uint32_t t=0;t<1000u;t++) {
        s=REG32(STATUS);
        if((s&1u)!=0u) break;
    }
    if((s&1u)==0u) {REG32(RAM_DONE)=DONE_TIMEOUT;while(1) __asm__ volatile("nop");}
    if(REG32(INVALID)!=0u) {REG32(RAM_DONE)=DONE_INVALID;while(1) __asm__ volatile("nop");}
    for(uint32_t ch=0;ch<N;ch++) {
        int32_t actual=(int32_t)REG32(RESULT_BASE+4u*ch);
        REG32(RAM_RESULT+4u*ch)=(uint32_t)actual;
        if(actual<expected[ch]-3 || actual>expected[ch]+3) mismatch++;
    }
    REG32(RAM_DONE)= mismatch ? DONE_MISMATCH : DONE_OK;
    while(1) __asm__ volatile("nop");
}
