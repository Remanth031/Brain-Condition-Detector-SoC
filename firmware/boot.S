/* ==============================================================================
 * Brain Condition Detector (BCD) SoC - RISC-V RV32IMC Bootloader Startup Code
 * Architecture: RV32IMC (Western Digital / CHIPS Alliance VeeR EL2)
 * Address: 0x0000_0000 (Boot ROM Entry Point)
 * ============================================================================== */

    .section .text.boot, "ax", @progbits
    .global _start
    .global _reset_handler
    .global trap_handler
    .global isr_dispatch

_start:
    /* 0x0000_0000: BCD Magic Header & Vector Table */
    .word 0x62636431         /* 0x00: ASCII "bcd1" Magic Identifier */
    j     _reset_handler     /* 0x04: Reset vector jump to initialization */
    nop                      /* 0x08: Pipeline align */
    .word 0xCAFEBABE         /* 0x0C: Boot Integrity Tag */

_reset_handler:
    /* Initialize Machine Status: Disable interrupts during boot */
    csrci mstatus, 8

    /* Initialize Stack Pointer sp = 0x1008_0000 (Top of SRAM Ring Buffer) */
    lui   sp, 0x10080
    addi  sp, sp, -4

    /* Initialize Global Pointer gp */
    .option push
    .option norelax
    la    gp, __global_pointer$
    .option pop

    /* Set Machine Trap-Vector Base-Address Register (mtvec) */
    la    t0, trap_handler
    csrw  mtvec, t0

    /* Zero out BSS section */
    la    t0, __bss_start
    la    t1, __bss_end
.L_clear_bss_loop:
    bge   t0, t1, .L_clear_bss_done
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     .L_clear_bss_loop
.L_clear_bss_done:

    /* Enable Global Machine Interrupts (mstatus.MIE = 1) */
    csrsi mstatus, 8

    /* Jump to C Firmware Entry Point */
    call  main

    /* Fallback Sleep / Event Loop */
.L_park_loop:
    wfi
    j     .L_park_loop

/* ==============================================================================
 * Machine Trap & Interrupt Dispatcher
 * ============================================================================== */
    .align 4
trap_handler:
    /* Allocate trap frame on stack (16 words = 64 bytes) */
    addi  sp, sp, -64
    sw    ra,  0(sp)
    sw    t0,  4(sp)
    sw    t1,  8(sp)
    sw    t2, 12(sp)
    sw    a0, 16(sp)
    sw    a1, 20(sp)
    sw    a2, 24(sp)
    sw    a3, 28(sp)

    /* Read trap cause and trap value */
    csrr  a0, mcause
    csrr  a1, mepc
    csrr  a2, mtval

    /* Call C interrupt handler: void isr_dispatch(uint32_t mcause, uint32_t mepc, uint32_t mtval) */
    call  isr_dispatch

    /* Restore registers from trap frame */
    lw    ra,  0(sp)
    lw    t0,  4(sp)
    lw    t1,  8(sp)
    lw    t2, 12(sp)
    lw    a0, 16(sp)
    lw    a1, 20(sp)
    lw    a2, 24(sp)
    lw    a3, 28(sp)
    addi  sp, sp, 64

    /* Return from Machine-mode Trap */
    mret
