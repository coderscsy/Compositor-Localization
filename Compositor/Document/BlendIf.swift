import Foundation

nonisolated enum BlendIfChannel: String, Codable, CaseIterable, Sendable {
    case gray = "Gray"
    case red = "Red"
    case green = "Green"
    case blue = "Blue"

    var index: Int32 {
        switch self {
        case .gray: 0
        case .red: 1
        case .green: 2
        case .blue: 3
        }
    }
}

/// Photoshop-style tonal hide range with optional split handles (`blackLow..blackHigh` and `whiteLow..whiteHigh`).
/// Pixels below `blackLow` or above `whiteHigh` are hidden; between `blackLow..blackHigh` and `whiteLow..whiteHigh`
/// opacity feathers linearly between 0 and 1.
nonisolated struct BlendIfRange: Codable, Equatable, Hashable, Sendable {
    var blackLow: Int = 0
    var blackHigh: Int = 0
    var whiteLow: Int = 255
    var whiteHigh: Int = 255

    var isIdentity: Bool {
        blackLow == 0 && blackHigh == 0 && whiteLow == 255 && whiteHigh == 255
    }

    var isValid: Bool {
        (0...255).contains(blackLow)
            && (0...255).contains(blackHigh)
            && (0...255).contains(whiteLow)
            && (0...255).contains(whiteHigh)
            && blackLow <= blackHigh
            && blackHigh <= whiteLow
            && whiteLow <= whiteHigh
    }

    var normalized: Self {
        let bLow = min(255, max(0, blackLow))
        let bHigh = min(255, max(bLow, blackHigh))
        let wHigh = min(255, max(bHigh, whiteHigh))
        let wLow = min(wHigh, max(bHigh, whiteLow))
        return Self(blackLow: bLow, blackHigh: bHigh, whiteLow: wLow, whiteHigh: wHigh)
    }

    func factor(for value: Double) -> Double {
        let low: Double
        if blackHigh > blackLow {
            low = min(1, max(0, (value - Double(blackLow)) / Double(blackHigh - blackLow)))
        } else {
            low = value >= Double(blackLow) ? 1 : 0
        }
        let high: Double
        if whiteHigh > whiteLow {
            high = min(1, max(0, (Double(whiteHigh) - value) / Double(whiteHigh - whiteLow)))
        } else {
            high = value <= Double(whiteHigh) ? 1 : 0
        }
        return low * high
    }
}

/// Per-layer (and per-folder) Blend If settings controlling visibility by source and underlying luminance or channel.
nonisolated struct BlendIfSettings: Codable, Equatable, Hashable, Sendable {
    var channel: BlendIfChannel = .gray
    var thisLayer = BlendIfRange()
    var underlyingLayer = BlendIfRange()

    var isIdentity: Bool { thisLayer.isIdentity && underlyingLayer.isIdentity }
    var isValid: Bool { thisLayer.isValid && underlyingLayer.isValid }

    var normalized: Self {
        Self(channel: channel, thisLayer: thisLayer.normalized, underlyingLayer: underlyingLayer.normalized)
    }

    /// Nil when every slider is at its default, so unchanged layers serialize nothing extra.
    var nonIdentity: Self? {
        let clean = normalized
        return clean.isIdentity ? nil : clean
    }

    var cParams: BlendIfParams {
        let clean = normalized
        return BlendIfParams(
            channel: clean.channel.index,
            thisBlackLow: Int32(clean.thisLayer.blackLow),
            thisBlackHigh: Int32(clean.thisLayer.blackHigh),
            thisWhiteLow: Int32(clean.thisLayer.whiteLow),
            thisWhiteHigh: Int32(clean.thisLayer.whiteHigh),
            underBlackLow: Int32(clean.underlyingLayer.blackLow),
            underBlackHigh: Int32(clean.underlyingLayer.blackHigh),
            underWhiteLow: Int32(clean.underlyingLayer.whiteLow),
            underWhiteHigh: Int32(clean.underlyingLayer.whiteHigh)
        )
    }
}

struct BlendIfEdit: Equatable {
    let layerID: UUID
    var settings: BlendIfSettings
    let original: BlendIfSettings?
}

extension EditorSession {
    func displayedBlendIf(for layer: ImageLayer) -> BlendIfSettings? {
        if let edit = blendIfEdit, edit.layerID == layer.id {
            return edit.settings.nonIdentity
        }
        return layer.blendIf?.nonIdentity
    }

    /// Whether a folder renders as an isolated transparency group rather than Pass Through.
    func isFolderIsolated(_ layer: ImageLayer) -> Bool {
        guard layer.isGroup else { return false }
        let mode = displayedBlendMode(for: layer)
        let blendIf = displayedBlendIf(for: layer)
        return !displayedFolderPassThrough(for: layer) || mode != .normal || blendIf != nil
    }

    var canEditBlendIf: Bool { canEditBlendMode }

    func openBlendIf() {
        guard canEditBlendIf, let layer = activeLayer else { return }
        if blendIfEdit?.layerID == layer.id { return }
        if blendIfEdit != nil { commitBlendIf() }
        blendIfEdit = BlendIfEdit(layerID: layer.id,
                                  settings: layer.blendIf ?? BlendIfSettings(),
                                  original: layer.blendIf)
        refreshCanvasPreview?()
    }

    func updateBlendIf(_ settings: BlendIfSettings) {
        guard var edit = blendIfEdit else { return }
        edit.settings = settings.normalized
        blendIfEdit = edit
        refreshCanvasPreview?()
    }

    func resetBlendIf() {
        updateBlendIf(BlendIfSettings())
    }

    func commitBlendIf() {
        guard let edit = blendIfEdit else { return }
        blendIfEdit = nil
        let clean = edit.settings.nonIdentity
        guard let index = document?.layers.firstIndex(where: { $0.id == edit.layerID }) else {
            refreshCanvasPreview?()
            return
        }
        if document?.layers[index].blendIf != clean {
            beginEdit("Blending Options")
            document?.layers[index].blendIf = clean
            endEdit()
        }
        refreshCanvasPreview?()
    }

    func cancelBlendIf() {
        guard blendIfEdit != nil else { return }
        blendIfEdit = nil
        refreshCanvasPreview?()
    }

    func setLayerBlendIf(_ settings: BlendIfSettings?) {
        guard canEditBlendIf, let id = activeLayerID,
              let index = document?.layers.firstIndex(where: { $0.id == id }) else { return }
        let clean = settings?.nonIdentity
        guard document?.layers[index].blendIf != clean else { return }
        beginEdit("Blending Options")
        document?.layers[index].blendIf = clean
        endEdit()
    }
}
