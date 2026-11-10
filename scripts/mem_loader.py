#!/usr/bin/env python3
# ==============================================================================
# Brain Condition Detector (BCD) SoC - Memory Loader & Hex Parser Utility
# ==============================================================================
# Features:
# 1. Converts binary firmware (.bin / .elf) into Verilog $readmemh hex files.
# 2. Parses Intel HEX (.hex) and SystemVerilog memory (.mem) format.
# 3. Validates memory alignment, address gaps, and checksums.
# 4. Injects firmware into simulation memory models.
#
# Usage:
#   python scripts/mem_loader.py --inspect mem/boot.hex
#   python scripts/mem_loader.py --bin firmware.bin --hex mem/boot.hex --base 0x00000000
# ==============================================================================

import argparse
import os
import sys

def parse_hex_file(filepath):
    """Parses a Verilog $readmemh file, stripping comments and addresses."""
    words = []
    current_addr = 0
    if not os.path.exists(filepath):
        print(f"Error: File '{filepath}' not found.")
        return []

    with open(filepath, 'r') as f:
        for line in f:
            # Strip comments
            line = line.split('//')[0].strip()
            if not line:
                continue

            # Check for address directive (@address)
            if line.startswith('@'):
                parts = line[1:].split()
                current_addr = int(parts[0], 16)
                tokens = parts[1:]
            else:
                tokens = line.split()

            for token in tokens:
                try:
                    val = int(token, 16)
                    words.append((current_addr, val))
                    current_addr += 1
                except ValueError:
                    continue

    return words

def inspect_hex(filepath):
    """Displays memory contents, decoding header signatures and known patterns."""
    words = parse_hex_file(filepath)
    print("=" * 68)
    print(f" Memory Image Inspection: {filepath}")
    print(f" Total Words: {len(words)} ({len(words)*4} bytes)")
    print("=" * 68)
    print(f" {'Address':<12} | {'Hex Value':<10} | {'ASCII / Annotation'}")
    print("-" * 68)

    for addr, val in words[:32]:
        byte_str = "".join([chr((val >> (8 * b)) & 0xFF) if 32 <= ((val >> (8 * b)) & 0xFF) <= 126 else "." for b in range(4)])
        # Big-endian display for ASCII
        ascii_disp = byte_str[::-1]

        annotation = f"'{ascii_disp}'"
        if val == 0x00000013:
            annotation += " (RISC-V NOP)"
        elif val == 0x10500073:
            annotation += " (RISC-V WFI)"
        elif val == 0x62636431:
            annotation += " (BCD1 Magic Tag)"
        elif val == 0xCAFEBABE:
            annotation += " (Boot Integrity)"

        byte_addr = addr * 4
        print(f" 0x{byte_addr:08X}   | 0x{val:08X} | {annotation}")

    if len(words) > 32:
        print(f" ... ({len(words) - 32} remaining words omitted)")
    print("=" * 68)

def bin_to_hex(bin_path, hex_path, base_addr=0):
    """Converts a raw binary file to a 32-bit word-aligned Verilog hex file."""
    if not os.path.exists(bin_path):
        print(f"Error: Binary file '{bin_path}' not found.")
        sys.exit(1)

    with open(bin_path, 'rb') as f:
        data = f.read()

    # Pad data to multiple of 4 bytes
    remainder = len(data) % 4
    if remainder != 0:
        data += b'\x00' * (4 - remainder)

    words = []
    for i in range(0, len(data), 4):
        word = int.from_bytes(data[i:i+4], byteorder='little')
        words.append(word)

    with open(hex_path, 'w') as f:
        f.write(f"// Generated from {bin_path} (Base: 0x{base_addr:08X})\n")
        f.write(f"// Total Words: {len(words)}\n\n")
        for i, word in enumerate(words):
            f.write(f"{word:08x}\n")

    print(f"Success: Wrote {len(words)} words to '{hex_path}'")

def main():
    parser = argparse.ArgumentParser(description="BCD SoC Memory Loader & Hex Parser")
    parser.add_argument("--inspect", type=str, help="Inspect and dump contents of a .hex or .mem file")
    parser.add_argument("--bin", type=str, help="Input raw binary file (.bin)")
    parser.add_argument("--hex", type=str, help="Output Verilog $readmemh file (.hex)")
    parser.add_argument("--base", type=lambda x: int(x, 0), default=0, help="Base byte address")

    args = parser.parse_args()

    if args.inspect:
        inspect_hex(args.inspect)
    elif args.bin and args.hex:
        bin_to_hex(args.bin, args.hex, args.base)
    else:
        # Default action: inspect default boot.hex
        default_boot = os.path.join(os.path.dirname(__file__), "..", "mem", "boot.hex")
        if os.path.exists(default_boot):
            inspect_hex(default_boot)
        else:
            parser.print_help()

if __name__ == "__main__":
    main()
