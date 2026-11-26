# ModelSim 重現操作（Libero 2024.09 + ModelSim Microsemi Pro 2022.2）

> 本專題 User 工程原始路徑為 `C:/Libero v2024.09/icicle-kit-reference-design-2024.09/MPFS_ICICLE/simulation/cordic_test/parallel_10ch`。本 GitHub 套件可另放資料夾編譯，但 CPU 相關 Testbench 仍需要你本機已有的 `presynth.miv_rv32_hart` 與 Microchip 原廠 packages。

## 1. 最簡單：核心效能比較（不需要 CPU vendor RTL）

在 ModelSim Transcript 輸入（先設定下載後的資料夾路徑）：

```tcl
catch {quit -sim}
set repo {C:/Users/你的使用者名稱/Desktop/MiV_RV32_10CH_CORDIC_GitHub_Final}
vlib perfcorelib
vmap perfcorelib perfcorelib
vlog -sv -work perfcorelib "$repo/rtl/ln/cordic_ln_parallel_10ch.sv" "$repo/rtl/exp/cordic_exp_parallel_10ch.sv" "$repo/rtl/single_serial/cordic_ln_single.sv" "$repo/rtl/single_serial/cordic_exp_single.sv" "$repo/sim/core/tb_cordic_perf_compare.sv"
vsim perfcorelib.tb_cordic_perf_compare
run 20 us
```

預期找到 `ALL LN/EXP CORE PERFORMANCE TESTS PASSED`、`169` 和 `16` 週期。可先分別編譯 `sim/core/tb_cordic_ln_parallel_10ch.sv`、`tb_cordic_exp_parallel_10ch.sv` 驗證功能。

## 2. MMIO 功能測試

```tcl
catch {quit -sim}
vlib lnmmio
vmap lnmmio lnmmio
vlog -sv -work lnmmio "$repo/rtl/ln/cordic_ln_parallel_10ch.sv" "$repo/rtl/ln/cordic_ln_parallel_10ch_mmio.sv" "$repo/sim/mmio/tb_cordic_ln_parallel_10ch_mmio.sv"
vsim lnmmio.tb_cordic_ln_parallel_10ch_mmio
run 5000 ns
```

```tcl
catch {quit -sim}
vlib expmmio
vmap expmmio expmmio
vlog -sv -work expmmio "$repo/rtl/exp/cordic_exp_parallel_10ch.sv" "$repo/rtl/exp/cordic_exp_parallel_10ch_mmio.sv" "$repo/sim/mmio/tb_cordic_exp_parallel_10ch_mmio.sv"
vsim expmmio.tb_cordic_exp_parallel_10ch_mmio
run 5000 ns
```

## 3. CPU 系統效能（需要本機已編譯的 Mi-V）

先確認 ModelSim 函式庫 `presynth` 中的 `miv_rv32_pkg`、`miv_rv32_hart_cfg_pkg` 和 `miv_rv32_hart` 已按原成功專題的順序編譯。**不能只靠此 GitHub Repository 單獨建置 CPU 模擬**，因為 Mi-V vendor RTL 不隨套件發佈。

```tcl
catch {quit -sim}
vlib cordicln10lib
vmap cordicln10lib cordicln10lib
vlog -sv -work cordicln10lib "$repo/rtl/ln/cordic_ln_parallel_10ch.sv" "$repo/rtl/ln/cordic_ln_parallel_10ch_mmio.sv"
vlog -sv -work presynth "$repo/sim/perf_cpu/tb_miv_cpu_ln10_perf.sv"
vsim -L presynth -L cordicln10lib presynth.tb_miv_cpu_ln10_perf
run 100 us
```

改測 exp：

```tcl
catch {quit -sim}
vlib cordicexp10lib
vmap cordicexp10lib cordicexp10lib
vlog -sv -work cordicexp10lib "$repo/rtl/exp/cordic_exp_parallel_10ch.sv" "$repo/rtl/exp/cordic_exp_parallel_10ch_mmio.sv"
vlog -sv -work presynth "$repo/sim/perf_cpu/tb_miv_cpu_exp10_perf.sv"
vsim -L presynth -L cordicexp10lib presynth.tb_miv_cpu_exp10_perf
run 100 us
```

一個核心依序十筆：

```tcl
catch {quit -sim}
vlib cordicseriallib
vmap cordicseriallib cordicseriallib
vlog -sv -work cordicseriallib "$repo/rtl/single_serial/cordic_ln_single.sv" "$repo/rtl/single_serial/cordic_ln_1ch_mmio.sv" "$repo/rtl/single_serial/cordic_exp_single.sv" "$repo/rtl/single_serial/cordic_exp_1ch_mmio.sv"
vlog -sv -work presynth "$repo/sim/perf_cpu/tb_miv_cpu_ln1_perf.sv" "$repo/sim/perf_cpu/tb_miv_cpu_exp1_perf.sv"
vsim -L presynth -L cordicseriallib presynth.tb_miv_cpu_ln1_perf
run 100 us
catch {quit -sim}
vsim -L presynth -L cordicseriallib presynth.tb_miv_cpu_exp1_perf
run 100 us
```

## 4. 常見狀況

- `vlog-13069 near "<"`：記事本誤貼 `<CodeBlock ...>` 標籤；檔案第一行應為反引號開頭的 `` `timescale ``。
- `vsim-3033 miv_rv32_hart not found`：原廠 Mi-V 模組尚未編譯或對映到函式庫。
- `Recompile ... because miv_rv32_pkg has changed`：需要先重新編譯 package，再重新編譯依賴它的 Hart 與 Testbench。
- `WLF file currently in use`：波形檔被占用；可使用替代 WLF，不代表演算法失敗。
- `ModelSim> PASS:` → `invalid command`：誤將 Transcript 的輸出文字貼入命令列，PASS 是輸出訊息，不是指令。

*本文件提供已完成專題的編譯流程供重跑參考，並不宣稱在新環境再次實測。*
