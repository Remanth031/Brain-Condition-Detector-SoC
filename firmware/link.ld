/* ==============================================================================
 * Brain Condition Detector (BCD) SoC - Linker Script
 * Target: RV32IMC (Western Digital / CHIPS Alliance VeeR EL2)
 * Memory Map: Boot ROM (0x0000_0000, 64K), SRAM (0x1000_0000, 1M)
 * ============================================================================== */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    ROM  (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    SRAM (rwx) : ORIGIN = 0x10000000, LENGTH = 1M
}

SECTIONS
{
    /* 1. Boot Code & Reset Vector at 0x0000_0000 */
    .text.boot :
    {
        KEEP(*(.text.boot))
    } > ROM

    /* 2. Program Code */
    .text :
    {
        . = ALIGN(4);
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
        . = ALIGN(4);
        _etext = .;
    } > ROM

    /* 3. Initialized Data (Stored in ROM, relocated to SRAM at boot) */
    .data : AT(_etext)
    {
        . = ALIGN(4);
        __data_start = .;
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4);
        __data_end = .;
    } > SRAM

    /* Global pointer initialization for GP-relative addressing */
    __global_pointer$ = MIN(__data_start + 0x800, __data_end);

    /* 4. Uninitialized Data (Zeroed by startup code) */
    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > SRAM

    /* 5. Stack & Heap Boundaries */
    .heap (NOLOAD) :
    {
        . = ALIGN(8);
        __heap_start = .;
        . += 0x00010000; /* 64 KiB Heap */
        __heap_end = .;
    } > SRAM

    .stack (NOLOAD) :
    {
        . = ALIGN(8);
        . += 0x00010000; /* 64 KiB Stack */
        __stack_top = .;
    } > SRAM

    /* End of allocated image */
    _end = .;
}
