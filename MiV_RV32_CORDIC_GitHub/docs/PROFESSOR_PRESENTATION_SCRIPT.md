# 教授報告講稿（約 4–5 分鐘）

> 建議使用 README 的架構圖、測試表，以及 `assets/screenshots/04_final_pass.png`。括號裡是你操作畫面時的提示，不用念出來。

## 0:00–0:35｜主題與目標

「教授您好，我們這次要報告的主題是 **Mi-V RV32 CPU 使用自訂 CORDIC 指令來計算自然對數 ln 和指數 exp 的軟硬體整合 RTL 模擬**。專題的硬體基礎是學長留下的單通道 CORDIC。我這部分主要負責 C 語言的迭代控制、SoftConsole 編譯、CPU 模擬整合，以及功能驗證。」

## 0:35–1:20｜為什麼用 CORDIC

「CORDIC 的特色是以位移和加減法逐步計算數學函數。雙曲線 CORDIC 可以透過兩種控制模式計算 ln 和 exp。對 ln 而言，軟體根據 Y 的正負選擇方向；對 exp 而言，根據剩餘角度 Z 的正負選方向。我們用 Q12 定點數，所以 4096 代表實際數值 1。每一筆測試使用 13 次迭代，其中 shift 4 重複一次。」

## 1:20–2:10｜軟硬體如何接起來

（打開 `firmware/cordic_ln_exp.c` 的 `CORDIC_END` 和 `hw_step()`）

「這裡是我們在 C 程式裡呼叫的自訂指令 `.insn r 0x0B, 0x5, 0x03`。程式把 X 和 Y 各用 16 bit 放進 rs1，並把方向 dir、移位量 shift 放進 rs2。CPU 取出這條指令，送到我們修改的 Mi-V EXU，CORDIC 硬體就執行一次移位加減，再把新的 X、Y 結果寫回 CPU 暫存器。」

「`test_ln_hw()`、`test_exp_hw()` 不是直接用一般浮點的 log/exp，而是依照不同方向條件，各呼叫這個硬體指令 13 次。」

## 2:10–3:10｜ModelSim 真正驗證了什麼

（打開 `assets/screenshots/01_cpu_fetch.png` 與 `assets/screenshots/03_ln_exp_and_store.png`）

「我們不是只有把運算器當成獨立模組測試，而是在 ModelSim 中例化完整的 `miv_rv32_hart`。程式由 SoftConsole 編譯成 ELF/HEX，再當作指令記憶體的內容。Trace 可以看到 CPU 真正取指令、執行自訂指令；LSU 訊息可以看到 CPU 把結果寫回 RAM。」

「這張圖中 `LN CORDIC count=13` 和 `EXP CORDIC count=13`，表示 CPU 確實執行兩組各 13 次的自訂指令。」

## 3:10–3:50｜重要實驗結果

（打開 `assets/screenshots/04_final_pass.png`）

「ln(1.5) 的結果是 Q12 整數 1660，換成實數為約 0.405273，理論值是 0.405465。exp(1) 的 Q12 結果是 11134，換算約 2.718262，理論值是 2.718282。CPU 也有寫出完成標記 `C0DE0002`，最後 ModelSim 顯示 `FULL CPU LN/EXP CORDIC INTEGRATION PASSED`。」

## 3:50–4:30｜結論與下一步

「所以目前可以確認的是 **Mi-V RV32 CPU 已經能透過自訂 CORDIC 指令，完成 ln 和 exp 的完整 RTL 功能模擬**。但這還不是 FPGA 上板，也不是效能加速倍率。下一步我們要比較純軟體 CORDIC 和自訂指令版本的 cycle 數與指令數，再擴充輸入範圍，最後評估 FPGA 實作。」

## 可能會被追問的問題

**Q：你和學長的工作差異？**

A：「學長留下 CORDIC 單步硬體。我負責由 C 程式控制連續迭代、編譯成 CPU 自訂指令、建立完整 CPU 記憶體測試平台，並比對 ln/exp 結果。已完成 RTL 整合功能驗證，後續才是效能量測。」

**Q：為什麼需要 13 次？**

A：「移位階段 1～12，共 12 種 shift；其中 shift 4 額外重複一次，符合本次雙曲線 CORDIC 的迭代安排，因此共 13 次。」

**Q：為何 ln(1.5) 用 X=10240、Y=2048？**

A：「Q12 裡 1.5=6144、1=4096，所以 X=6144+4096=10240，Y=6144−4096=2048；用 `ln(a)=2atanh((a−1)/(a+1))` 轉成 CORDIC vectoring。」

**Q：14050 ns 是硬體加速的執行時間嗎？**

A：「是 ModelSim 的 RTL 模擬時間，含 Testbench 和記憶體模型，不等於 FPGA 上實測的執行時間，不能直接推算加速倍率。」

**Q：到底是 CPU 在算還是 Testbench 在算？**

A：「CPU 執行 SoftConsole 編譯的指令，EXU 中的 CORDIC RTL 做每一步 X/Y 移位加減；Testbench 主要提供記憶體模型並檢查執行次數與最後結果。」
