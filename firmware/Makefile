# ==============================================================================
# Brain Condition Detector (BCD) SoC - RISC-V Firmware Build Makefile
# Target: Western Digital / CHIPS Alliance VeeR EL2 (RV32IMC)
# ==============================================================================

CROSS_COMPILE ?= riscv64-unknown-elf-
CC             = $(CROSS_COMPILE)gcc
OBJCOPY        = $(CROSS_COMPILE)objcopy
OBJDUMP        = $(CROSS_COMPILE)objdump

ARCH_FLAGS     = -march=rv32imc -mabi=ilp32
CFLAGS         = $(ARCH_FLAGS) -O2 -Wall -Wextra -ffreestanding -nostdlib -I.
LDFLAGS        = -T link.ld -nostartfiles -Wl,--gc-sections

TARGET_ELF     = boot.elf
TARGET_BIN     = boot.bin
TARGET_HEX     = boot.hex
TARGET_DUMP    = boot.dump

SRCS_S         = boot.S
SRCS_C         = main.c

OBJS           = $(SRCS_S:.S=.o) $(SRCS_C:.c=.o)

.PHONY: all clean dump hex install

all: $(TARGET_HEX) $(TARGET_DUMP)

$(TARGET_ELF): $(OBJS) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) -o $@

%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.c bcd_soc.h
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET_BIN): $(TARGET_ELF)
	$(OBJCOPY) -O binary $< $@

$(TARGET_DUMP): $(TARGET_ELF)
	$(OBJDUMP) -d -S $< > $@

$(TARGET_HEX): $(TARGET_BIN)
	python -c "import sys; data = open(sys.argv[1], 'rb').read(); [print(f'{int.from_bytes(data[i:i+4], \"little\"):08x}') for i in range(0, len(data), 4)]" $(TARGET_BIN) > $@

install: $(TARGET_HEX)
	cp $(TARGET_HEX) ../mem/boot.hex
	@echo "Copied $(TARGET_HEX) to ../mem/boot.hex"

clean:
	rm -f $(OBJS) $(TARGET_ELF) $(TARGET_BIN) $(TARGET_HEX) $(TARGET_DUMP)
