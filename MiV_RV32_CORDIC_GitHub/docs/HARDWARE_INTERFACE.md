# 硬體介面與自訂指令說明

> 這是依據專題提供的 `miv_rv32_pkg.v`／Mi-V RTL 片段與**實際成功模擬**整理的介面說明。第三方完整 RTL 未重新散佈。

## 自訂指令

- opcode: `0x0B`（CUSTOM-0）
- funct3: `0b101`
- funct7: `0b0000011`
- C inline assembly: `.insn r 0x0B, 0x5, 0x03, rd, rs1, rs2`
- 本次 ELF 中機器碼：`0x06F7578B`（兩個靜態指令位置）
- ln 的 PC：`0x60000070`；exp 的 PC：`0x600000F4`

`rs1` 將 2 個有號 16-bit 座標封裝：`{X[15:0],Y[15:0]}`。`rs2` 將 `dir` 放在 bit 31、`shift` 放在 bit 30:24。硬體回傳 `rd={X'[15:0],Y'[15:0]}`。本次小範圍輸入經驗證；不是通用浮點指令。

### 單步變換

- `dir=1`：`X' = X - (Y >>> shift)`，`Y' = Y - (X >>> shift)`。
- `dir=0`：`X' = X + (Y >>> shift)`，`Y' = Y + (X >>> shift)`。

這兩式是硬體實際測試的移位加減規則。`>>>` 為有號算術右移。

### CORDIC 的 ln 與 exp 是不同控制模式

- `ln`：vectoring。根據 `Y` 的正負選方向，累積查表角度 `Z`，使 Y 趨近零。
- `exp`：rotation。根據 `Z` 的正負選方向，調整 X/Y，讓剩餘角度趨近零。

共同 shift 次序：`1,2,3,4,4,5,6,7,8,9,10,11,12`；共 13 步。

## 完整 CPU 模擬觀察點

| 名稱 | 功能 |
|---|---|
| `ifu_emi_*` | CPU 向模擬 RAM 取指令 |
| `trace_valid/trace_iaddr/trace_insn` | CPU 退休（執行完成）的指令／PC |
| `lsu_emi_*` | CPU 透過 LSU 發出記憶體讀寫 |
| `0x60001000` | ln(1.5) 結果 1660 |
| `0x60001004` | exp(1) 結果 11134 |
| `0x60001008` | 軟體完成旗標 `0xC0DE0002` |

> **勿混淆：** 這裡使用完整的 `miv_rv32_hart`，不是之前由 Testbench 直接指定 `exu_alu_op_cordic_end` 的 EXU-only 測試。尚未在 FPGA 實機驗證，也沒有加速比數據。
