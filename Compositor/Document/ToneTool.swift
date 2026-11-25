import AppKit

/// Modes of the Toning tool (O): Dodge lightens, Burn darkens, Sponge shifts saturation.
nonisolated enum ToneToolMode: String, CaseIterable, Sendable {
    case dodge = "Dodge"
    case burn = "Burn"
    case sponge = "Sponge"
}

/// Tonal range targeted by Dodge and Burn.
nonisolated enum ToneRange: String, CaseIterable, Sendable {
    case shadows = "Shadows"
    case midtones = "Midtones"
    case highlights = "Highlights"

    var kernelValue: Int32 {
        switch self {
        case .shadows: 0
        case .midtones: 1
        case .highlights: 2
        }
    }
}

/// Direction of the Sponge tool.
nonisolated enum SpongeMode: String, CaseIterable, Sendable {
    case saturate = "Saturate"
    case desaturate = "Desaturate"
}

/// Options-bar state for Dodge, Burn, and Sponge.
nonisolated struct ToneToolSettings: Equatable, Sendable {
    var mode: ToneToolMode = .dodge
    var range: ToneRange = .midtones
    var spongeMode: SpongeMode = .saturate
    var protectTones = true

    var kernelMode: Int32 {
        switch mode {
        case .dodge: 0
        case .burn: 1
        case .sponge: spongeMode == .saturate ? 2 : 3
        }
    }

    var editName: String {
        switch mode {
        case .dodge: "Dodge"
        case .burn: "Burn"
        case .sponge: spongeMode == .saturate ? "Saturate" : "Desaturate"
        }
    }
}

extension EditorSession {
    /// Lazy per-tile adjusted copy of the active layer's pixels for Dodge, Burn, or Sponge.
    /// Computed only for regions the brush actually touches, keeping alpha unchanged.
    func toneSample(for stroke: BrushStroke, exposure: CGFloat) -> (sample: (image: CGImage, placed: CGRect, inGrid: Bool), render: (CGRect) -> CGImage?)? {
        guard !stroke.isMask, let image = stroke.layer.asset?.image else { return nil }
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        let mode = toneSettings.kernelMode
        let range = toneSettings.range.kernelValue
        let protect: Int32 = toneSettings.protectTones ? 1 : 0
        let strength = Float(min(1, max(0.01, exposure)))
        let render: (CGRect) -> CGImage? = { part in
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            let clipped = part.integral.intersection(bounds)
            guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1,
                  let cropped = image.cropping(to: clipped),
                  let context = try? BrushRaster.context(width: cropped.width, height: cropped.height, mask: false),
                  let data = context.data else { return nil }
            BrushRaster.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height), mask: false, context: context)
            tone_adjust_rgba(data.assumingMemoryBound(to: UInt8.self), cropped.width, cropped.height, context.bytesPerRow,
                             mode, range, strength, protect)
            return context.makeImage()
        }
        return ((image, stroke.sourceRect, true), render)
    }
}
