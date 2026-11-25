# Compositor Localization

[English](../../README.md) · **简体中文** · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md)

Compositor Localization 是 Robbie Tilton 的 Compositor 的非官方多语言分支。Compositor 是一款用于图像合成和照片编辑的 macOS 开源图像编辑器。本分支的首个版本基于上游 Compositor 1.7.1。[上游项目](https://github.com/robbietilton/Compositor)

本分支只维护 Apple 芯片 Mac 上的 macOS 版本。

## 系统要求

- 装有 Apple 芯片的 Mac
- macOS 26 或更新版本
- 从源码构建需要 Xcode。上游持续集成使用 Xcode 26.6。

## 下载 macOS 版

在发布页下载 [`Compositor-Localization-1.7.2-macos-arm64.dmg`](https://github.com/coderscsy/Compositor-Localization/releases/download/v1.7.2/Compositor-Localization-1.7.2-macos-arm64.dmg)，适用于运行 **macOS 26 或更新版本的 Apple 芯片 Mac**。同页提供 `SHA256SUMS.txt` 用于校验下载文件。打开磁盘映像后，将应用复制到「应用程序」文件夹。[GitHub 预览发行版](https://github.com/coderscsy/Compositor-Localization/releases/tag/v1.7.2)

此应用使用临时签名（ad hoc signing），未经 Apple 公证。首次打开时，Gatekeeper 可能会阻止运行。你也可以按下文从源码构建。[Apple 的 Mac 应用打开指南](https://support.apple.com/zh-cn/102445)

## 主要功能

- **图层和蒙版。** 支持图层、文件夹、混合模式、剪贴蒙版和图层蒙版。可以随时编辑描边、投影和发光等图层效果。
- **变换和选区。** 支持非破坏性移动、缩放、旋转和翻转，以及标尺、参考线和网格吸附。可使用选框、套索、魔棒或对象选择工具创建选区，也可以自动选择主体。
- **绘制和修饰。** 提供画笔、橡皮擦、污点修复画笔、仿制图章和内容识别填充。形状、渐变和文字在创建后仍可编辑。
- **调整和滤镜。** 支持色阶、曲线、色相/饱和度、曝光、Camera Raw、模糊和降噪。调整带实时预览，也可以限制在选区内。
- **导入和导出。** 导入 JPEG、PNG、HEIC、TIFF、WebP、SVG、PDF、GIF、相机 RAW 以及 Photoshop PSD/PSB（8 位 RGB）。动画 GIF 可逐帧编辑。支持预览并导出为 PNG、JPEG、单页 PDF 或动画 GIF。
- **项目和快捷键。** 使用标签页同时打开多个项目，按 ⌘F 搜索命令和工具，在「编辑 → 键盘快捷键」中自定义快捷键。
- **项目自动化。** 脚本和 AI 智能体可以直接创建或编辑 `.comp` 项目。应用会实时更新已打开的项目。[编写 `.comp` 项目](../writing-comp-files.md)

## 界面语言

打开 **Compositor → 设置 → 界面语言**，选择语言后退出并重新打开应用。选择 **跟随系统** 会使用 macOS 为 Compositor 选定的语言，可在 **系统设置 → 通用 → 语言与地区 → 应用程序** 中调整。

- 英语（`en`）是源语言，也是未翻译文案的回退语言。
- 中文提供简体（`zh-Hans`）和繁体（`zh-Hant`）版本，繁体中文尽量采用台湾常用术语。
- 日语（`ja`）、韩语（`ko`）、法语（`fr`）、德语（`de`）和西班牙语（`es`）为预览版。常用控件已抽查，其余文案包含机器辅助翻译。

## 从源码构建

各版本的源码可通过对应的 Git 标签获取。以下命令使用默认分支。

```sh
git clone https://github.com/coderscsy/Compositor-Localization.git
cd Compositor-Localization
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build
open build/Build/Products/Release/Compositor.app
```

也可以在 Xcode 中打开 `Compositor.xcodeproj`，运行 **Compositor** scheme。Debug 和 Release 的本地构建均使用临时签名（ad hoc signing）、应用沙盒和独立的应用标识。

若要和上游应用并存，可将构建产物以 `Compositor Localization.app` 的名称复制到「应用程序」文件夹。更新本地构建时，请获取本分支的新版本并重新构建。

经原作者签名和公证的应用可从上游发行页下载。[上游发行页](https://github.com/robbietilton/Compositor/releases/latest)

仓库保留了上游发布流程所用的 `scripts/release.sh`、`scripts/publish.sh` 和 `appcast.xml`。

## 反馈与贡献

反馈 macOS 应用、翻译或文档问题时，请注明界面语言、出现问题的菜单或界面、当前显示的文字、应用版本以及 macOS 版本。若方便，可附上期望的译文或截图。[问题反馈](https://github.com/coderscsy/Compositor-Localization/issues)

可以通过拉取请求提交翻译修订。编辑本分支的字符串目录时，请保留格式占位符和快捷键，并在应用中检查修改后的文案。[字符串目录](../../Compositor/Resources/Localizable.xcstrings)

## 许可证

本分支采用 MIT 许可证。原始版权归 Wonder Assembly LLC 所有。[MIT 许可证](../../LICENSE)

体积光功能使用的深度模型 DepthMini 由 Depth Anything V2 Small（Apache-2.0）蒸馏而来，并以 torchvision 中使用 ImageNet 训练的 MobileNetV3 权重（BSD-3-Clause）为起点。首次打开体积光功能时会下载模型。[Depth Anything V2](https://github.com/DepthAnything/Depth-Anything-V2)
