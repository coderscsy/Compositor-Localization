# Changelog · 更新日志

## v1.8.1 (Build 81) — Rendering Orientation Fixes

### English
- **Rendering Fixes**: Preserved upright top-left image orientation when reading `CGImage` sources into flipped `BrushRaster` bitmap contexts across:
  - **Warp Text** (`TypographyRenderer.applyWarp`): fixed vertically mirrored warped text output.
  - **Select and Mask & Select Similar** (`SelectionRefinement`): fixed inverted preview, mask refinement, edge color decontamination, and color sampling coordinates.
  - **3×3 Mesh Warp** (`WarpMesh.render`): fixed vertically flipped source sampling during mesh deformation.
  - **Perspective Crop** (`CropProcessor.trimToOpaqueBounds`) & **Histogram** (`HistogramStats.compute`): unified upright `BrushRaster.draw` pixel reading.

### 简体中文
- **渲染坐标系修复**：统一修复 5 个模块在翻转后的 `BrushRaster` 绘图上下文中读取 `CGImage` 导致的 Y 轴垂直倒置问题：
  - **文字变形（Warp Text）**：修复变形后文字上下翻转的问题。
  - **「选择并遮住」与选取相似**：修复预览画面、遮罩精修、边缘颜色净化及颜色采样坐标倒置的问题。
  - **3×3 网格变形（Mesh Warp）**：修复变形采样源图像垂直翻转的问题。
  - **透视裁剪与直方图**：统一使用正向 `BrushRaster.draw` 读取像素并计算裁剪边界。

---

## v1.8.0 (Build 80) — Photoshop-Class Feature Parity & `.abr` Brushes

### English

#### Layers, Blending & Styles
- **Layer Lock** (`.comp` v23): Lock Transparent Pixels, Lock Image Pixels, Lock Position, and Lock All with folder lock inheritance and canvas edit guards.
- **Fill Opacity** (`.comp` v24): Separate Fill slider decoupled from Layer Effects across Metal GPU, CPU, and exports.
- **Advanced Blending** (`.comp` v26): Added Dissolve, Darker Color, and Lighter Color blend modes; per-layer/folder **Blend If** tonal visibility sliders (Gray/R/G/B with split feathering); and isolated folder blend modes.
- **Extended Layer Styles** (`.comp` v28): Added **Bevel & Emboss**, **Gradient Overlay**, **Pattern Overlay**, Center stroke position, shadow/glow Spread & Choke, and per-effect blend modes.

#### Painting, Brushes, Gradients & Retouching
- **Photoshop `.abr` Brush Import & Brush Library**: Import `.abr` brush packs (v1/v2/v6/v10 sampled bitmap tips) into a persistent local library, save/manage custom presets, and paint with Spacing, Angle, Roundness, Scatter (count & both axes), and Size/Angle/Opacity Jitter.
- **Brush Engine Upgrade**: Added Flow, Airbrush continuous deposition, 12 brush blend modes (including Behind & Clear), and **Paint Bucket** flood-fill tool.
- **Retouching Tools**: Added **Dodge, Burn & Sponge (`O`)**, **Sharpen Brush (`R`)**, **multi-brush Liquify** (Forward Warp, Bloat, Pucker, Twirl CW/CCW, Push Left, Reconstruct, plus Freeze/Thaw Mask), and **Manual-sample Healing Brush** (Option-click source + Poisson seamless blending).
- **Gradient Upgrade** (`.comp` v29): Multi-stop gradient editor, Angle/Reflected/Diamond shapes, and non-destructive **Live Gradient Fill** layers.

#### Adjustments & Filters (`.comp` v25)
- Added **High Pass**, **Offset** (seamless wrap), **Brightness/Contrast**, **Vibrance**, **Selective Color**, **Color Lookup** (`.cube` 3D LUTs), **Threshold**, and **Posterize** — available as both destructive filters and non-destructive adjustment layers.

#### Vectors & Typography
- **Shapes Upgrade** (`.comp` v30): Triangle, Polygon (3–32 sides), and Star shapes, plus Inside/Center/Outside strokes and Solid/Dotted/Dashed/Long Dash styles.
- **Pen Tool (`P`) & Paths** (`.comp` v31): Cubic Bézier drawing, Direct Selection, Convert Point, **Paths panel**, Path ↔ Selection conversion, and Fill/Stroke Path.
- **Vector Masks & Booleans** (`.comp` v32): Non-destructive per-layer Vector Masks (CPU/GPU/Export clipping, invert, toggle, rasterize) and Shape/Path Boolean operations (Unite, Subtract, Intersect, Exclude).
- **Typography Upgrade** (`.comp` v33): Vertical text layout, Underline/Strikethrough/All Caps/Baseline Shift/Justified alignment, **Warp Text** (7 presets with bend & H/V distortion), and **Text on Path**.

#### Crop, Transform, Selection & Workflow Panels
- **Crop Upgrade**: Straighten tool & `-45°…45°` rotation, 5 composition overlays (Rule of Thirds, Golden Ratio, Diagonal, Grid, None), non-destructive crop toggle, and 4-corner **Perspective Crop**.
- **Advanced Transform**: 9-point Pivot reference grid, independent Skew X/Y, and **3×3 bicubic Bézier Mesh Warp** (16 control points + 5 presets).
- **Selection Refinement**: **Quick Mask (`Q`)** with ruby overlay and live brush editing, Border/Smooth/Select Similar, and **Select and Mask** floating workspace.
- **Professional Panels**: **History panel** (one-click state jump + named Snapshots), **Info panel** (live X/Y + RGBA/Hex/HSB/CMYK sampling), and persistent **Histogram panel** (RGB/Luminosity/channel statistics).

#### Export & PSD Interoperability
- Added **lossless WebP** (`VP8L` RGBA) and **HEIC** export in Export As.
- Upgraded PSD reader/writer for lossless round-trip of **9 native Photoshop adjustment layer types** (`levl`, `curv`, `hue2`, `brit`, `blnc`, `nvrt`, `post`, `thrs`, `expA`), **Blend If** tables, **Fill Opacity (`iOpa`)**, and **Layer Effects (`lrFX`)**.

---

### 简体中文

#### 图层、混合与样式
- **图层锁定**（`.comp` v23）：支持锁定透明像素、锁定图像像素、锁定位置与全部锁定，支持文件夹锁定继承。
- **填充不透明度**（`.comp` v24）：独立于图层不透明度与图层样式解耦渲染（GPU/CPU/导出全链路一致）。
- **高级混合**（`.comp` v26）：补全溶解、深色、浅色混合模式，新增**混合颜色带（Blend If）**与文件夹独立隔离混合模式。
- **图层样式补全**（`.comp` v28）：新增**斜面和浮雕**、**渐变叠加**、**图案叠加**、居中描边、扩展/阻塞与各效果独立混合模式。

#### 画笔、`.abr` 导入、渐变与精修
- **Photoshop `.abr` 笔刷导入与本地笔刷库**：支持导入 `.abr` 笔刷包（v1/v2/v6/v10 采样位图笔尖）、保存与管理自定义预设，并支持间距、角度、圆度、散布（数量与双轴）以及大小/角度/不透明度抖动。
- **画笔引擎升级**：新增流量（Flow）、喷枪持续上色、12 种画笔混合模式（含背后/清除）及**油漆桶**填充工具。
- **精修工具**：新增**减淡 / 加深 / 海绵（`O`）**、**锐化画笔（`R`）**、**多笔刷液化**（含冻结/解冻蒙版）及**手动取样泊松修复画笔**。
- **渐变升级**（`.comp` v29）：多色标渐变编辑器、角度/对称/菱形渐变与非破坏性**实时渐变填充图层**。

#### 调色与滤镜（`.comp` v25）
- 新增**高反差保留**、**位移**、**亮度/对比度**、**自然饱和度**、**可选颜色**、**颜色查找（`.cube` 3D LUT）**、**阈值**与**色调分离**，支持破坏性滤镜与非破坏性调整层双模式。

#### 矢量与文字排版
- **形状升级**（`.comp` v30）：三角形、多边形（3–32 边）、星形，支持内部/居中/外部描边与虚线样式。
- **钢笔工具（`P`）与路径**（`.comp` v31）：贝塞尔绘制、直接选择、转换点、**路径面板**、路径与选区互转、填充/描边路径。
- **矢量蒙版与布尔运算**（`.comp` v32）：非破坏性图层矢量蒙版与形状/路径布尔运算（合并/减去/交集/排除重叠）。
- **文字排版增强**（`.comp` v33）：竖排文字、下划线/删除线/全大写/基线偏移/两端对齐、**文字变形**（7 种预设）与**路径文字**。

#### 裁剪、变形、选区与工作流面板
- **裁剪增强**：拉直与旋转、5 种构图参考线、非破坏性裁剪开关、4 角点**透视裁剪**。
- **高阶变形**：9 点自定义变换参考点（Pivot）、独立水平/垂直斜切（Skew）与 **3×3 双三次网格变形（Warp）**。
- **选区精修**：**快速蒙版（`Q`）**、边界/平滑/选取相似与独立**「选择并遮住」**工作区。
- **专业面板**：**历史记录面板**（含命名快照）、**信息面板**（实时坐标与 RGBA/Hex/HSB/CMYK 采样）及常驻**直方图面板**。

#### 导出与 PSD 互通
- 新增**无损 WebP**（含透明通道）与 **HEIC** 导出。
- 升级 PSD 读写：原生无损互通 **9 类 Photoshop 调整图层**（色阶、曲线、色相/饱和度、亮度/对比度、色彩平衡、反相、色调分离、阈值、曝光度），并保留**混合颜色带**、**填充不透明度（`iOpa`）**与**图层样式（`lrFX`）**。

---

## v1.7.2 (Build 78) — Initial Multilingual macOS Release
- Based on upstream Compositor 1.7.1 with complete Simplified Chinese (`zh-Hans`), Traditional Chinese (`zh-Hant`), and preview localizations for Japanese, Korean, French, German, and Spanish.
- First verified Apple silicon macOS disk image (`Compositor-Localization-1.7.2-macos-arm64.dmg`) with multilingual documentation.
