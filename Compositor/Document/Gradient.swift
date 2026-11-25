import AppKit

nonisolated enum GradientStyle: String, CaseIterable, Sendable {
    case foregroundToBackground = "Foreground to Background"
    case foregroundToTransparent = "Foreground to Transparent"
    case custom = "Custom"
}

/// Linear, Radial, Angle (conical), Reflected (mirrored linear), and Diamond gradient shapes.
nonisolated enum GradientShape: String, Codable, CaseIterable, Sendable {
    case linear = "Linear"
    case radial = "Radial"
    case angle = "Angle"
    case reflected = "Reflected"
    case diamond = "Diamond"

    var kernelIndex: Int32 {
        switch self {
        case .linear: 0
        case .radial: 1
        case .angle: 2
        case .reflected: 3
        case .diamond: 4
        }
    }
}

nonisolated struct GradientSettings: Equatable, Sendable {
    var shape = GradientShape.linear
    var style = GradientStyle.foregroundToTransparent
    var reversed = false
    var opacity: CGFloat = 1
    var customStops: [GradientOverlayStop] = GradientPreset.builtIn[1].stops
}

/// An uncommitted gradient on one layer or mask. Endpoints are document pixels;
/// the raster preview lives in `raster` and never touches the document until commit.
final class GradientEdit {
    let raster: BrushStroke
    var start: CGPoint
    var end: CGPoint
    init(raster: BrushStroke, start: CGPoint) {
        self.raster = raster
        self.start = start
        end = start
    }
    var hasLine: Bool { hypot(end.x - start.x, end.y - start.y) >= 0.5 }

    /// What the gradient is filled with, as it's dragged and set.
    struct Fill: Equatable {
        let shape: GradientShape
        let start: CGPoint
        let end: CGPoint
        let colors: [CGColor]
        let stops: [GradientOverlayStop]
        let opacity: CGFloat
    }
    var fill: Fill?
    /// The fill the raster's tiles hold. They're filled only when something reads them — the Core Graphics canvas, or
    /// the commit — as the GPU canvas draws 2-stop linear/radial gradients itself.
    private var filled: Fill?
    func applyFill() throws {
        guard let fill, fill != filled else { return }
        try raster.fillGradient(fill.shape, from: fill.start, to: fill.end, colors: fill.colors,
                                stops: fill.stops, opacity: fill.opacity)
        filled = fill
    }
}

extension EditorSession {
    func beginGradient(at point: CGPoint) {
        guard tool == .gradient, canPaint || gradientEdit != nil, let layer = activeLayer else { return }
        // Dragging a new line replaces the pending one on the same target.
        if let edit = gradientEdit, edit.raster.layer.id == layer.id, edit.raster.isMask == isMaskSelected {
            edit.start = point
            edit.end = point
            refreshGradient()
            return
        }
        guard canPaint else { brushError = paintRefusal; return }
        finishOpacityEdit()
        do {
            gradientEdit = GradientEdit(raster: try makeRasterEdit(for: layer, growsMask: true), start: point)
            brushRevision += 1
        } catch { brushError = error.localizedDescription }
    }

    func moveGradient(start: CGPoint? = nil, end: CGPoint? = nil) {
        guard let edit = gradientEdit else { return }
        if let start { edit.start = start }
        if let end { edit.end = end }
        refreshGradient()
    }

    /// Re-renders the pending gradient from the current endpoints, settings, and palette.
    func refreshGradient() {
        guard let edit = gradientEdit else { return }
        if edit.hasLine {
            edit.fill = GradientEdit.Fill(shape: gradientSettings.shape, start: edit.start, end: edit.end,
                                          colors: gradientColors(mask: edit.raster.isMask),
                                          stops: gradientStops(mask: edit.raster.isMask),
                                          opacity: gradientSettings.opacity)
        }
        brushRevision += 1
    }

    func gradientStops(mask: Bool) -> [GradientOverlayStop] {
        let raw: [GradientOverlayStop]
        switch gradientSettings.style {
        case .foregroundToBackground:
            let fg = paletteColor(background: false)
            let bg = paletteColor(background: true)
            raw = [
                GradientOverlayStop(position: 0, red: fg.red, green: fg.green, blue: fg.blue, alpha: 1),
                GradientOverlayStop(position: 1, red: bg.red, green: bg.green, blue: bg.blue, alpha: 1),
            ]
        case .foregroundToTransparent:
            let fg = paletteColor(background: false)
            raw = [
                GradientOverlayStop(position: 0, red: fg.red, green: fg.green, blue: fg.blue, alpha: 1),
                GradientOverlayStop(position: 1, red: fg.red, green: fg.green, blue: fg.blue, alpha: 0),
            ]
        case .custom:
            let sorted = gradientSettings.customStops.sorted { $0.position < $1.position }
            if mask {
                raw = sorted.map { stop in
                    let luma = 0.299 * stop.red + 0.587 * stop.green + 0.114 * stop.blue
                    return GradientOverlayStop(position: stop.position, red: luma, green: luma, blue: luma, alpha: stop.alpha)
                }
            } else {
                raw = sorted
            }
        }
        guard gradientSettings.reversed else { return raw }
        return raw.reversed().map {
            GradientOverlayStop(position: 1 - $0.position, red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
        }
    }

    func gradientColors(mask: Bool) -> [CGColor] {
        let space = mask ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
        return gradientStops(mask: mask).map { stop in
            CGColor(colorSpace: space, components: mask ? [stop.red, stop.alpha] : [stop.red, stop.green, stop.blue, stop.alpha])!
        }
    }

    /// Ends a drag; a click without a line leaves nothing pending.
    func endGradientDrag() {
        if gradientEdit?.hasLine == false { cancelGradient() }
    }

    func cancelGradient() {
        guard gradientEdit != nil else { return }
        gradientEdit = nil
        brushRevision += 1
    }

    func commitGradient() async {
        guard let edit = gradientEdit, !isProjectBusy else { return }
        guard edit.hasLine else { cancelGradient(); return }
        do {
            try edit.applyFill()
            try await commitRasterEdit(edit.raster, name: edit.raster.isMask ? "Gradient Mask" : "Gradient")
        } catch { brushError = error.localizedDescription }
        if gradientEdit === edit { cancelGradient() }
    }

    /// Switching tools, layers, or targets applies the pending gradient, as in Photoshop.
    func resolveGradient() {
        guard gradientEdit != nil else { return }
        Task { await commitGradient() }
    }
}
