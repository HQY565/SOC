# 範圍、來源及授權聲明

- 本套件保留的是本專題提供與整理過的自建 RTL、ModelSim Testbench、SoftConsole HEX／MEM、圖像證據及技術文件；不包含 Microchip 原廠 Mi-V CPU、Libero／ModelSim／SoftConsole 或其他閉源 FPGA IP。
- 原廠設計及 FPGA 工具的授權以相應權利人條款為準；請自行確認實驗室與團隊是否允許公開衍生作品或學校工程檔案。未宣告一份可涵蓋所有組件的開源授權。
- `firmware/mi-vuse_ln10.hex`、`mi-vuse_exp10.hex` 為先前實測成功的韌體映像；`*_reference.c` 為為了理解流程而整理的程式碼，不保證在不同 linker 或工具版本下生成位元完全相同的 HEX。
- `rtl/ln/cordic_ln_parallel_10ch_mmio.sv`、`sim/mmio/tb_cordic_ln_parallel_10ch_mmio.sv` 為依先前對話中成功使用的介面與測試流程整理出的乾淨公開副本，並未在此容器重新呼叫 ModelSim 驗證。
- 當前數據來自使用者的 ModelSim Transcript。**已驗證範圍為 RTL 模擬**；未對 FPGA 實板、Libero 綜合使用率或最高時脈做出完成宣稱。
- `assets/screenshots` 為本專題測試結果截圖。若公開前含帳號、主機名稱、路徑或其他不希望公開的資訊，請自行遮蔽再上傳。
