# Compositor Localization

[English](../../README.md) · [简体中文](README.zh-Hans.md) · **繁體中文** · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md)

Compositor Localization 是 Robbie Tilton 的 Compositor 的非官方多語言分支。Compositor 是用於影像合成和相片編輯的 macOS 開放原始碼編輯器。本分支的第一個版本以原專案的 Compositor 1.7.1 為基礎。[原專案](https://github.com/robbietilton/Compositor)

本分支僅維護搭載 Apple 晶片的 Mac 上的 macOS 版本。

## 系統需求

- 搭載 Apple 晶片的 Mac
- macOS 26 或更新版本
- 從原始碼建置需要 Xcode。原專案的持續整合環境使用 Xcode 26.6。

## 下載 macOS 版

從發行頁面下載 [`Compositor-Localization-1.8.0-macos-arm64.dmg`](https://github.com/coderscsy/Compositor-Localization/releases/download/v1.8.0/Compositor-Localization-1.8.0-macos-arm64.dmg)，適用於執行 **macOS 26 或更新版本且搭載 Apple 晶片的 Mac**。同一頁面提供 `SHA256SUMS.txt`，可用於驗證下載檔案。打開磁碟映像檔後，將應用程式拷貝至「應用程式」資料夾。[GitHub v1.8.0 發行版本](https://github.com/coderscsy/Compositor-Localization/releases/tag/v1.8.0) · [更新日誌](../../CHANGELOG.md)

此應用程式採用臨時簽署（ad hoc signing），未經 Apple 公證。Gatekeeper 可能會在第一次開啟時阻擋執行。你也可以依照下文說明從原始碼建置。[Apple 的 Mac 應用程式開啟指南](https://support.apple.com/zh-tw/102445)

## 主要功能

- **圖層、混合與樣式。** 支援圖層鎖定（透明像素／影像像素／位置／全部鎖定）、與圖層樣式解耦的填滿不透明度（Fill Opacity）、混合色帶（Blend If）、資料夾獨立混合模式、向量遮色片與完整圖層樣式（筆畫內／中／外、陰影、內陰影、外／內光暈、顏色覆蓋、斜角和浮雕、漸層覆蓋與圖樣覆蓋）。
- **筆刷、`.abr` 匯入與修飾。** 支援直接匯入 Photoshop `.abr` 筆刷包至本機筆刷庫並儲存自訂預設，支援取樣位圖筆尖、流量、噴槍、12 種筆刷混合模式、筆尖間距／角度／圓度／散佈／抖動，以及油漆桶、加亮／加深／海綿（`O`）、銳利化筆刷（`R`）、多筆刷液化（含凍結遮色片）與手動取樣泊松修復筆刷。
- **向量路徑與文字排版。** 內建三角形／多邊形／星形工具、鋼筆工具（`P`）與路徑面板、非破壞性向量遮色片與布林運算，以及直排文字、文字彎曲變形（7 種預設）與路徑文字。
- **變形、裁切與選取精修。** 支援 9 點自訂軸心、獨立傾斜與 3×3 網格變形（Warp）；裁切支援拉直旋轉、構圖參考線、非破壞性切換與 4 角點透視裁切；選取新增快速遮色片（`Q`）與獨立「選取並遮住」工作區。
- **調整、濾鏡與專業面板。** 支援高反差保留、位移、亮度／對比、自然飽和度、選取顏色、顏色查閱（`.cube` 3D LUT）、臨界值、色調分離、色階、曲線、Camera Raw 與即時漸層填滿圖層；內建歷史記錄面板（含快照）、資訊面板與常駐色階分佈圖面板。
- **匯入、匯出與 PSD 互通。** 支援預覽並匯出為 PNG、JPEG、無損 WebP、HEIC、TIFF、單頁 PDF、GIF 動畫、EXR 與高保真 PSD（原生雙向讀寫 9 類 Photoshop 調整圖層、混合色帶、填滿不透明度與圖層樣式）。
- **專案自動化。** 指令稿或 AI 代理程式可以直接建立與編輯 `.comp`（v33）專案。應用程式會即時更新已開啟的專案。[編寫 `.comp` 專案](../writing-comp-files.md)

## 介面語言

開啟 **Compositor → 設定 → 介面語言**，選擇語言後結束並重新開啟應用程式。選擇 **跟隨系統** 時，會使用 macOS 為 Compositor 選定的語言。你可以在 **系統設定 → 一般 → 語言與地區 → 應用程式** 變更設定。

- 英文（`en`）是原始語言。尚未翻譯的文字會顯示英文。
- 中文提供簡體（`zh-Hans`）和繁體（`zh-Hant`）版本，繁體中文盡量採用臺灣常用詞彙。
- 日文（`ja`）、韓文（`ko`）、法文（`fr`）、德文（`de`）及西班牙文（`es`）為預覽版本。常用操作介面已抽查，其餘介面文字包含機器輔助翻譯。

## 從原始碼建置

各版本的原始碼可透過對應的 Git 標籤取得。以下指令會使用預設分支。

```sh
git clone https://github.com/coderscsy/Compositor-Localization.git
cd Compositor-Localization
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build
open build/Build/Products/Release/Compositor.app
```

也可以在 Xcode 開啟 `Compositor.xcodeproj`，執行 **Compositor** scheme。以 Debug 或 Release 在本機建置時，會使用臨時簽署（ad hoc signing）、應用程式沙盒和獨立的套件識別碼。

若要與原專案的應用程式並存，可將建置結果以 `Compositor Localization.app` 的名稱拷貝到「應用程式」資料夾。若要更新本機建置的版本，請取得本分支的新版本並重新建置。

經原作者簽署與公證的應用程式可從原專案的發行頁面下載。[原專案發行頁面](https://github.com/robbietilton/Compositor/releases/latest)

程式碼庫保留了原專案發行流程所用的 `scripts/release.sh`、`scripts/publish.sh` 及 `appcast.xml`。

## 回報與貢獻

回報 macOS 應用程式、翻譯或文件問題時，請註明介面語言、發生問題的選單或畫面、目前顯示的文字、應用程式和 macOS 的版本。方便時也可以附上建議譯文或螢幕截圖。[回報問題](https://github.com/coderscsy/Compositor-Localization/issues)

歡迎透過 Pull Request 提交翻譯修改。編輯本分支的字串目錄時，請保留格式預留位置和鍵盤快速鍵，並在應用程式內確認修改結果。[字串目錄](../../Compositor/Resources/Localizable.xcstrings)

## 授權

本分支採用 MIT 授權。原始著作權屬於 Wonder Assembly LLC。[MIT 授權條款](../../LICENSE)

體積光功能使用的深度模型 DepthMini 由 Depth Anything V2 Small（Apache-2.0）蒸餾而來，以 torchvision 中使用 ImageNet 訓練的 MobileNetV3 權重（BSD-3-Clause）為起點。應用程式會在第一次開啟體積光功能時下載此模型。[Depth Anything V2](https://github.com/DepthAnything/Depth-Anything-V2)
