# 如何把這份專題上傳 GitHub（不用 Git 指令）

1. 下載 `MiV_RV32_10CH_CORDIC_GitHub_Final.zip`，在 Windows 檔案總管**解壓縮**。
2. 登入 GitHub，點選右上角 `+` → `New repository`。
3. Repository name 可填 `MiV-RV32-10CH-CORDIC-LN-EXP`，Visibility 選 **Public**（若課程、團隊或原始碼有保密需求則選 Private）。
4. **不要勾選** Initialize with a README，避免與套件內的 `README.md` 混淆；建立 Repository。
5. 點擊 `uploading an existing file` 或 `Add file → Upload files`。
6. **進入解壓縮後資料夾，按 Ctrl+A 選取裡面的所有檔案及子資料夾**，拖曳到 GitHub Upload 畫面。不要只拖 ZIP 檔，否則 GitHub 首頁無法直接顯示 README。
7. 下方寫 `Add project report, RTL, verification, performance evidence`，按 `Commit changes`。
8. 重新開啟 Repository 首頁，應可直接看到 README、架構圖、成果表與截圖。按 `docs/教授報告講稿_約7分鐘.md` 可以看到講稿。

## 上傳前請確認

- 不要公開含有學校／實驗室機密或其他人的未經授權專有原始碼。
- 此套件未包含 Microchip 原廠 Mi-V RTL；保留既有專題的原廠 RTL 在你本機即可。
- 如需 GitHub 上真正一鍵重新編譯 SoftConsole，請額外補上**自己當時使用的完整 `mivuse.c`、`linker.ld`、編譯參數**，而不是把這份 reference C 程式宣稱為逐位元可重製版本。
- 第一次上傳後建議加入 GitHub Repo Description：`RTL-verified Mi-V RV32 + 10-channel hyperbolic CORDIC ln/exp, MMIO integration and core/system performance benchmarks.`
