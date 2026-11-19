# NOTICE / 授權與重現注意事項

- This repository documents a user-demonstrated educational project and contains user-supplied firmware binaries and testbench code prepared for that work.
- It intentionally does not bundle Microchip/Mi-V vendor RTL or the full project-derived merged Hart RTL. Users must supply their own appropriately licensed copy and apply the project's CORDIC extension.
- The C source `firmware/cordic_ln_exp.c` is a readable demo reconstructed from the implementation shown in the project conversation; the ELF/HEX files under `firmware/reference_binary/` are the **uploaded compiled artifacts**. Rebuilding may change instruction addresses and binary bytes, in which case the Testbench's embedded image and PC checks must also be regenerated.
- The optional external-MEM Testbench contains the original absolute Windows path, preserved as reference. Do not expect it to work without editing that path.
- Published performance results are functional RTL test results for specified inputs only. No FPGA clock/area/power benchmarks or performance speedup claims are included.
- No open-source license has been selected for third-party code here. Confirm permission from all rights holders before releasing a public repository.
