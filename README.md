# Compositor Localization

**[Download for macOS v1.8.0 · 下载 DMG](https://github.com/coderscsy/Compositor-Localization/releases/download/v1.8.0/Compositor-Localization-1.8.0-macos-arm64.dmg)** · [Releases](https://github.com/coderscsy/Compositor-Localization/releases) · [Changelog](CHANGELOG.md)

**English** · [简体中文](docs/readme/README.zh-Hans.md) · [繁體中文](docs/readme/README.zh-Hant.md) · [日本語](docs/readme/README.ja.md) · [한국어](docs/readme/README.ko.md) · [Français](docs/readme/README.fr.md) · [Deutsch](docs/readme/README.de.md) · [Español](docs/readme/README.es.md)

Compositor Localization is an unofficial multilingual fork of [Robbie Tilton’s Compositor](https://github.com/robbietilton/Compositor), an open-source image editor for compositing and photo editing. Development, testing, and releases for this fork focus exclusively on **macOS on Apple silicon**. The first release is based on upstream Compositor 1.7.1, and **v1.8.0** adds comprehensive Photoshop-class retouching, brush, vector, typography, transform, selection, panel, and export upgrades.

## Download for macOS

The public preview requires **Apple silicon and macOS 26 or later**. The release also includes `SHA256SUMS.txt` to verify the download. Open the disk image and copy the app to Applications. [GitHub v1.8.0 release](https://github.com/coderscsy/Compositor-Localization/releases/tag/v1.8.0)

The app uses ad hoc signing and has not been notarized by Apple. Gatekeeper may block it the first time you open it. You can also build the app from source. [Apple’s guide to opening Mac apps](https://support.apple.com/en-us/102445)

## Language support

Use **Compositor → Settings → Interface Language** and relaunch the app after changing the setting. **System Default** follows the language macOS selects for Compositor. You can set the app’s macOS language in **System Settings → General → Language & Region → Applications**. English is the source and fallback language.

- English (`en`)
- 简体中文 · Simplified Chinese (`zh-Hans`)
- 繁體中文 · Traditional Chinese (`zh-Hant`)
- 日本語 · Japanese (`ja`)
- 한국어 · Korean (`ko`)
- Français · French (`fr`)
- Deutsch · German (`de`)
- Español · Spanish (`es`)

French, German, Spanish, Japanese, and Korean are preview localizations. Common controls have been spot-checked, and the rest of the interface includes machine-assisted translations. Traditional Chinese uses Taiwanese terminology where possible.

## Build from source

The source for each version is available from the corresponding Git tag. Build with Xcode on a Mac with Apple silicon running macOS 26 or later. Upstream CI uses Xcode 26.6.

```sh
git clone https://github.com/coderscsy/Compositor-Localization.git
cd Compositor-Localization
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build
open build/Build/Products/Release/Compositor.app
```

You can also open `Compositor.xcodeproj` in Xcode and run the **Compositor** scheme. Debug and Release use ad hoc signing for local builds, with an app sandbox and a separate bundle identifier. To keep both editions in your Applications folder, copy the resulting app as `Compositor Localization.app`. To update your local build, rebuild from a newer fork release.

For the signed and notarized upstream app, see [Robbie Tilton’s release page](https://github.com/robbietilton/Compositor/releases/latest).

The inherited `scripts/release.sh`, `scripts/publish.sh`, and `appcast.xml` belong to the upstream release process.

## Report issues and contribute

Use this fork’s [issue tracker](https://github.com/coderscsy/Compositor-Localization/issues) for macOS bugs and translation issues. Include your interface language, the affected menu or panel, the text you see, and your Compositor and macOS versions. A screenshot of the affected area helps when it can be shared.

Interface translations live in [Localizable.xcstrings](Compositor/Resources/Localizable.xcstrings). Send changes to this fork through a pull request and test them on a Mac.

## Features

### Layers
- Layers and folders, with **Layer Lock** (transparent pixels, image pixels, position, or lock all), **Fill Opacity** decoupled from Layer Styles, and Photoshop's full set of blend modes (including Dissolve, Darker Color, and Lighter Color), **Blend If** tonal visibility sliders, and isolated folder blend modes
- Layer masks and **non-destructive Vector Masks**: paint, fill, invert, blur, feather, clip with Bézier paths, or link/unlink masks to transform independently
- Clipping masks and folder masks
- Adjustment layers: Hue/Saturation, Levels, Curves, Exposure, Gradient Map, Grain, Black & White, Color Balance, Invert, **Brightness/Contrast, Vibrance, Selective Color, Color Lookup (`.cube` 3D LUTs), Threshold, Posterize**, and **Live Gradient Fill** layers; plus filter layers including **High Pass**, Gaussian Blur, Motion Blur, Progressive Blur, Sharpen, Reduce Noise, Noise, Vignette, Bloom / Glow, RGB Split, Lens Effects, and Tonal Contrast
- Complete **Layer Styles**: Stroke (Outside / Center / Inside), Drop Shadow, Inner Shadow, Outer Glow, Inner Glow, Color Overlay, **Bevel & Emboss**, **Gradient Overlay**, and **Pattern Overlay**, with per-effect blend modes and spread/choke controls
- Merge Down, Merge Layers and Merge Group (⌘E)
- Duplicate, rename inline, reorder and nest by drag and drop; Option-drag to duplicate; a right-click menu in the Layers panel
- Copy and paste whole layers and folders (⌘C/⌘V with no selection), within a project or between projects, or drag them between projects

### Transform & Crop
- Non-destructive move, scale, rotate and flip with a **9-point Pivot reference grid**, independent **Skew X/Y**, free distort (⌘-drag), and **3×3 bicubic Bézier Mesh Warp** (with 5 presets and 16 draggable control points)
- **Crop upgrade**: Straighten horizon drag & `-45°…45°` rotation, composition overlays (Rule of Thirds, Golden Ratio, Diagonal, Grid), non-destructive vs. Delete Cropped Pixels toggle, and **4-corner Perspective Crop**
- Transform several layers, or a whole folder, together
- Snapping to canvas and layer edges and centers, with guides
- Distances (View › Show › Distances): pixel gaps to the canvas edges and nearby layers while moving a layer, and to the layer under the pointer with ⌘ held
- Exact values for position, size, scale and angle, stepped with the arrow keys
- Flip Layer and Flip Canvas, horizontal and vertical
- Align and Distribute layers to each other, the selection or the canvas, from the Move tool's bar or the Layer menu

### Selections
- Rectangle and Ellipse Marquee, Freehand and Polygonal Lasso, and the Magic tool — Wand selects by color, Object traces whatever you click (Tab switches)
- **Quick Mask mode (`Q`)** with ruby overlay and live brush painting, **Border / Smooth / Select Similar**, and a dedicated **Select and Mask** workspace (Smooth, Feather, Contrast, Shift Edge, Decontaminate Colors, 4 view modes, and flexible output targets)
- Select Subject, Expand, Contract, Feather, and Content-Aware Fill (including extending an image past its edges)
- Add to and subtract from selections, move the outline, load a layer's pixels or mask as a selection

### Painting, Retouching, Vectors & Typography
- **Brush engine & Photoshop `.abr` import**: import `.abr` brush packs (v1/v2/v6/v10 sampled bitmap tips) into a persistent local Brush Library, create/save custom presets, and paint with Flow, Airbrush, 12 brush blend modes (including Behind & Clear), Spacing, Angle, Roundness, Scatter, Size/Angle/Opacity Jitter, Smoothing, Anti-alias toggle, and tablet pen pressure
- **Paint Bucket** flood fill (tolerance, contiguous, sample all layers, blend modes) grouped with the **Gradient tool** (multi-stop editor, Linear/Radial/Angle/Reflected/Diamond, and Live Gradient Fill layers)
- **Dodge, Burn & Sponge (`O`)** and **Sharpen Brush (`R`)**, alongside Blur, Smudge, **multi-brush Liquify** (Forward/Bloat/Pucker/Twirl/Push/Reconstruct + Freeze Mask), **Manual-sample Healing Brush** (Poisson seamless blending), Spot Healing Brush, and Clone Stamp
- **Pen tool (`P`) & Bézier Paths**: anchor/handle editing, Direct Selection, Convert Point, **Paths panel**, Path ↔ Selection conversion, Fill/Stroke Path, and **Shape/Path Boolean operations** (Unite, Subtract, Intersect, Exclude)
- **Shape tool**: Rectangles, Rounded Rectangles, Ellipses, Lines, **Triangles, Polygons (3–32 sides), and Stars**, with Inside/Center/Outside strokes and Solid/Dotted/Dashed/Long Dash styles
- **Type tool (`T`)**: inline multiline editing, **Vertical text**, underline/strikethrough/all caps/baseline shift/justified alignment, **Warp Text** (7 presets with bend & H/V distortion), and **Text on Path**
- Eyedropper and a full color picker

### Adjustments, Filters & Panels
- Camera Raw filter: light, color, curves, color mixer, color grading, detail, optics and geometry, in a panel beside the canvas; each section resets to its defaults from its header
- Full adjustment & filter suite including **High Pass**, **Offset** (seamless tile wrap), **Brightness/Contrast**, **Vibrance**, **Selective Color**, **Color Lookup (`.cube` 3D LUTs)**, **Threshold**, **Posterize**, Levels, Curves, Hue/Saturation, Exposure, Gradient Map, Grain, Black & White, Color Balance, Invert, Gaussian/Motion/Progressive Blur, Sharpen, Reduce Noise, Vignette, Bloom/Glow, Lens Effects, Tonal Contrast, Volumetric Light, Rim Light, Lens Correction, and Remove Background
- **Professional floating panels**: **History panel** (one-click state jump + named Snapshots), **Info panel** (live cursor X/Y + RGBA/Hex/HSB/CMYK sampling), persistent **Histogram panel** (RGB/Luminosity/channel statistics), **Paths panel**, and **Navigator** minimap
- Live previews, limited to the selection when there is one, and Last Filter (⌃⌘F)

### Canvas and files
- Multiple projects in tabs, Search Commands (⌘F), Toggle Fullscreen (F), Rulers (⌘R), Guides, Layout Grid, Snap To, Canvas Size, Image Size, and Trim
- Import JPEG, PNG, HEIC, TIFF, WebP, SVG, PDF, animated GIF, camera RAW, and Photoshop PSD/PSB (including artboards, folders, masks, blend modes, Blend If, 9 native adjustment layer types, shapes, and text)
- Export PNG (⇧⌘E) and Export As (⇧⌥⌘S, or ⇧⌥⌘W) for **PNG, JPEG, lossless WebP, HEIC, TIFF, PDF, animated GIF, EXR, Channel Pack, and high-fidelity PSD** (preserving layers, folders, masks, 9 native adjustment layer types, Blend If, Fill Opacity, and `lrFX` layer effects); Copy Merged
- Photoshop-style keyboard shortcuts throughout, remappable in Edit > Keyboard Shortcuts, and scrubbable numeric labels

### Works with AI agents
- AI agents and scripts can build and edit projects directly: a `.comp` is a folder of PNG layers and a manifest, and an open project updates live as it's written. See [Writing Compositor projects](docs/writing-comp-files.md)

## License

This fork uses the [MIT License](LICENSE). The original copyright belongs to Wonder Assembly LLC.

Volumetric Light's depth model, DepthMini, is distilled from [Depth Anything V2 Small](https://github.com/DepthAnything/Depth-Anything-V2)
(Apache-2.0) and starts from torchvision's ImageNet-trained MobileNetV3 weights (BSD-3-Clause). It isn't in the app:
it's downloaded the first time Volumetric Light opens.
