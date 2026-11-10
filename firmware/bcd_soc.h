// ==============================================================================
// Brain Condition Detector (BCD) SoC - Firmware Hardware Abstraction Layer
// Definitions, Memory Map, and Peripheral CSR Driver Functions
// Compatible with RV32IMC (VeeR EL2 Core)
// ==============================================================================

#ifndef BCD_SOC_H
#define BCD_SOC_H

#include <stdint.h>
#include <stdbool.h>

// -----------------------------------------------------------------------------
// 1. Memory Map
// -----------------------------------------------------------------------------
#define BCD_ROM_BASE          0x00000000U
#define BCD_ROM_SIZE          0x00010000U // 64 KiB
#define BCD_SRAM_BASE         0x10000000U
#define BCD_SRAM_SIZE         0x00100000U // 1 MiB
#define BCD_SCRATCHPAD_BASE   0x11000000U
#define BCD_SCRATCHPAD_SIZE   0x00200000U // 2 MiB
#define BCD_NVM_BASE          0x60000000U
#define BCD_NVM_SIZE          0x08000000U // 128 MiB
#define BCD_LPDDR_BASE        0x80000000U
#define BCD_LPDDR_SIZE        0x40000000U // 1 GiB

// -----------------------------------------------------------------------------
// 2. Peripheral CSR Bases (0x4000_0000 - 0x4009_0000)
// -----------------------------------------------------------------------------
#define BCD_CSR_AFE_BASE      0x40000000U
#define BCD_CSR_FILTER_BASE   0x40010000U
#define BCD_CSR_THRESH_BASE   0x40020000U
#define BCD_CSR_PMU_BASE      0x40030000U
#define BCD_CSR_DMA_BASE      0x40040000U
#define BCD_CSR_NPU_BASE      0x40050000U
#define BCD_CSR_SWIN_BASE     0x40060000U
#define BCD_CSR_OUTPUT_BASE   0x40070000U
#define BCD_CSR_SECURITY_BASE 0x40080000U
#define BCD_CSR_PERIPH_BASE   0x40090000U

// -----------------------------------------------------------------------------
// 3. RTL Threshold Engine Registers (Base 0x4002_0000)
// -----------------------------------------------------------------------------
#define THRESH_CTRL           (*(volatile uint32_t *)(BCD_CSR_THRESH_BASE + 0x00U))
#define THRESH_STATUS         (*(volatile uint32_t *)(BCD_CSR_THRESH_BASE + 0x04U))
#define THRESH_CH_MASK        (*(volatile uint32_t *)(BCD_CSR_THRESH_BASE + 0x08U))
#define THRESH_LL_THR         (*(volatile uint32_t *)(BCD_CSR_THRESH_BASE + 0x0CU))
#define THRESH_BP_RATIO_THR   (*(volatile uint32_t *)(BCD_CSR_THRESH_BASE + 0x10U))
#define THRESH_ENT_THR        (*(volatile uint32_t *)(BCD_CSR_THRESH_BASE + 0x14U))
#define THRESH_VOTE_NM        (*(volatile uint32_t *)(BCD_CSR_THRESH_BASE + 0x18U))
#define THRESH_HYST_HOLD      (*(volatile uint32_t *)(BCD_CSR_THRESH_BASE + 0x1CU))
#define THRESH_PRETRIG_LEN    (*(volatile uint32_t *)(BCD_CSR_THRESH_BASE + 0x20U))
#define THRESH_IRQ_EN         (*(volatile uint32_t *)(BCD_CSR_THRESH_BASE + 0x24U))
#define THRESH_IRQ_STATUS     (*(volatile uint32_t *)(BCD_CSR_THRESH_BASE + 0x28U))
#define THRESH_WAKE_TARGET    (*(volatile uint32_t *)(BCD_CSR_THRESH_BASE + 0x2CU))

// Bitfields for THRESH_CTRL
#define THRESH_CTRL_EN            (1U << 0)
#define THRESH_CTRL_SOFT_RESET    (1U << 1)
#define THRESH_CTRL_CALIBRATE     (1U << 2)
#define THRESH_CTRL_WINDOW_256    (0U << 4)
#define THRESH_CTRL_WINDOW_512    (1U << 4)

// Bitfields for THRESH_WAKE_TARGET
#define WAKE_TARGET_NPU           (1U << 0)
#define WAKE_TARGET_SWIN          (1U << 1)
#define WAKE_TARGET_BOTH          (1U << 2)

// -----------------------------------------------------------------------------
// 4. Edge-AI NPU Accelerator Registers (Base 0x4005_0000)
// -----------------------------------------------------------------------------
#define NPU_CTRL              (*(volatile uint32_t *)(BCD_CSR_NPU_BASE + 0x00U))
#define NPU_STATUS            (*(volatile uint32_t *)(BCD_CSR_NPU_BASE + 0x04U))
#define NPU_WEIGHT_ADDR       (*(volatile uint32_t *)(BCD_CSR_NPU_BASE + 0x08U))
#define NPU_SCRATCH_ADDR      (*(volatile uint32_t *)(BCD_CSR_NPU_BASE + 0x0CU))
#define NPU_RESULT_CLASS      (*(volatile uint32_t *)(BCD_CSR_NPU_BASE + 0x10U))
#define NPU_CONFIDENCE        (*(volatile uint32_t *)(BCD_CSR_NPU_BASE + 0x14U))
#define NPU_CYCLE_COUNT       (*(volatile uint32_t *)(BCD_CSR_NPU_BASE + 0x18U))
#define NPU_IRQ_EN            (*(volatile uint32_t *)(BCD_CSR_NPU_BASE + 0x1CU))

// Bitfields for NPU_CTRL
#define NPU_CTRL_START            (1U << 0)
#define NPU_CTRL_AUTO_DMA         (1U << 1)
#define NPU_CTRL_SOFT_RESET       (1U << 4)

// -----------------------------------------------------------------------------
// 5. Swin Transformer Accelerator Registers (Base 0x4006_0000)
// -----------------------------------------------------------------------------
#define SWIN_CTRL             (*(volatile uint32_t *)(BCD_CSR_SWIN_BASE + 0x00U))
#define SWIN_STATUS           (*(volatile uint32_t *)(BCD_CSR_SWIN_BASE + 0x04U))
#define SWIN_WEIGHT_ADDR      (*(volatile uint32_t *)(BCD_CSR_SWIN_BASE + 0x08U))
#define SWIN_TOKEN_ADDR       (*(volatile uint32_t *)(BCD_CSR_SWIN_BASE + 0x0CU))
#define SWIN_SALIENCY_ADDR    (*(volatile uint32_t *)(BCD_CSR_SWIN_BASE + 0x10U))
#define SWIN_RESULT_CLASS     (*(volatile uint32_t *)(BCD_CSR_SWIN_BASE + 0x14U))
#define SWIN_CONFIDENCE       (*(volatile uint32_t *)(BCD_CSR_SWIN_BASE + 0x18U))
#define SWIN_CYCLE_COUNT      (*(volatile uint32_t *)(BCD_CSR_SWIN_BASE + 0x1CU))
#define SWIN_IRQ_EN           (*(volatile uint32_t *)(BCD_CSR_SWIN_BASE + 0x20U))

// Bitfields for SWIN_CTRL
#define SWIN_CTRL_START           (1U << 0)
#define SWIN_CTRL_SHIFT_EN        (1U << 1)
#define SWIN_CTRL_MODALITY_EEG    (0U << 2)
#define SWIN_CTRL_MODALITY_MRI    (1U << 2)

// -----------------------------------------------------------------------------
// 6. PMU and Power Sequencer Registers (Base 0x4003_0000)
// -----------------------------------------------------------------------------
#define PMU_CTRL              (*(volatile uint32_t *)(BCD_CSR_PMU_BASE + 0x00U))
#define PMU_STATUS            (*(volatile uint32_t *)(BCD_CSR_PMU_BASE + 0x04U))
#define PMU_WAKE_MASK         (*(volatile uint32_t *)(BCD_CSR_PMU_BASE + 0x08U))

// -----------------------------------------------------------------------------
// 7. Output Fusion & Report Generator Registers (Base 0x4007_0000)
// -----------------------------------------------------------------------------
#define FUSION_CTRL           (*(volatile uint32_t *)(BCD_CSR_OUTPUT_BASE + 0x00U))
#define FUSION_STATUS         (*(volatile uint32_t *)(BCD_CSR_OUTPUT_BASE + 0x04U))
#define FUSION_CLASS_OUT      (*(volatile uint32_t *)(BCD_CSR_OUTPUT_BASE + 0x08U))
#define FUSION_CONF_OUT       (*(volatile uint32_t *)(BCD_CSR_OUTPUT_BASE + 0x0CU))

// -----------------------------------------------------------------------------
// 8. Interrupt Source IDs (VeeR PIC Vector)
// -----------------------------------------------------------------------------
#define IRQ_ID_RESERVED       0U
#define IRQ_ID_THRESHOLD      1U
#define IRQ_ID_DMA_DONE       2U
#define IRQ_ID_PMU_EVENT      3U
#define IRQ_ID_FIREWALL       4U
#define IRQ_ID_NPU_DONE       5U
#define IRQ_ID_SWIN_DONE      6U
#define IRQ_ID_REPORT_READY   7U

// Diagnostic Class Codes
typedef enum {
    CLASS_NORMAL           = 0,
    CLASS_EPILEPTIC_SEIZURE= 1,
    CLASS_SLEEP_SPINDLE    = 2,
    CLASS_ENCEPHALOPATHY   = 3,
    CLASS_MOTION_ARTIFACT  = 4
} bcd_clinical_class_t;

// Inline Helpers
static inline void bcd_wfi(void) {
    __asm__ volatile ("wfi");
}

static inline void bcd_enable_interrupts(void) {
    __asm__ volatile ("csrsi mstatus, 8"); // MIE bit
}

static inline void bcd_disable_interrupts(void) {
    __asm__ volatile ("csrci mstatus, 8");
}

#endif // BCD_SOC_H
