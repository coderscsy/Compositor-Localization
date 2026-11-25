import Foundation
import CoreGraphics

nonisolated enum LayerBlendMode: String, Codable, CaseIterable, Sendable {
    case normal = "Normal", dissolve = "Dissolve"
    case darken = "Darken", multiply = "Multiply", colorBurn = "Color Burn"
    case linearBurn = "Linear Burn", darkerColor = "Darker Color"
    case lighten = "Lighten", screen = "Screen", colorDodge = "Color Dodge"
    case linearDodge = "Linear Dodge (Add)", lighterColor = "Lighter Color"
    case overlay = "Overlay", softLight = "Soft Light", hardLight = "Hard Light"
    case vividLight = "Vivid Light", linearLight = "Linear Light", pinLight = "Pin Light", hardMix = "Hard Mix"
    case difference = "Difference", exclusion = "Exclusion", subtract = "Subtract", divide = "Divide"
    case hue = "Hue", saturation = "Saturation", color = "Color", luminosity = "Luminosity"

    /// Photoshop's grouping: normal/dissolve, then darkening, lightening, contrast,
    /// comparative, and component modes. The menu draws a line between each group.
    static let groups: [[LayerBlendMode]] = [
        [.normal, .dissolve],
        [.darken, .multiply, .colorBurn, .linearBurn, .darkerColor],
        [.lighten, .screen, .colorDodge, .linearDodge, .lighterColor],
        [.overlay, .softLight, .hardLight, .vividLight, .linearLight, .pinLight, .hardMix],
        [.difference, .exclusion, .subtract, .divide],
        [.hue, .saturation, .color, .luminosity]
    ]

    /// What Core Graphics can draw directly. The rest are composited through Core Image or by hand,
    /// so this is only meaningful for the modes `SeparableBlend.needsSurface` leaves alone.
    var cgMode: CGBlendMode {
        switch self {
        case .normal: .normal
        case .multiply: .multiply
        case .screen: .screen
        case .overlay: .overlay
        case .softLight: .softLight
        case .hardLight: .hardLight
        case .darken: .darken
        case .lighten: .lighten
        case .difference: .difference
        case .exclusion: .exclusion
        case .colorDodge: .colorDodge
        case .colorBurn: .colorBurn
        case .hue: .hue
        case .saturation: .saturation
        case .color: .color
        case .luminosity: .luminosity
        // Drawn through Core Image or custom pixel/Metal kernels; never reaches Core Graphics.
        case .dissolve, .darkerColor, .lighterColor,
             .linearBurn, .linearDodge, .vividLight, .linearLight, .pinLight, .hardMix, .subtract, .divide: .normal
        }
    }

    /// Modes computed by our own C/Metal kernels rather than Core Graphics or Core Image built-ins.
    var usesCustomBlend: Bool {
        self == .dissolve || self == .darkerColor || self == .lighterColor
    }

    /// The Core Image filter that computes this mode, for the ones Core Graphics has no equivalent
    /// for — or computes wrongly, as it does for Color Burn and Color Dodge, and for Soft Light, whose formula is up to
    /// 25 levels off Photoshop's with a light blend color (Core Image's is within 5).
    var coreImageFilter: String? {
        switch self {
        case .colorBurn: "CIColorBurnBlendMode"
        case .colorDodge: "CIColorDodgeBlendMode"
        case .softLight: "CISoftLightBlendMode"
        case .linearBurn: "CILinearBurnBlendMode"
        case .linearDodge: "CILinearDodgeBlendMode"
        case .vividLight: "CIVividLightBlendMode"
        case .linearLight: "CILinearLightBlendMode"
        case .pinLight: "CIPinLightBlendMode"
        case .hardMix: "CIHardMixBlendMode"
        case .subtract: "CISubtractBlendMode"
        case .divide: "CIDivideBlendMode"
        default: nil
        }
    }
}

extension EditorSession {
    func displayedBlendMode(for layer: ImageLayer) -> LayerBlendMode {
        if let blendPreview, blendPreview.layerID == layer.id, activeLayerID == layer.id { return blendPreview.mode }
        return layer.blendMode
    }
    func displayedFolderPassThrough(for layer: ImageLayer) -> Bool {
        guard layer.isGroup else { return false }
        if let blendPreview, blendPreview.layerID == layer.id, activeLayerID == layer.id,
           let previewPassThrough = blendPreview.passThrough {
            return previewPassThrough
        }
        return layer.isPassThrough
    }
    func previewBlendMode(_ mode: LayerBlendMode?, for id: UUID?, passThrough: Bool? = nil) {
        if let mode, let id, id == activeLayerID, canEditBlendMode {
            blendPreview = (id, mode, passThrough)
        } else {
            blendPreview = nil
        }
        refreshCanvasPreview?()
    }
    var canEditAppearance: Bool {
        guard canEditLayers, selectedLayerIDs.count == 1, let layer = activeLayer, !layer.isGroup else { return false }
        return !effectiveLock(for: layer.id).blocksAppearance
    }
    /// Both layers and folders accept a blend mode and Blend If options.
    var canEditBlendMode: Bool {
        guard canEditLayers, selectedLayerIDs.count == 1, let layer = activeLayer else { return false }
        return !effectiveLock(for: layer.id).blocksAppearance
    }
    /// A folder takes an opacity of its own, which dims everything inside it (see LayerOpacity).
    var canEditOpacity: Bool {
        guard canEditLayers, selectedLayerIDs.count == 1, let layer = activeLayer else { return false }
        return !effectiveLock(for: layer.id).blocksAppearance
    }
    var canEditFillOpacity: Bool { canEditAppearance }
    func beginOpacityEdit() {
        guard canEditOpacity, opacityEditLayerID == nil, let id = activeLayerID else { return }
        finishFillOpacityEdit()
        beginEdit("Layer Opacity")
        opacityEditLayerID = id
    }
    func finishOpacityEdit() {
        finishFillOpacityEdit()
        guard opacityEditLayerID != nil else { return }
        opacityEditLayerID = nil
        endEdit()
    }
    func setLayerOpacity(_ opacity: Double) {
        guard opacity.isFinite, canEditOpacity,
              let id = opacityEditLayerID ?? activeLayerID,
              let index = document?.layers.firstIndex(where: { $0.id == id }) else { return }
        let standalone = opacityEditLayerID == nil
        if standalone { beginEdit("Layer Opacity") }
        document?.layers[index].opacity = min(1, max(0, opacity))
        if standalone { endEdit() }
    }
    func beginFillOpacityEdit() {
        guard canEditFillOpacity, fillOpacityEditLayerID == nil, let id = activeLayerID else { return }
        if opacityEditLayerID != nil { opacityEditLayerID = nil; endEdit() }
        beginEdit("Layer Fill")
        fillOpacityEditLayerID = id
    }
    func finishFillOpacityEdit() {
        guard fillOpacityEditLayerID != nil else { return }
        fillOpacityEditLayerID = nil
        endEdit()
    }
    func setLayerFillOpacity(_ fillOpacity: Double) {
        guard fillOpacity.isFinite, canEditFillOpacity,
              let id = fillOpacityEditLayerID ?? activeLayerID,
              let index = document?.layers.firstIndex(where: { $0.id == id }) else { return }
        let standalone = fillOpacityEditLayerID == nil
        if standalone { beginEdit("Layer Fill") }
        document?.layers[index].fillOpacity = min(1, max(0, fillOpacity))
        if standalone { endEdit() }
    }
    /// Sets every selected layer's opacity as one undo step. A selected folder takes the value too,
    /// dimming its contents on top of their own opacity.
    func setSelectedLayersOpacity(_ opacity: Double) {
        guard opacity.isFinite, canEditLayers, let document else { return }
        let value = min(1, max(0, opacity))
        let indices = document.layers.indices.filter {
            selectedLayerIDs.contains(document.layers[$0].id)
                && !document.effectiveLock(for: document.layers[$0].id).blocksAppearance
                && document.layers[$0].opacity != value
        }
        guard !indices.isEmpty else { return }
        finishOpacityEdit()
        beginEdit("Layer Opacity")
        for index in indices { self.document?.layers[index].opacity = value }
        endEdit()
    }
    /// Shift-+ / Shift-−: the active layer's (or folder's) blend mode steps to the next or previous one in the
    /// blend menu's order, wrapping around, as one undo step.
    func cycleBlendMode(forward: Bool) {
        guard canEditBlendMode, let layer = activeLayer else { return }
        if layer.isGroup {
            let modes = LayerBlendMode.allCases
            if layer.isPassThrough {
                setLayerBlendMode(forward ? modes[0] : modes[modes.count - 1])
            } else if let index = modes.firstIndex(of: layer.blendMode) {
                let next = index + (forward ? 1 : -1)
                if next < 0 || next >= modes.count {
                    setFolderPassThrough()
                } else {
                    setLayerBlendMode(modes[next])
                }
            }
            return
        }
        let modes = LayerBlendMode.allCases
        let index = modes.firstIndex(of: layer.blendMode) ?? 0
        setLayerBlendMode(modes[(index + (forward ? 1 : modes.count - 1)) % modes.count])
    }
    func setLayerBlendMode(_ mode: LayerBlendMode) {
        blendPreview = nil
        guard canEditBlendMode, let index = document?.layers.firstIndex(where: { $0.id == activeLayerID }) else { return }
        finishOpacityEdit()
        beginEdit("Layer Blend Mode")
        document?.layers[index].blendMode = mode
        if document?.layers[index].isGroup == true {
            document?.layers[index].isPassThrough = false
        }
        endEdit()
    }
    func setFolderPassThrough() {
        blendPreview = nil
        guard canEditBlendMode, let index = document?.layers.firstIndex(where: { $0.id == activeLayerID }),
              document?.layers[index].isGroup == true else { return }
        guard !(document?.layers[index].isPassThrough == true && document?.layers[index].blendMode == .normal) else { return }
        finishOpacityEdit()
        beginEdit("Layer Blend Mode")
        document?.layers[index].isPassThrough = true
        document?.layers[index].blendMode = .normal
        endEdit()
    }
}
