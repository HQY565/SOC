# 從零理解本專題（向教授報告前建議先讀）

## 你現在到底做了什麼？

這個專題是**軟硬體共同完成 ln 和 exp**。學長留下的單通道 CORDIC 硬體只做一次位移／加減。你負責 C 程式，安排要迭代多少次、方向要選哪一邊、怎麼查表、怎麼把結果轉回 Q12；再把 C 程式編譯成 Mi-V 可以執行的自訂指令。

一句話版本：**C 決定怎麼計算，CPU 執行自訂指令，CORDIC RTL 做每一步的移位加減。**

## 三份最重要的程式

1. `firmware/cordic_ln_exp.c`：軟體控制器；`hw_step()` 封裝自訂指令；`test_ln_hw()` 與 `test_exp_hw()` 各呼叫 13 次；`main()` 將答案寫進記憶體。
2. `verification/tb_miv_cpu_ln_exp_standalone.sv`：硬體測試平台；用 RAM 模型提供 CPU 指令、回應 LSU 讀寫，檢查執行次數、結果、完成標記。
3. **你的 Libero 專案內** `hdl/miv_rv32_hart_merged.v` 與 `hdl/miv_rv32_pkg.v`：真正的 Mi-V 與 CORDIC RTL；因可能受第三方授權限制，**未放入 GitHub 套件**。

## 為什麼不是普通的 C 語言模擬？

`miv_rv32_hart` 有 CPU 取指令介面。ModelSim 提供一段 RAM，放入 SoftConsole 編出來的機器碼；`trace_insn` 證明 CPU 退休了自訂指令；`lsu_emi_req_write` 證明 CPU 把答案寫回 RAM。這才叫**CPU 層級 RTL 軟硬體整合模擬**。

如果只是 `tb` 直接給 EXU 的 ALU selector，就只能叫 EXU 層級驗證。兩者先前都已完成，但驗證範圍不同。

## 固定小數點 Q12 是什麼？

- 以整數儲存實數，`4096` 代表 `1.0`；`Q12 值 / 4096 = 實際數值`。
- ln(1.5) 的 `1660 / 4096 = 0.4052734375`。
- exp(1) 的 `11134 / 4096 = 2.71826171875`。

這使 CPU／CORDIC 不必在每步使用浮點運算，適合以整數和位移操作。

## 數學為什麼可行？

- `ln(a) = 2 atanh((a-1)/(a+1))`，先把 `a` 轉成 `X=a+1, Y=a-1`，再做 hyperbolic vectoring；程式用 `x=10240, y=2048`，等價於 Q12 的 2.5 和 0.5，對應 `a=1.5`。
- `exp(a) = 2^q exp(r)`，以 `a=q ln(2)+r` 範圍縮減。`exp(1)` 用 `q=1`，`r≈1-ln(2)`；CORDIC rotation 算完 `exp(r)`，再乘 2。
- 雙曲線 CORDIC 有重複 shift 的需求；本次用 `1,2,3,4,4,5,...,12`，共 13 次。

## Transcript 怎麼看？

- `IFETCH addr=...`：CPU 要讀這個程式位置。
- `RETIRED PC=... INSN=... exception=0`：CPU 完成這條指令，未產生例外。
- `LN CORDIC count=13`：CPU 真的執行了 ln 迴圈的自訂指令 13 次；exp 也一樣。
- `CPU LSU WRITE 60001000 <- 0000067c`：CPU 把 ln 整數結果寫進記憶體。
- `CPU LSU WRITE 60001004 <- 00002b7e`：CPU 把 exp 整數結果寫進記憶體。
- `CPU LSU WRITE 60001008 <- c0de0002`：程式寫出完成標記。
- `FULL CPU LN/EXP CORDIC INTEGRATION PASSED`：以上檢查在 Testbench 中通過。

## 教授問：這樣算硬體加速成功嗎？

**目前可以說：硬體自訂指令的功能整合驗證成功。** 但還沒有「加速了幾倍」的結論。必須額外設計純軟體基準測試，在相同環境下量測 CPU cycle/retired instruction，並且再做 FPGA 資源／時序或實機驗證。

## 教授問：14050 ns 是執行速度嗎？

這是 ModelSim Testbench 的**模擬時間**（包含 reset、記憶體模型、迴圈等），不是 CPU 實機耗時／加速比。不能直接拿它聲稱 CORDIC 硬體速度比純軟體快。

## 下一階段的合理計畫

1. 擴充 ln(0.5)、ln(2)、exp(-1) 等輸入與誤差範圍。
2. 加入純 C 位移／加減版，與自訂指令版比較相同輸入的週期和指令數。
3. 再評估 FPGA 上板、資源消耗、時序收斂與真實執行效能。
