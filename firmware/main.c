// ==============================================================================
// Brain Condition Detector (BCD) SoC - Main RISC-V Management Firmware
// Target Core : Western Digital / CHIPS Alliance VeeR EL2 (RV32IMC)
// Description : Manages autonomous biosensor ingest, programs RTL Threshold CSRs,
//               coordinates Edge-AI & Swin accelerator DMA, and handles clinical telemetry.
// ==============================================================================

#include "bcd_soc.h"

// System State Variables (resident in SRAM .bss)
static volatile uint32_t g_event_counter;
static volatile uint32_t g_seizure_alarm_active;
static volatile uint32_t g_last_clinical_class;
static volatile uint32_t g_last_confidence;

// -----------------------------------------------------------------------------
// Subsystem Initialization Routines
// -----------------------------------------------------------------------------

/**
 * @brief Configure the 24-bit 64-Channel Biopotential Analog Front-End (AFE)
 */
void bcd_init_afe(void) {
    volatile uint32_t *afe_csr = (volatile uint32_t *)BCD_CSR_AFE_BASE;
    // Enable AFE, set 250 Sps sampling rate, enable all 64 biopotential channels
    afe_csr[0] = 0x00000001U; // AFE Power Enable
    afe_csr[1] = 0x000000FAU; // Sample Rate = 250 Hz
    afe_csr[2] = 0xFFFFFFFFU; // Channel Mask Lower 32 channels
    afe_csr[3] = 0xFFFFFFFFU; // Channel Mask Upper 32 channels
}

/**
 * @brief Configure Digital Filter Bank (50 Hz Notch + 0.5-100 Hz BPF + CAR)
 */
void bcd_init_filter_bank(void) {
    volatile uint32_t *filter_csr = (volatile uint32_t *)BCD_CSR_FILTER_BASE;
    // [0] Filter Enable, [1] 50Hz Notch Enable (Indian power grid), [2] CAR Enable
    filter_csr[0] = 0x00000007U;
}

/**
 * @brief Program RTL Threshold Engine (Section 4.4 Register Map)
 */
void bcd_init_threshold_engine(void) {
    // 1. Reset threshold registers
    THRESH_CTRL = THRESH_CTRL_SOFT_RESET;
    THRESH_CTRL = 0x00000000U;

    // 2. Set 64-channel detection mask (all channels enabled for surveillance)
    THRESH_CH_MASK = 0xFFFFFFFFU;

    // 3. Program clinical seizure & pathology thresholds
    THRESH_LL_THR       = 0x000008A0U; // Line Length abnormal threshold (fixed-point 16.16)
    THRESH_BP_RATIO_THR = 0x00000450U; // Delta/Theta to Alpha/Beta power ratio threshold
    THRESH_ENT_THR      = 0x00000120U; // Spectral Entropy depression threshold

    // 4. Configure Multi-Channel Voter (4-of-8 voting logic)
    // Bits [15:0]: M=4 channels, Bits [31:16]: N=8 channels
    THRESH_VOTE_NM      = (8U << 16) | (4U);

    // 5. Alarm debounce and pre-trigger history window
    THRESH_HYST_HOLD    = 0x000A0005U; // 10 hold-off counts, 5 hysteresis counts
    THRESH_PRETRIG_LEN  = 0x0000001EU; // 30 seconds of pre-trigger buffer context

    // 6. Set Wake-up Target (Power-ungate both Edge-AI NPU and Swin Transformer)
    THRESH_WAKE_TARGET  = WAKE_TARGET_BOTH;

    // 7. Enable Abnormal Wake-up Interrupt to VeeR core
    THRESH_IRQ_STATUS   = 0xFFFFFFFFU; // Clear any pending status (W1C)
    THRESH_IRQ_EN       = 0x00000001U; // Enable IRQ to CPU

    // 8. Start monitoring
    THRESH_CTRL         = THRESH_CTRL_EN;
}

/**
 * @brief Initialize Edge-AI NPU Accelerator (Base 0x4005_0000)
 */
void bcd_init_npu(void) {
    // Configure AXI base address for pre-loaded EEGNet INT8 model weights in NVM
    NPU_WEIGHT_ADDR  = BCD_NVM_BASE;          // 0x6000_0000
    // Configure scratchpad workspace for intermediate activation tensors
    NPU_SCRATCH_ADDR = BCD_SCRATCHPAD_BASE;   // 0x1100_0000
    // Enable completion interrupt
    NPU_IRQ_EN       = 0x00000001U;
}

/**
 * @brief Initialize Swin Transformer Accelerator (Base 0x4006_0000)
 */
void bcd_init_swin(void) {
    // Configure AXI base address for Swin attention projection weights in LPDDR4
    SWIN_WEIGHT_ADDR   = BCD_LPDDR_BASE;      // 0x8000_0000
    // Configure tokenized spectrogram patch input buffer in Scratchpad
    SWIN_TOKEN_ADDR    = BCD_SCRATCHPAD_BASE + 0x00010000U;
    // Configure saliency heatmap overlay output buffer in SRAM
    SWIN_SALIENCY_ADDR = BCD_SRAM_BASE + 0x00040000U;
    // Enable completion interrupt
    SWIN_IRQ_EN        = 0x00000001U;
}

/**
 * @brief Initialize Power Management Unit (PMU) & Power Islands
 */
void bcd_init_pmu(void) {
    // Enable automatic hardware power-gating on Threshold Engine trigger
    PMU_WAKE_MASK = 0x00000003U; // Allow both NPU (bit 0) and Swin (bit 1) to be auto-ungated
}

// -----------------------------------------------------------------------------
// Interrupt Service Routine (ISR) Dispatcher
// -----------------------------------------------------------------------------
void isr_dispatch(uint32_t mcause, uint32_t mepc, uint32_t mtval) {
    (void)mepc;
    (void)mtval;

    // Check if external interrupt (bit 31 set)
    if (mcause & 0x80000000U) {
        uint32_t irq_id = mcause & 0x7FFFFFFFU;

        switch (irq_id) {
            case IRQ_ID_THRESHOLD:
                // Abnormal neuro-event detected by real-time hardware thresholding
                g_seizure_alarm_active = 1;
                g_event_counter++;

                // Clear threshold engine interrupt status (Write-1-to-Clear)
                THRESH_IRQ_STATUS = 0x00000001U;
                break;

            case IRQ_ID_NPU_DONE:
                // Edge-AI NPU completed EEGNet inference
                g_last_clinical_class = NPU_RESULT_CLASS & 0xFU;
                g_last_confidence     = NPU_CONFIDENCE & 0xFFU;
                break;

            case IRQ_ID_SWIN_DONE:
                // Swin Transformer completed shifted-window attention
                g_last_clinical_class = SWIN_RESULT_CLASS & 0xFU;
                g_last_confidence     = SWIN_CONFIDENCE & 0xFFU;
                break;

            case IRQ_ID_REPORT_READY:
                // Output Fusion generated final diagnostic heatmap and report
                g_seizure_alarm_active = 0;
                break;

            case IRQ_ID_DMA_DONE:
                // Ring buffer sample transfer completed
                break;

            case IRQ_ID_FIREWALL:
                // Security boundary violation trapped
                break;

            default:
                break;
        }
    }
}

// -----------------------------------------------------------------------------
// Main Application Entry Point
// -----------------------------------------------------------------------------
int main(void) {
    g_event_counter        = 0;
    g_seizure_alarm_active = 0;
    g_last_clinical_class  = CLASS_NORMAL;
    g_last_confidence      = 0;

    // 1. Initialize all SoC subsystems
    bcd_init_afe();
    bcd_init_filter_bank();
    bcd_init_threshold_engine();
    bcd_init_pmu();
    bcd_init_npu();
    bcd_init_swin();

    // 2. Enable processor interrupts
    bcd_enable_interrupts();

    // 3. Autonomous Low-Power Surveillance Loop
    // The processor sleeps via 'wfi' until an abnormal event (Seizure/Spindle)
    // asserts hardware wake-up through the RTL Threshold Engine.
    while (1) {
        bcd_wfi(); // Enter low-power sleep mode

        // If woken by a clinical event, trigger acceleration if needed
        if (g_seizure_alarm_active) {
            // Optional: Software supervision of ongoing inference
        }
    }

    return 0;
}
