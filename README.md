# Compositor Localization

**English** · [简体中文](docs/readme/README.zh-Hans.md) · [繁體中文](docs/readme/README.zh-Hant.md) · [日本語](docs/readme/README.ja.md) · [한국어](docs/readme/README.ko.md) · [Français](docs/readme/README.fr.md) · [Deutsch](docs/readme/README.de.md) · [Español](docs/readme/README.es.md)

Compositor Localization is an unofficial multilingual fork of [Robbie Tilton’s Compositor](https://github.com/robbietilton/Compositor), an open-source image editor for compositing and photo editing. Development, testing, and releases for this fork focus exclusively on **macOS on Apple silicon**. The first release is based on upstream Compositor 1.7.1.

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

The [fork releases](https://github.com/coderscsy/Compositor-Localization/releases) provide tagged source code. Build with Xcode on a Mac with Apple silicon running macOS 26 or later. Upstream CI uses Xcode 26.6.

```sh
git clone https://github.com/coderscsy/Compositor-Localization.git
cd Compositor-Localization
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build
open build/Build/Products/Release/Compositor.app
```

You can also open `Compositor.xcodeproj` in Xcode and run the **Compositor** scheme. Debug and Release use ad hoc signing for local builds, with an app sandbox and a separate bundle identifier. To keep both editions in your Applications folder, copy the resulting app as `Compositor Localization.app`. To update it, rebuild from a newer fork release.

For the signed and notarized upstream app, see [Robbie Tilton’s release page](https://github.com/robbietilton/Compositor/releases/latest).

The inherited `scripts/release.sh`, `scripts/publish.sh`, and `appcast.xml` belong to the upstream release process. This fork publishes tagged source through its own GitHub Releases page.

## Report issues and contribute

Use this fork’s [issue tracker](https://github.com/coderscsy/Compositor-Localization/issues) for macOS bugs and translation issues. Include your interface language, the affected menu or panel, the text you see, and your Compositor and macOS versions. A screenshot of the affected area helps when it can be shared.

Interface translations live in [Localizable.xcstrings](Compositor/Resources/Localizable.xcstrings). Send changes to this fork through a pull request and test them on a Mac.

## Features

### Layers
- Layers and folders, with opacity and Photoshop's full set of blend modes in its order — a folder's opacity dims everything inside it
- Layer masks: paint, fill, invert, blur and feather them anywhere on the canvas, past the layer's own pixels; link or unlink them to transform a mask on its own
- Clipping masks and folder masks
- Adjustment layers: Hue/Saturation, Levels, Curves, Exposure, Gradient Map, Grain, Black & White, Color Balance, Invert, and filter layers: Gaussian Blur, Motion Blur, Progressive Blur, Sharpen, Reduce Noise, Noise, Vignette, Bloom / Glow, RGB Split, Lens Effects and Tonal Contrast
- Layer effects: Stroke, Drop Shadow, Color Overlay, Inner Shadow, Outer Glow and Inner Glow, rendered on the GPU and editable at any time
- Merge Down, Merge Layers and Merge Group (⌘E)
- Duplicate, rename inline, reorder and nest by drag and drop; Option-drag to duplicate; a right-click menu in the Layers panel
- Copy and paste whole layers and folders (⌘C/⌘V with no selection), within a project or between projects, or drag them between projects

### Transform
- Non-destructive move, scale, rotate and flip — images keep their full resolution however small you make them
- Free distort (⌘-drag a handle), with Shift to lock to an axis
- Transform several layers, or a whole folder, together
- Snapping to canvas and layer edges and centers, with guides
- Distances (View › Show › Distances): pixel gaps to the canvas edges and nearby layers while moving a layer, and to the layer under the pointer with ⌘ held
- Exact values for position, size, scale and angle, stepped with the arrow keys
- Flip Layer and Flip Canvas, horizontal and vertical
- Align and Distribute layers to each other, the selection or the canvas, from the Move tool's bar or the Layer menu

### Selections
- Rectangle and Ellipse Marquee, Freehand and Polygonal Lasso, and the Magic tool — Wand selects by color, Object traces whatever you click (Tab switches)
- Select Subject, and Expand, Contract and Feather on any selection
- Add to and subtract from selections, move the outline, or move and duplicate the pixels inside
- Load a layer's pixels or a mask as a selection
- Content-Aware Fill, which can also extend an image past its edges

### Painting and retouching
- Brush with size, hardness, opacity and smoothing, in Paint or Erase mode (B and E), and Shift for straight lines
- Pen pressure for the Brush's size and opacity, on a graphics tablet
- Spot Healing Brush (content-aware)
- Clone Stamp, aligned or not, sampling one layer or all of them
- Blur tool, on pixels or masks
- Gradient tool and Shape tool (rectangles, rounded rectangles, ellipses and lines), which stay editable rather than being rasterized
- Type tool (T): inline multiline editing in draggable, resizable paragraph boxes; font, size, color, alignment and spacing in the tool header; transform text and use it as a clipping mask
- Eyedropper and a full color picker

### Adjustments and filters
- Camera Raw filter: light, color, curves, color mixer, color grading, detail, optics and geometry, in a panel beside the canvas; each section resets to its defaults from its header
- Levels (with Auto), Curves, Hue/Saturation, Exposure, Gradient Map, Grain, Black & White, Color Balance and Invert
- Gaussian Blur and Motion Blur that spread past a layer's edges
- Sharpen, Reduce Noise, Add Noise, Vignette, Bloom / Glow, Dither, Scanlines, RGB Split, Lens Effects (anamorphic flare, starburst, mist, prism and bokeh in round, hexagon, oval or cat's-eye shapes), Tonal Contrast, Volumetric Light (fog that thickens with distance around the subject, lit by a light you place, with the photo's own lights glowing into it and optional beams), Rim Light (up to three colored lights behind the subject, with glow that wraps it into the light), Lens Correction and Remove Background
- Live previews, limited to the selection when there is one
- Last Filter (⌃⌘F) runs the last filter again with the same settings

### Canvas and files
- Multiple projects in tabs
- Search Commands (⌘F): find every menu command and tool by name, as in Raycast or Obsidian, and run it with Return
- Toggle Fullscreen (F): the canvas alone on black over the whole screen, with every panel put away; F or Esc brings them back
- Rulers (⌘R), guides dragged from them, a layout grid with adjustable spacing and subdivisions, and Snap To for guides, grid, layers and document bounds
- Crop with snapping, ratios including 3:4 and 9:16, and Option for symmetric cropping; with a selection, the crop starts at it
- Canvas Size, Image Size and Trim
- The tool bar moves into two columns when the window is too short for one
- A Navigator minimap in the canvas's corner from 300% zoom: the whole document in small with a box around the view; click or drag to move there (View › Navigator)
- Sharp high-quality downsampling when zoomed out, and a pixel grid when zoomed in
- Import JPEG, PNG, HEIC, TIFF, WebP, SVG, PDF (every page its own layer, at 300 DPI or fitted to the canvas), animated GIF (one layer whose frames show in a strip under the canvas, to play, paint on, duplicate, delete and retime), camera RAW (with a develop step first) and Photoshop PSD and PSB (8-bit RGB; not CMYK). Each Photoshop artboard opens in a tab of its own; folders, masks, blend modes, fill rectangles/ellipses, and simple horizontal text stay editable; other vectors and vertical text become pixels. A conversion report is shown before anything is applied.
- Large documents: the memory budget scales with your Mac, and a Photoshop file too big to open has its layers cropped to the canvas instead
- Export PNG (⇧⌘E) and Export As (⇧⌥⌘S, or ⇧⌥⌘W) for PNG, JPEG, a one-page PDF at the print size or, with a GIF layer, an animated GIF, scaled if you like, with a live preview, JPEG quality and file size; Channel Pack in Export As packs layers into a PNG's red, green, blue and alpha for game textures, and RGB Split's Split to Layers turns a layer back into those four; right-click layers in the Layers panel to export each as its own PNG, trimmed to its pixels; Copy Merged
- Keep working while a project saves
- Photoshop-style keyboard shortcuts throughout, remappable in Edit > Keyboard Shortcuts
- Drag a number's label to scrub its value, as in Photoshop

### Works with AI agents
- AI agents and scripts can build and edit projects directly: a `.comp` is a folder of PNG layers and a manifest, and an open project updates live as it's written. See [Writing Compositor projects](docs/writing-comp-files.md)

## License

This fork uses the [MIT License](LICENSE). The original copyright belongs to Wonder Assembly LLC.

Volumetric Light's depth model, DepthMini, is distilled from [Depth Anything V2 Small](https://github.com/DepthAnything/Depth-Anything-V2)
(Apache-2.0) and starts from torchvision's ImageNet-trained MobileNetV3 weights (BSD-3-Clause). It isn't in the app:
it's downloaded the first time Volumetric Light opens.
