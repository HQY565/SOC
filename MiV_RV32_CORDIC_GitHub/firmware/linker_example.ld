/* Adapted from the linker configuration supplied for this project.
 * EXAMPLE, not an automatic replacement for the original SoftConsole file.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY
{
    ram   (rwx) : ORIGIN = 0x60000000, LENGTH = 8K
    ram_b (rw)  : ORIGIN = 0x60020000, LENGTH = 8K
}
_STACK_RESERVE = 512;
SECTIONS {
    .text : { *(.init) *(.text*) *(.rodata*) *(.srodata*) } > ram
    .data : { *(.data*) *(.sdata*) } > ram
    .bss  : { *(.bss*)  *(.sbss*) } > ram
    .mailbox (NOLOAD) : {
        . = ALIGN(4);
        _ALIVE_FLAG = .; . += 4;
        _CORDIC_START_FLAG = .; . += 4;
        _CORDIC_DONE_FLAG = .; . += 4;
        _IN_BUF = .; . += 1024;
        _CYCLES = .; . += 4;
        _INSTRET = .; . += 4;
        _TEST_R3 = .; . += 4;
        . = ALIGN(4);
        _mailbox_end = .;
    } > ram
    .conv_out (NOLOAD) : {
        . = ALIGN(4);
        _EXP_OUT = .; . += 2048;
    } > ram_b
    _stack_top = ORIGIN(ram) + LENGTH(ram) - 16;
    ASSERT(_mailbox_end + _STACK_RESERVE <= _stack_top, "ERROR: SRAM Overflow")
}
