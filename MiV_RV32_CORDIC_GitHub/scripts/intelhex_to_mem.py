#!/usr/bin/env python3
"""Convert Intel HEX to one 32-bit little-endian word per line for $readmemh.

Example:
  python scripts/intelhex_to_mem.py firmware/reference_binary/mi-vuse-ln-exp.hex /tmp/cpu_prog_ln_exp.mem

This converter is dependency-free and checks record checksums/address ranges.
"""
import argparse
from pathlib import Path

BASE = 0x60000000
SIZE = 8192

def convert(text: str, base: int = BASE, size: int = SIZE) -> tuple[bytes, int | None]:
    if size % 4:
        raise ValueError("size must be divisible by four")
    data = bytearray(size)
    upper = 0
    entry = None
    seen_eof = False
    for lineno, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        if not line.startswith(":"):
            raise ValueError(f"line {lineno}: not an Intel HEX record")
        raw = bytes.fromhex(line[1:])
        if len(raw) < 5:
            raise ValueError(f"line {lineno}: short record")
        n = raw[0]
        if len(raw) != n + 5 or sum(raw) % 256:
            raise ValueError(f"line {lineno}: bad record length/checksum")
        off = int.from_bytes(raw[1:3], "big")
        typ = raw[3]
        payload = raw[4:-1]
        if typ == 0:
            addr = upper + off
            if not (base <= addr and addr + n <= base + size):
                raise ValueError(f"line {lineno}: out-of-range data 0x{addr:08X}")
            data[addr-base:addr-base+n] = payload
        elif typ == 1:
            seen_eof = True
            break
        elif typ == 4:
            if n != 2:
                raise ValueError(f"line {lineno}: invalid extended linear address")
            upper = int.from_bytes(payload, "big") << 16
        elif typ == 5:
            if n != 4:
                raise ValueError(f"line {lineno}: invalid start linear address")
            entry = int.from_bytes(payload, "big")
        else:
            raise ValueError(f"line {lineno}: unsupported record type {typ}")
    if not seen_eof:
        raise ValueError("missing EOF record")
    return bytes(data), entry

def main():
    p = argparse.ArgumentParser()
    p.add_argument("hex_input", type=Path)
    p.add_argument("mem_output", type=Path)
    args = p.parse_args()
    data, entry = convert(args.hex_input.read_text(encoding="ascii"))
    words = [int.from_bytes(data[i:i+4], "little") for i in range(0, SIZE, 4)]
    args.mem_output.parent.mkdir(parents=True, exist_ok=True)
    args.mem_output.write_text("".join(f"{w:08x}\n" for w in words), encoding="ascii")
    print(f"wrote {len(words)} words, base=0x{BASE:08X}, entry={hex(entry) if entry is not None else 'unknown'}")

if __name__ == "__main__":
    main()
