#!/usr/bin/env python3
"""Check on-disk firmware integrity and the two expected instruction sites.
This is static verification; it does NOT replace a ModelSim CPU simulation.
"""
from pathlib import Path
import hashlib, sys
sys.path.insert(0, str(Path(__file__).parent))
from intelhex_to_mem import convert, BASE, SIZE

root = Path(__file__).resolve().parents[1]
hexfile = root / "firmware/reference_binary/mi-vuse-ln-exp.hex"
memfile = root / "firmware/reference_binary/cpu_prog_ln_exp.mem"
elfile = root / "firmware/reference_binary/mi-vuse-ln-exp.elf"
data, entry = convert(hexfile.read_text(encoding="ascii"))
expected = [f"{int.from_bytes(data[i:i+4], 'little'):08x}" for i in range(0,SIZE,4)]
actual = memfile.read_text(encoding="ascii").splitlines()
assert actual == expected, "HEX and MEM differ"
assert entry in (None, BASE), f"unexpected entry {entry!r}"
for pc in (0x60000070,0x600000F4):
    instr = int.from_bytes(data[pc-BASE:pc-BASE+4], "little")
    assert instr == 0x06F7578B, (hex(pc),hex(instr))
elf = elfile.read_bytes()
assert elf[:4] == b"\x7fELF" and elf[4:6] == b"\x01\x01"
assert int.from_bytes(elf[24:28],"little") == BASE
print("PASS static artifact verification: ELF entry, HEX/MEM match, two CORDIC sites")
print("ELF SHA256:", hashlib.sha256(elf).hexdigest())
print("NOTE: 13+13 retired instructions and numerical outputs require the ModelSim test.")
