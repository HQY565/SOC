# 如何上傳至 GitHub（Windows 新手版）

## 不需 Git 指令：網頁上傳

1. 登入 GitHub → **New repository**。
2. Repository name 建議：`MiV-RV32-CORDIC-ln-exp`。
3. 先選 **Private**（和專題夥伴／教授確認公開授權後再切 Public）。
4. Repository 建好後點 **Add file → Upload files**。
5. 把本套件解壓縮，將 `README.md`、`firmware/`、`verification/`、`scripts/`、`assets/`、`docs/`、`.gitignore` 等放上去。一般會保留資料夾結構；如果瀏覽器拖曳整個資料夾不成功，可改用 Git Desktop 或下方指令。
6. 填寫 commit 訊息，例如 `Add verified Mi-V RV32 CORDIC RTL integration demo`，再按 **Commit changes**。

## 使用 Git 指令（在資料夾內開 Git Bash）

```bash
git init
git add .
git commit -m "Add Mi-V RV32 CORDIC CPU RTL integration demo"
git branch -M main
git remote add origin https://github.com/<YOUR_ACCOUNT>/MiV-RV32-CORDIC-ln-exp.git
git push -u origin main
```

將 `<YOUR_ACCOUNT>` 換成你的 GitHub 帳號。遠端 Repository 必須先在 GitHub 建立。

## 重要公開注意事項

- **不要**直接上傳整個 `MPFS_ICICLE`、`component/Actel`、`component/Microsemi`、整個 `miv_rv32_hart_merged.v` 等未確認授權的第三方／學長 IP。
- 本套件已排除第三方 Mi-V RTL，只保留測試平台、軟體示範與已提供的 binary／驗證截圖。
- 發布前和學長、共同作者、指導教授確認程式、截圖和成果是否可以公開。可先使用 Private。
- 如需提供可完全重建的硬體設計，請另以取得授權的原始專案／環境配置。
- `docs/MiV_CORDIC_RTL_Integration_Report.pdf` 是報告用途，發布前可以自行選擇保留或移除。
