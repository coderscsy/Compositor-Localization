import AppKit
import CoreGraphics
import CoreImage

/// A line drawn around what the layer shows, outside its edge, centered on it, or inside it.
nonisolated struct StrokeEffect: Codable, Equatable, Sendable {
    /// Supported document-pixel width; preview work is bounded independently of this value.
    static let maxSize: CGFloat = 500
    var enabled: Bool? = nil // Missing in older projects means visible.
    var isEnabled: Bool { enabled ?? true }
    var size: CGFloat = 4
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var opacity: Double = 1
    var inside = false
    /// Explicit placement (`Outside`, `Center`, `Inside`), arrived in format v28. Nil falls back to `inside`.
    var position: StrokePosition? = nil
    var blendMode: EffectBlendMode? = nil
    var resolvedPosition: StrokePosition {
        get { position ?? (inside ? .inside : .outside) }
        set {
            position = newValue
            inside = (newValue == .inside)
        }
    }
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    var isValid: Bool {
        size.isFinite && (0...StrokeEffect.maxSize).contains(size) && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// The layer's shape repeated behind it, offset and softened.
nonisolated struct ShadowEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    /// Where the light comes from, in degrees counterclockwise from the right, as Photoshop's dial is: 90 is from
    /// straight above, which drops the shadow straight down.
    var angle: CGFloat = 90
    var distance: CGFloat = 20
    var blur: CGFloat = 20
    var spread: CGFloat? = nil
    var blendMode: EffectBlendMode? = nil
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var opacity: Double = 0.5
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    /// Where the shadow sits, in layer pixels (y grows downward, as the layer's own pixels do).
    var offset: CGSize {
        let radians = angle * .pi / 180
        // The shadow falls away from the light, and a layer's pixels count y downward.
        return CGSize(width: -cos(radians) * distance, height: sin(radians) * distance)
    }
    var isValid: Bool {
        [angle, distance, blur].allSatisfy(\.isFinite) && (-360...360).contains(angle)
            && (0...5000).contains(distance) && (0...500).contains(blur)
            && (spread.map { $0.isFinite && (0...100).contains($0) } ?? true)
            && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// A flat color over everything the layer shows.
nonisolated struct ColorOverlayEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var opacity: Double = 1
    var blendMode: EffectBlendMode? = nil
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    var isValid: Bool {
        opacity.isFinite && (0...1).contains(opacity) && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// A shadow cast inside the layer's own edges, as though it were cut out of what is behind it.
nonisolated struct InnerShadowEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var angle: CGFloat = 90
    var distance: CGFloat = 10
    var blur: CGFloat = 10
    var spread: CGFloat? = nil
    var blendMode: EffectBlendMode? = nil
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var opacity: Double = 0.5
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    /// Where the shadow falls, in layer pixels (y grows downward).
    var offset: CGSize {
        let radians = angle * .pi / 180
        return CGSize(width: -cos(radians) * distance, height: sin(radians) * distance)
    }
    var isValid: Bool {
        [angle, distance, blur].allSatisfy(\.isFinite) && (-360...360).contains(angle)
            && (0...5000).contains(distance) && (0...500).contains(blur)
            && (spread.map { $0.isFinite && (0...100).contains($0) } ?? true)
            && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// A soft glow drawn omnidirectionally around the outside of what the layer shows.
nonisolated struct OuterGlowEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var size: CGFloat = 20
    var spread: CGFloat? = nil
    var blendMode: EffectBlendMode? = nil
    var red: CGFloat = 1
    var green: CGFloat = 1
    var blue: CGFloat = 1
    var opacity: Double = 0.75
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    var isValid: Bool {
        size.isFinite && (0...500).contains(size)
            && (spread.map { $0.isFinite && (0...100).contains($0) } ?? true)
            && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// A glow cast inside the layer's own edges, emanating inward from its boundary.
nonisolated struct InnerGlowEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var size: CGFloat = 10
    var spread: CGFloat? = nil
    var blendMode: EffectBlendMode? = nil
    var red: CGFloat = 1
    var green: CGFloat = 1
    var blue: CGFloat = 1
    var opacity: Double = 0.75
    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }
    var isValid: Bool {
        size.isFinite && (0...500).contains(size)
            && (spread.map { $0.isFinite && (0...100).contains($0) } ?? true)
            && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// What a layer draws around itself. Kept with the layer, so it follows every edit and can be changed or removed
/// at any time; the pixels themselves are never touched.
nonisolated struct LayerEffects: Codable, Equatable, Sendable {
    var stroke: StrokeEffect? = nil
    var shadow: ShadowEffect? = nil
    var colorOverlay: ColorOverlayEffect? = nil
    var innerShadow: InnerShadowEffect? = nil
    var outerGlow: OuterGlowEffect? = nil
    var innerGlow: InnerGlowEffect? = nil
    var bevelEmboss: BevelEmbossEffect? = nil
    var gradientOverlay: GradientOverlayEffect? = nil
    var patternOverlay: PatternOverlayEffect? = nil
    var isEmpty: Bool {
        stroke == nil && shadow == nil && colorOverlay == nil && innerShadow == nil
            && outerGlow == nil && innerGlow == nil
            && bevelEmboss == nil && gradientOverlay == nil && patternOverlay == nil
    }
    var isValid: Bool {
        (stroke?.isValid ?? true) && (shadow?.isValid ?? true)
            && (colorOverlay?.isValid ?? true) && (innerShadow?.isValid ?? true)
            && (outerGlow?.isValid ?? true) && (innerGlow?.isValid ?? true)
            && (bevelEmboss?.isValid ?? true) && (gradientOverlay?.isValid ?? true)
            && (patternOverlay?.isValid ?? true)
    }
    /// True when any format-v28 style feature is present (used both for version checks and choosing the renderer path).
    var hasVersion28Features: Bool {
        bevelEmboss != nil || gradientOverlay != nil || patternOverlay != nil
            || stroke?.position != nil || stroke?.blendMode != nil
            || shadow?.spread != nil || shadow?.blendMode != nil
            || colorOverlay?.blendMode != nil
            || innerShadow?.spread != nil || innerShadow?.blendMode != nil
            || outerGlow?.spread != nil || outerGlow?.blendMode != nil
            || innerGlow?.spread != nil || innerGlow?.blendMode != nil
    }
    /// The effects for an image resampled by `factor`: every size, distance and blur in pixels scaled with it, held to
    /// the ranges `isValid` accepts.
    func scaled(by factor: CGFloat) -> LayerEffects {
        func scale(_ value: CGFloat?, upTo limit: CGFloat) -> CGFloat { min(limit, (value ?? 0) * factor) }
        var result = self
        result.stroke?.size = scale(stroke?.size, upTo: 500)
        result.shadow?.distance = scale(shadow?.distance, upTo: 5000)
        result.shadow?.blur = scale(shadow?.blur, upTo: 500)
        result.innerShadow?.distance = scale(innerShadow?.distance, upTo: 5000)
        result.innerShadow?.blur = scale(innerShadow?.blur, upTo: 500)
        result.outerGlow?.size = scale(outerGlow?.size, upTo: 500)
        result.innerGlow?.size = scale(innerGlow?.size, upTo: 500)
        result.bevelEmboss?.size = scale(bevelEmboss?.size, upTo: 250)
        result.bevelEmboss?.soften = scale(bevelEmboss?.soften, upTo: 16)
        return result
    }
    var kinds: [LayerEffectKind] { LayerEffectKind.allCases.filter { contains($0) } }
    func contains(_ kind: LayerEffectKind) -> Bool {
        switch kind {
        case .stroke: return stroke != nil
        case .shadow: return shadow != nil
        case .colorOverlay: return colorOverlay != nil
        case .gradientOverlay: return gradientOverlay != nil
        case .patternOverlay: return patternOverlay != nil
        case .innerShadow: return innerShadow != nil
        case .outerGlow: return outerGlow != nil
        case .innerGlow: return innerGlow != nil
        case .bevelEmboss: return bevelEmboss != nil
        }
    }
    func isEnabled(_ kind: LayerEffectKind) -> Bool {
        switch kind {
        case .stroke: return stroke?.isEnabled == true
        case .shadow: return shadow?.isEnabled == true
        case .colorOverlay: return colorOverlay?.isEnabled == true
        case .gradientOverlay: return gradientOverlay?.isEnabled == true
        case .patternOverlay: return patternOverlay?.isEnabled == true
        case .innerShadow: return innerShadow?.isEnabled == true
        case .outerGlow: return outerGlow?.isEnabled == true
        case .innerGlow: return innerGlow?.isEnabled == true
        case .bevelEmboss: return bevelEmboss?.isEnabled == true
        }
    }
    /// The effect's own color, and a way to put a new one back.
    func color(_ kind: LayerEffectKind) -> PaletteColor? {
        switch kind {
        case .stroke: return stroke?.color
        case .shadow: return shadow?.color
        case .colorOverlay: return colorOverlay?.color
        case .gradientOverlay: return gradientOverlay?.startColor
        case .patternOverlay: return patternOverlay?.color
        case .innerShadow: return innerShadow?.color
        case .outerGlow: return outerGlow?.color
        case .innerGlow: return innerGlow?.color
        case .bevelEmboss: return bevelEmboss?.highlightColor
        }
    }
    mutating func setColor(_ color: PaletteColor, for kind: LayerEffectKind) {
        switch kind {
        case .stroke: stroke?.red = color.red; stroke?.green = color.green; stroke?.blue = color.blue
        case .shadow: shadow?.red = color.red; shadow?.green = color.green; shadow?.blue = color.blue
        case .colorOverlay: colorOverlay?.red = color.red; colorOverlay?.green = color.green; colorOverlay?.blue = color.blue
        case .gradientOverlay:
            if gradientOverlay?.stops.isEmpty == false {
                gradientOverlay?.stops[0].red = color.red
                gradientOverlay?.stops[0].green = color.green
                gradientOverlay?.stops[0].blue = color.blue
            }
        case .patternOverlay: patternOverlay?.red = color.red; patternOverlay?.green = color.green; patternOverlay?.blue = color.blue
        case .innerShadow: innerShadow?.red = color.red; innerShadow?.green = color.green; innerShadow?.blue = color.blue
        case .outerGlow: outerGlow?.red = color.red; outerGlow?.green = color.green; outerGlow?.blue = color.blue
        case .innerGlow: innerGlow?.red = color.red; innerGlow?.green = color.green; innerGlow?.blue = color.blue
        case .bevelEmboss:
            bevelEmboss?.highlightRed = color.red; bevelEmboss?.highlightGreen = color.green; bevelEmboss?.highlightBlue = color.blue
        }
    }
    mutating func remove(_ kind: LayerEffectKind) {
        switch kind {
        case .stroke: stroke = nil
        case .shadow: shadow = nil
        case .colorOverlay: colorOverlay = nil
        case .gradientOverlay: gradientOverlay = nil
        case .patternOverlay: patternOverlay = nil
        case .innerShadow: innerShadow = nil
        case .outerGlow: outerGlow = nil
        case .innerGlow: innerGlow = nil
        case .bevelEmboss: bevelEmboss = nil
        }
    }
    mutating func setEnabled(_ enabled: Bool, for kind: LayerEffectKind) {
        switch kind {
        case .stroke: stroke?.enabled = enabled
        case .shadow: shadow?.enabled = enabled
        case .colorOverlay: colorOverlay?.enabled = enabled
        case .gradientOverlay: gradientOverlay?.enabled = enabled
        case .patternOverlay: patternOverlay?.enabled = enabled
        case .innerShadow: innerShadow?.enabled = enabled
        case .outerGlow: outerGlow?.enabled = enabled
        case .innerGlow: innerGlow?.enabled = enabled
        case .bevelEmboss: bevelEmboss?.enabled = enabled
        }
    }
    var visible: LayerEffects {
        LayerEffects(stroke: stroke?.isEnabled == true ? stroke : nil,
                     shadow: shadow?.isEnabled == true ? shadow : nil,
                     colorOverlay: colorOverlay?.isEnabled == true ? colorOverlay : nil,
                     innerShadow: innerShadow?.isEnabled == true ? innerShadow : nil,
                     outerGlow: outerGlow?.isEnabled == true ? outerGlow : nil,
                     innerGlow: innerGlow?.isEnabled == true ? innerGlow : nil,
                     bevelEmboss: bevelEmboss?.isEnabled == true ? bevelEmboss : nil,
                     gradientOverlay: gradientOverlay?.isEnabled == true ? gradientOverlay : nil,
                     patternOverlay: patternOverlay?.isEnabled == true ? patternOverlay : nil)
    }
}

nonisolated enum LayerEffectKind: String, CaseIterable, Sendable {
    case bevelEmboss = "Bevel & Emboss"
    case stroke = "Stroke"
    case innerShadow = "Inner Shadow"
    case innerGlow = "Inner Glow"
    case colorOverlay = "Color Overlay"
    case gradientOverlay = "Gradient Overlay"
    case patternOverlay = "Pattern Overlay"
    case outerGlow = "Outer Glow"
    case shadow = "Drop Shadow"
}

struct LayerEffectSelection: Equatable {
    let layerID: UUID
    let kind: LayerEffectKind
}

extension EditorSession {
    var canEditEffects: Bool {
        guard canEditLayers, let layer = activeLayer, !layer.isGroup, layer.asset != nil else { return false }
        return !effectiveLock(for: layer.id).blocksStructure
    }
    var activeEffects: LayerEffects { activeLayer?.effects ?? LayerEffects() }
    var editingEffects: LayerEffects {
        document?.layers.first(where: { $0.id == effectsEditing?.layerID })?.effects ?? LayerEffects()
    }
    var selectedEffect: LayerEffectSelection? {
        guard let effectSelection, effectSelection.layerID == activeLayerID,
              activeEffects.contains(effectSelection.kind) else { return nil }
        return effectSelection
    }

    func addEffect(_ kind: LayerEffectKind) {
        guard canEditEffects, let id = activeLayerID else { return }
        if effectsEditing == LayerEffectSelection(layerID: id, kind: kind) { return }
        finishEffectsEditing(commit: false)
        let original = activeEffects
        var effects = original
        // A new stroke or overlay takes the background color: the foreground is usually what the layer is painted in.
        switch kind {
        case .stroke where effects.stroke == nil:
            var new = StrokeEffect()
            new.red = backgroundColor.red; new.green = backgroundColor.green; new.blue = backgroundColor.blue
            effects.stroke = new
        case .shadow where effects.shadow == nil:
            effects.shadow = ShadowEffect()
        case .colorOverlay where effects.colorOverlay == nil:
            var new = ColorOverlayEffect()
            new.red = backgroundColor.red; new.green = backgroundColor.green; new.blue = backgroundColor.blue
            effects.colorOverlay = new
        case .innerShadow where effects.innerShadow == nil:
            effects.innerShadow = InnerShadowEffect()
        case .outerGlow where effects.outerGlow == nil:
            effects.outerGlow = OuterGlowEffect()
        case .innerGlow where effects.innerGlow == nil:
            effects.innerGlow = InnerGlowEffect()
        case .bevelEmboss where effects.bevelEmboss == nil:
            effects.bevelEmboss = BevelEmbossEffect()
        case .gradientOverlay where effects.gradientOverlay == nil:
            var new = GradientOverlayEffect()
            new.stops = [
                GradientOverlayStop(position: 0, red: foregroundColor.red, green: foregroundColor.green, blue: foregroundColor.blue),
                GradientOverlayStop(position: 1, red: backgroundColor.red, green: backgroundColor.green, blue: backgroundColor.blue),
            ]
            effects.gradientOverlay = new
        case .patternOverlay where effects.patternOverlay == nil:
            var new = PatternOverlayEffect()
            new.red = foregroundColor.red; new.green = foregroundColor.green; new.blue = foregroundColor.blue
            effects.patternOverlay = new
        default: break
        }
        setEffects(effects, on: id, name: L10n.format("Add %@", L10n.text(kind.rawValue)))
        selectEffect(kind, on: id, editing: true)
        effectsEditingOriginal = original
    }

    func selectEffect(_ kind: LayerEffectKind, on id: UUID, editing: Bool = false) {
        guard canEditLayers, document?.layers.first(where: { $0.id == id })?.effects?.contains(kind) == true else { return }
        let selection = LayerEffectSelection(layerID: id, kind: kind)
        if editing, effectsEditing != selection { finishEffectsEditing(commit: false) }
        selectLayer(id)
        selectedLayerIDs = [id]
        isMaskSelected = false
        effectSelection = selection
        if editing, effectsEditing != selection {
            if let picker = colorPicker, case .effect = picker.target { closeColorPicker(commit: false) }
            effectsEditingOriginal = document?.layers.first(where: { $0.id == id })?.effects ?? LayerEffects()
            effectsEditing = selection
        }
    }

    /// Cancel restores only this panel's effect, preserving edits to other effects or layers.
    /// For a newly added effect the original value is absent, so Cancel removes it again.
    func finishEffectsEditing(commit: Bool) {
        guard let editing = effectsEditing else { return }
        if let picker = colorPicker, case .effect = picker.target { closeColorPicker(commit: commit) }
        if !commit, let original = effectsEditingOriginal,
           var effects = document?.layers.first(where: { $0.id == editing.layerID })?.effects {
            switch editing.kind {
            case .stroke: effects.stroke = original.stroke
            case .shadow: effects.shadow = original.shadow
            case .colorOverlay: effects.colorOverlay = original.colorOverlay
            case .gradientOverlay: effects.gradientOverlay = original.gradientOverlay
            case .patternOverlay: effects.patternOverlay = original.patternOverlay
            case .innerShadow: effects.innerShadow = original.innerShadow
            case .outerGlow: effects.outerGlow = original.outerGlow
            case .innerGlow: effects.innerGlow = original.innerGlow
            case .bevelEmboss: effects.bevelEmboss = original.bevelEmboss
            }
            setEffects(effects, on: editing.layerID, name: L10n.format("Cancel %@", L10n.text(editing.kind.rawValue)))
        }
        effectsEditing = nil
        effectsEditingOriginal = nil
        if selectedEffect == nil { effectSelection = nil }
    }

    func setEffects(_ effects: LayerEffects, on id: UUID? = nil, name: String = "Layer Effects") {
        guard canEditLayers, effects.isValid,
              let index = document?.layers.firstIndex(where: { $0.id == (id ?? activeLayerID) }),
              document?.layers[index].isGroup == false, document?.layers[index].asset != nil,
              document?.layers[index].effects != (effects.isEmpty ? nil : effects) else { return }
        finishOpacityEdit()
        beginEdit(name)
        document?.layers[index].effects = effects.isEmpty ? nil : effects
        endEdit()
    }

    /// Panel edits stay bound to the layer that opened the panel, even if selection changes.
    func changeEffects(_ change: (inout LayerEffects) -> Void) {
        guard let editing = effectsEditing,
              let layer = document?.layers.first(where: { $0.id == editing.layerID }),
              layer.effects?.contains(editing.kind) == true else { return }
        var effects = layer.effects ?? LayerEffects()
        change(&effects)
        setEffects(effects, on: layer.id, name: L10n.format("Edit %@", L10n.text(editing.kind.rawValue)))
    }

    func canCopyEffect(_ kind: LayerEffectKind, from source: UUID, to target: UUID) -> Bool {
        guard canEditLayers, source != target,
              document?.layers.first(where: { $0.id == source })?.effects?.contains(kind) == true,
              let layer = document?.layers.first(where: { $0.id == target }),
              !layer.isGroup, layer.asset != nil else { return false }
        return true
    }

    func copyEffect(_ kind: LayerEffectKind, from source: UUID, to target: UUID) {
        guard canCopyEffect(kind, from: source, to: target),
              let original = document?.layers.first(where: { $0.id == source })?.effects else { return }
        // Close the destination's editor before replacing its effect so a later Cancel cannot undo the copy.
        if effectsEditing == LayerEffectSelection(layerID: target, kind: kind) {
            finishEffectsEditing(commit: true)
        }
        var effects = document?.layers.first(where: { $0.id == target })?.effects ?? LayerEffects()
        switch kind {
        case .stroke: effects.stroke = original.stroke
        case .shadow: effects.shadow = original.shadow
        case .colorOverlay: effects.colorOverlay = original.colorOverlay
        case .gradientOverlay: effects.gradientOverlay = original.gradientOverlay
        case .patternOverlay: effects.patternOverlay = original.patternOverlay
        case .innerShadow: effects.innerShadow = original.innerShadow
        case .outerGlow: effects.outerGlow = original.outerGlow
        case .innerGlow: effects.innerGlow = original.innerGlow
        case .bevelEmboss: effects.bevelEmboss = original.bevelEmboss
        }
        setEffects(effects, on: target, name: L10n.format("Copy %@", L10n.text(kind.rawValue)))
        selectEffect(kind, on: target)
    }

    func toggleEffect(_ kind: LayerEffectKind, on id: UUID) {
        guard var effects = document?.layers.first(where: { $0.id == id })?.effects else { return }
        let enabled = effects.isEnabled(kind)
        effects.setEnabled(!enabled, for: kind)
        setEffects(effects, on: id, name: L10n.format(enabled ? "Hide %@" : "Show %@", L10n.text(kind.rawValue)))
    }

    func removeSelectedEffect() {
        guard let selectedEffect, canEditLayers, !effectiveLock(for: selectedEffect.layerID).blocksStructure,
              var effects = document?.layers.first(where: { $0.id == selectedEffect.layerID })?.effects else { return }
        if effectsEditing == selectedEffect {
            if let picker = colorPicker, case .effect = picker.target { closeColorPicker(commit: false) }
            effectsEditing = nil
            effectsEditingOriginal = nil
        }
        effects.remove(selectedEffect.kind)
        setEffects(effects, on: selectedEffect.layerID, name: L10n.format("Remove %@", L10n.text(selectedEffect.kind.rawValue)))
        effectSelection = nil
    }
}

/// Draws a layer's effects around its pixels. The result is the layer as it should appear — shadow behind, stroke
/// around, pixels on top — on a canvas grown by `inset` pixels on every side, so the caller places it by growing
/// the layer's transform in the same proportion.
nonisolated enum LayerEffectsRenderer {
    /// The last few layers drawn with effects, so the canvas doesn't rebuild them on every redraw.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(image: CGImage, mask: CGImage?, effects: LayerEffects, fillOpacity: Double, result: CGImage, inset: CGFloat)] = []
        func result(image: CGImage, mask: CGImage?, effects: LayerEffects, fillOpacity: Double,
                    make: () throws -> (image: CGImage, inset: CGFloat)) throws -> (image: CGImage, inset: CGFloat) {
            lock.lock()
            let hit = entries.first { $0.image === image && $0.mask === mask && $0.effects == effects && $0.fillOpacity == fillOpacity }
            lock.unlock()
            if let hit { return (hit.result, hit.inset) }
            let made = try make()
            lock.lock()
            let budget = 64 * 1024 * 1024
            let cost = made.image.bytesPerRow * made.image.height + image.bytesPerRow * image.height + (mask.map { $0.bytesPerRow * $0.height } ?? 0)
            if cost <= budget {
                entries.append((image, mask, effects, fillOpacity, made.image, made.inset))
                while entries.count > 8 || entries.reduce(0, { $0 + $1.result.bytesPerRow * $1.result.height + $1.image.bytesPerRow * $1.image.height + ($1.mask.map { $0.bytesPerRow * $0.height } ?? 0) }) > budget {
                    entries.removeFirst()
                }
            }
            lock.unlock()
            return made
        }
    }
    private static let cache = Cache()

    /// `image` with `effects` around it, reusing the last result for the same pixels, mask and settings. Nil when
    /// there is nothing to draw or the effects can't be made, so the caller draws the layer as it is.
    static func cached(_ image: CGImage, mask: CGImage?, effects: LayerEffects?, fillOpacity: Double = 1) -> (image: CGImage, inset: CGFloat)? {
        guard let effects = effects?.visible, !effects.isEmpty, effects.isValid else { return nil }
        let fill = min(1, max(0, fillOpacity.isFinite ? fillOpacity : 1))
        return try? cache.result(image: image, mask: mask, effects: effects, fillOpacity: fill) {
            try render(image, mask: mask, effects: effects, fillOpacity: fill)
        }
    }

    /// The layer's transform grown by the margin its effects need, so the bigger image lands in the same place.
    static func placed(_ transform: LayerTransform, image: CGImage, inset: CGFloat) -> LayerTransform {
        var grown = transform
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard width > inset * 2, height > inset * 2 else { return transform }
        grown.size = CGSize(width: transform.size.width * width / (width - inset * 2),
                            height: transform.size.height * height / (height - inset * 2))
        grown.origin = CGPoint(x: transform.center.x - grown.size.width / 2, y: transform.center.y - grown.size.height / 2)
        return grown
    }

    static func margin(for effects: LayerEffects) -> CGFloat {
        let effects = effects.visible
        var margin: CGFloat = 0
        if let stroke = effects.stroke {
            switch stroke.resolvedPosition {
            case .outside: margin = max(margin, stroke.size)
            case .center: margin = max(margin, ceil(stroke.size / 2))
            case .inside: break
            }
        }
        if let shadow = effects.shadow {
            margin = max(margin, shadow.distance + shadow.blur * 3)
        }
        if let glow = effects.outerGlow {
            margin = max(margin, glow.size * 3)
        }
        if let bevel = effects.bevelEmboss, bevel.style != .innerBevel {
            margin = max(margin, bevel.size + bevel.soften + 4)
        }
        return ceil(margin) + 2
    }

    private static func maskBytes(_ image: CGImage, width: Int, height: Int, spread: CGFloat? = nil) throws -> (context: CGContext, bytes: UnsafeMutablePointer<UInt8>, stride: Int32) {
        let ctx = try BrushRaster.context(width: width, height: height, mask: true)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), mask: true, context: ctx)
        guard let raw = ctx.data else { throw ExportError.render }
        let bytes = raw.assumingMemoryBound(to: UInt8.self)
        if let spread, spread > 0 {
            style_apply_spread(bytes, Int32(ctx.bytesPerRow), Int32(width), Int32(height), Float(spread))
        }
        return (ctx, bytes, Int32(ctx.bytesPerRow))
    }

    /// `image` with `effects` around it. `mask` (the layer's own mask, in its pixel grid) hides part of the layer
    /// before the effects are made, so they follow the shape that is actually shown, as in Photoshop.
    static func render(_ image: CGImage, mask: CGImage?, effects: LayerEffects, fillOpacity: Double = 1) throws -> (image: CGImage, inset: CGFloat) {
        let effects = effects.visible
        guard effects.isValid else { throw ProjectError.invalid }
        let fillOpacity = min(1, max(0, fillOpacity.isFinite ? fillOpacity : 1))
        let inset = margin(for: effects)
        let width = image.width + Int(inset) * 2, height = image.height + Int(inset) * 2
        guard width > 0, height > 0, width * height <= DocumentLimits.maxSurfacePixels else { throw ProjectError.tooLarge }
        let placed = CGRect(x: inset, y: inset, width: CGFloat(image.width), height: CGFloat(image.height))
        let full = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        // The layer as it is shown: its pixels through its mask.
        let shown = try masked(image, mask: mask)
        if !effects.hasVersion28Features, let metal = MetalLayerEffects.shared {
            // The pixels with room around them, then the stroke and shadow drawn on the GPU.
            let padded = try BrushRaster.context(width: width, height: height, mask: false)
            BrushRaster.draw(shown, in: placed, mask: false, context: padded)
            if let room = padded.makeImage(), let built = try? metal.render(room, effects: effects, fillOpacity: fillOpacity) {
                return (built, inset)
            }
        }
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        guard let ctxRaw = context.data else { throw ExportError.render }
        let ctxBytes = ctxRaw.assumingMemoryBound(to: UInt8.self)
        let ctxStride = Int32(context.bytesPerRow)

        let shapeAlphaImage = try coverage(shown, in: placed, size: CGSize(width: width, height: height), blur: 0)
        let shapeMask = try maskBytes(shapeAlphaImage, width: width, height: height)

        if let shadow = effects.shadow, shadow.opacity > 0 {
            let alpha = try coverage(shown, in: placed.offsetBy(dx: shadow.offset.width, dy: shadow.offset.height),
                                     size: CGSize(width: width, height: height), blur: shadow.blur)
            let cov = try maskBytes(alpha, width: width, height: height, spread: shadow.spread)
            style_blend_solid(ctxBytes, ctxStride, cov.bytes, cov.stride, nil, 0, Int32(width), Int32(height),
                              Float(shadow.red), Float(shadow.green), Float(shadow.blue), Float(shadow.opacity),
                              (shadow.blendMode ?? .normal).kernelIndex)
        }
        if let glow = effects.outerGlow, glow.opacity > 0 {
            let alpha = try outerGlowCoverage(shown, placed: placed, size: CGSize(width: width, height: height), glow: glow)
            let cov = try maskBytes(alpha, width: width, height: height, spread: glow.spread)
            style_blend_solid(ctxBytes, ctxStride, cov.bytes, cov.stride, nil, 0, Int32(width), Int32(height),
                              Float(glow.red), Float(glow.green), Float(glow.blue), Float(glow.opacity),
                              (glow.blendMode ?? .normal).kernelIndex)
        }
        // Outside stroke sits behind the layer's pixels; Center and Inside draw over them.
        let stroke = effects.stroke.flatMap { $0.size > 0 && $0.opacity > 0 ? $0 : nil }
        func drawStroke(_ stroke: StrokeEffect) throws {
            let alpha = try strokeCoverage(shown, placed: placed, size: CGSize(width: width, height: height), stroke: stroke)
            let cov = try maskBytes(alpha, width: width, height: height)
            style_blend_solid(ctxBytes, ctxStride, cov.bytes, cov.stride, nil, 0, Int32(width), Int32(height),
                              Float(stroke.red), Float(stroke.green), Float(stroke.blue), Float(stroke.opacity),
                              (stroke.blendMode ?? .normal).kernelIndex)
        }
        if let stroke, stroke.resolvedPosition == .outside { try drawStroke(stroke) }

        // Layer interior: fill pixels, Pattern Overlay, Gradient Overlay, Color Overlay, Inner Glow, Inner Shadow, Inner Bevel.
        let layer = try BrushRaster.context(width: width, height: height, mask: false)
        guard let layerRaw = layer.data else { throw ExportError.render }
        let layerBytes = layerRaw.assumingMemoryBound(to: UInt8.self)
        let layerStride = Int32(layer.bytesPerRow)
        if fillOpacity > 0 {
            layer.saveGState()
            layer.translateBy(x: placed.minX, y: placed.maxY)
            layer.scaleBy(x: 1, y: -1)
            layer.setAlpha(fillOpacity)
            layer.draw(shown, in: CGRect(origin: .zero, size: placed.size))
            layer.restoreGState()
        }
        if let pattern = effects.patternOverlay, pattern.isEnabled, pattern.opacity > 0 {
            style_render_pattern_overlay(layerBytes, layerStride, shapeMask.bytes, shapeMask.stride,
                                         Int32(width), Int32(height),
                                         pattern.pattern.kernelIndex, Float(pattern.scale),
                                         Float(pattern.red), Float(pattern.green), Float(pattern.blue),
                                         Float(pattern.opacity), pattern.blendMode.kernelIndex)
        }
        if let gradient = effects.gradientOverlay, gradient.isEnabled, gradient.opacity > 0 {
            let stops = gradient.sortedStops
            stops.withUnsafeBufferPointer { buf in
                style_render_gradient_overlay(layerBytes, layerStride, shapeMask.bytes, shapeMask.stride,
                                              Int32(width), Int32(height),
                                              Float(placed.minX), Float(placed.minY), Float(placed.width), Float(placed.height),
                                              gradient.style.kernelIndex, Float(gradient.angle), Float(gradient.scale),
                                              gradient.reverse ? 1 : 0, Float(gradient.opacity), gradient.blendMode.kernelIndex,
                                              buf.baseAddress, Int32(buf.count))
            }
        }
        if let overlay = effects.colorOverlay, overlay.isEnabled, overlay.opacity > 0 {
            style_blend_solid(layerBytes, layerStride, shapeMask.bytes, shapeMask.stride, nil, 0, Int32(width), Int32(height),
                              Float(overlay.red), Float(overlay.green), Float(overlay.blue), Float(overlay.opacity),
                              (overlay.blendMode ?? .normal).kernelIndex)
        }
        if let innerGlow = effects.innerGlow, innerGlow.isEnabled, innerGlow.opacity > 0,
           let insideGlow = try? innerGlowCoverage(shown, placed: placed, size: CGSize(width: width, height: height), glow: innerGlow) {
            let cov = try maskBytes(insideGlow, width: width, height: height, spread: innerGlow.spread)
            style_blend_solid(layerBytes, layerStride, cov.bytes, cov.stride, shapeMask.bytes, shapeMask.stride,
                              Int32(width), Int32(height),
                              Float(innerGlow.red), Float(innerGlow.green), Float(innerGlow.blue), Float(innerGlow.opacity),
                              (innerGlow.blendMode ?? .normal).kernelIndex)
        }
        if let inner = effects.innerShadow, inner.isEnabled, inner.opacity > 0,
           let inside = try? innerCoverage(shown, placed: placed, size: CGSize(width: width, height: height), shadow: inner) {
            let cov = try maskBytes(inside, width: width, height: height, spread: inner.spread)
            style_blend_solid(layerBytes, layerStride, cov.bytes, cov.stride, shapeMask.bytes, shapeMask.stride,
                              Int32(width), Int32(height),
                              Float(inner.red), Float(inner.green), Float(inner.blue), Float(inner.opacity),
                              (inner.blendMode ?? .normal).kernelIndex)
        }
        if let bevel = effects.bevelEmboss, bevel.isEnabled, bevel.style == .innerBevel, bevel.size > 0 {
            let blurRadius = max(1, bevel.size + bevel.soften)
            let heightImg = try coverage(shown, in: placed, size: CGSize(width: width, height: height), blur: blurRadius)
            let heightMask = try maskBytes(heightImg, width: width, height: height)
            style_render_bevel_emboss(layerBytes, layerStride, shapeMask.bytes, shapeMask.stride,
                                      heightMask.bytes, heightMask.stride, Int32(width), Int32(height),
                                      bevel.style.kernelIndex, bevel.direction == .down ? 1 : 0,
                                      Float(bevel.depth), Float(bevel.angle), Float(bevel.altitude),
                                      Float(bevel.highlightRed), Float(bevel.highlightGreen), Float(bevel.highlightBlue),
                                      Float(bevel.highlightOpacity), bevel.highlightBlendMode.kernelIndex,
                                      Float(bevel.shadowRed), Float(bevel.shadowGreen), Float(bevel.shadowBlue),
                                      Float(bevel.shadowOpacity), bevel.shadowBlendMode.kernelIndex)
        }
        guard let styled = layer.makeImage() else { throw ExportError.render }
        context.saveGState()
        context.translateBy(x: 0, y: full.height)
        context.scaleBy(x: 1, y: -1)
        context.setBlendMode(.normal)
        context.draw(styled, in: full)
        context.restoreGState()

        if let bevel = effects.bevelEmboss, bevel.isEnabled, bevel.style != .innerBevel, bevel.size > 0 {
            let blurRadius = max(1, bevel.size + bevel.soften)
            let heightImg = try coverage(shown, in: placed, size: CGSize(width: width, height: height), blur: blurRadius)
            let heightMask = try maskBytes(heightImg, width: width, height: height)
            style_render_bevel_emboss(ctxBytes, ctxStride, shapeMask.bytes, shapeMask.stride,
                                      heightMask.bytes, heightMask.stride, Int32(width), Int32(height),
                                      bevel.style.kernelIndex, bevel.direction == .down ? 1 : 0,
                                      Float(bevel.depth), Float(bevel.angle), Float(bevel.altitude),
                                      Float(bevel.highlightRed), Float(bevel.highlightGreen), Float(bevel.highlightBlue),
                                      Float(bevel.highlightOpacity), bevel.highlightBlendMode.kernelIndex,
                                      Float(bevel.shadowRed), Float(bevel.shadowGreen), Float(bevel.shadowBlue),
                                      Float(bevel.shadowOpacity), bevel.shadowBlendMode.kernelIndex)
        }
        if let stroke, stroke.resolvedPosition != .outside { try drawStroke(stroke) }
        guard let result = context.makeImage() else { throw ExportError.render }
        return (result, inset)
    }

    /// How strongly an inner glow falls on each pixel: strongest at the layer's edges, fading inward. It's the
    /// strength before the layer's own alpha, which the glow keeps as it recolors the pixels (see `recolor`).
    static func innerGlowCoverage(_ image: CGImage, placed: CGRect, size: CGSize, glow: InnerGlowEffect) throws -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let blurred = try coverage(image, in: placed, size: size, blur: glow.size)
        let inside = try GuidedMatte.levels(of: blurred, width: width, height: height).map { max(0, min(1, 1 - $0)) }
        return try GuidedMatte.image(inside, width: width, height: height)
    }

    /// The layer's pixels with its mask applied, or the pixels as they are when it has none.
    private static func masked(_ image: CGImage, mask: CGImage?) throws -> CGImage {
        guard let mask else { return image }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        // Draw the source and its grayscale mask in the same image coordinate system.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.clip(to: bounds, mask: mask)
        context.draw(image, in: bounds)
        guard let result = context.makeImage() else { throw ExportError.render }
        return result
    }

    /// Moves the pixels' color toward `color` by `alpha`, scaled by `amount` where given, keeping their alpha:
    /// source-atop, so a half-transparent pixel takes the color fully.
    static func recolor(_ context: CGContext, _ color: PaletteColor, alpha: Double, amount: CGImage?, in rect: CGRect) {
        context.saveGState()
        context.setBlendMode(.sourceAtop)
        if let amount { fill(color, alpha: alpha, coverage: amount, in: rect, context: context) }
        else {
            context.setFillColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: CGFloat(alpha)))
            context.fill(rect)
        }
        context.restoreGState()
    }

    /// A shadow's coverage for one piece of a layer: its shape, moved and softened.
    static func shadowCoverage(_ pixels: CGImage, in size: CGSize, offset: CGSize, blur: CGFloat) throws -> CGImage {
        let placed = CGRect(origin: .zero, size: CGSize(width: pixels.width, height: pixels.height))
        return try coverage(pixels, in: placed.offsetBy(dx: offset.width, dy: offset.height), size: size, blur: blur)
    }

    /// How strongly an inner shadow falls on each pixel: what lies outside the layer, moved and softened. Like
    /// `innerGlowCoverage`, it's the strength before the layer's own alpha.
    static func innerCoverage(_ image: CGImage, placed: CGRect, size: CGSize, shadow: InnerShadowEffect) throws -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let moved = try coverage(image, in: placed.offsetBy(dx: shadow.offset.width, dy: shadow.offset.height),
                                 size: size, blur: shadow.blur)
        let inside = try GuidedMatte.levels(of: moved, width: width, height: height).map { max(0, min(1, 1 - $0)) }
        return try GuidedMatte.image(inside, width: width, height: height)
    }

    /// An outer glow's coverage: the layer's shape softened omnidirectionally, with the shape interior excluded.
    static func outerGlowCoverage(_ image: CGImage, placed: CGRect, size: CGSize, glow: OuterGlowEffect) throws -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let shape = try coverage(image, in: placed, size: size, blur: 0)
        let soft = try coverage(image, in: placed, size: size, blur: glow.size)
        var levels = try GuidedMatte.levels(of: soft, width: width, height: height)
        let mask = try GuidedMatte.levels(of: shape, width: width, height: height)
        for i in levels.indices {
            levels[i] = max(0, min(1, levels[i] * (1 - mask[i])))
        }
        return try GuidedMatte.image(levels, width: width, height: height)
    }

    /// A stroke's ring for one piece of a layer.
    static func ringCoverage(_ pixels: CGImage, in size: CGSize, stroke: StrokeEffect) throws -> CGImage {
        try strokeCoverage(pixels, placed: CGRect(origin: .zero, size: CGSize(width: pixels.width, height: pixels.height)),
                           size: size, stroke: stroke)
    }

    /// The shape's own alpha, placed in a bigger canvas and optionally softened: gray, white where the layer is.
    static func coverage(_ image: CGImage, in rect: CGRect, size: CGSize, blur: CGFloat) throws -> CGImage {
        let context = try BrushRaster.context(width: Int(size.width), height: Int(size.height), mask: true)
        BrushRaster.draw(image, in: rect, mask: true, context: context)
        guard let sharp = context.makeImage() else { throw ExportError.render }
        guard blur > 0 else { return sharp }
        let extent = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let soft = CIImage(cgImage: sharp).clampedToExtent().applyingGaussianBlur(sigma: blur / 2).cropped(to: extent)
        return try PixelAdjust.render(soft, width: Int(size.width), height: Int(size.height), isMask: true)
    }

    /// Where a stroke lands: the shape grown (or shrunk) by its size, less the shape itself. The reach is round, measured
    /// as the true distance from the shape's edge, so a circle's stroke is as thick on the diagonals as at the sides and
    /// an outside stroke rounds a rectangle's corners, as Photoshop's does.
    static func strokeCoverage(_ image: CGImage, placed: CGRect, size: CGSize, stroke: StrokeEffect) throws -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let shape = try coverage(image, in: placed, size: size, blur: 0)
        var levels = try GuidedMatte.levels(of: shape, width: width, height: height)
        switch stroke.resolvedPosition {
        case .center:
            let halfReach = Float(stroke.size) * 0.5
            let limit = Int(halfReach.rounded(.up)) + 2
            let outDistances = edgeDistances(levels, width: width, height: height, inside: false, limit: limit)
            let inDistances = edgeDistances(levels, width: width, height: height, inside: true, limit: limit)
            for i in levels.indices {
                let outReached = min(1, max(0, halfReach + 1 - outDistances[i]))
                let inReached = min(1, max(0, halfReach + 1 - inDistances[i]))
                let outRing = max(0, outReached - levels[i])
                let inRing = max(0, levels[i] - (1 - inReached))
                levels[i] = min(1, outRing + inRing)
            }
        case .outside, .inside:
            let inside = stroke.resolvedPosition == .inside
            let reach = Float(stroke.size)
            let distances = edgeDistances(levels, width: width, height: height, inside: inside,
                                          limit: Int(reach.rounded(.up)) + 2)
            for i in levels.indices {
                // How much of this pixel the grown (or shrunk) shape covers. A pixel's center sits half a pixel past the
                // edge of the nearest one counted as the shape, so the edge is at `distance - 0.5` and the reach blends
                // across the pixel that straddles it.
                let reached = min(1, max(0, reach + 1 - distances[i]))
                levels[i] = inside ? max(0, levels[i] - (1 - reached)) : max(0, reached - levels[i])
            }
        }
        return try GuidedMatte.image(levels, width: width, height: height)
    }

    /// For each pixel, how far it is from the nearest pixel on the other side of the shape's edge: from the shape for
    /// an outside stroke, from what's around it for an inside one, where past the image's edge also counts as around
    /// it. Pixels at least half covered are the shape. Distances beyond `limit` come back as `limit + 1` or more.
    /// A row pass then a column pass (Felzenszwalb and Huttenlocher's), so the cost doesn't grow with the reach.
    static func edgeDistances(_ levels: [Float], width: Int, height: Int, inside: Bool, limit: Int) -> [Float] {
        guard width > 0, height > 0, levels.count == width * height else { return [] }
        let cap = limit + 1
        let far = Float(cap * cap)
        var squared = [Float](repeating: far, count: levels.count)
        // Along each row: the distance to the nearest pixel on the other side, kept squared for the column pass.
        levels.withUnsafeBufferPointer { levels in
            squared.withUnsafeMutableBufferPointer { squared in
                for row in 0..<height {
                    let base = row * width
                    func isTarget(_ x: Int) -> Bool { (levels[base + x] >= 0.5) != inside }
                    var last = inside ? -1 : Int.min / 2
                    for x in 0..<width {
                        if isTarget(x) { last = x }
                        let gap = min(cap, x - last)
                        squared[base + x] = Float(gap * gap)
                    }
                    last = inside ? width : Int.max / 2
                    for x in stride(from: width - 1, through: 0, by: -1) {
                        if isTarget(x) { last = x }
                        let gap = min(cap, last - x)
                        squared[base + x] = min(squared[base + x], Float(gap * gap))
                    }
                }
            }
        }
        // Down each column: the lowest of the parabolas the row distances make, which is the distance in two dimensions.
        var column = [Float](repeating: 0, count: height)
        var lowest = [Int](repeating: 0, count: height)
        var bounds = [Float](repeating: 0, count: height + 1)
        var result = [Float](repeating: 0, count: levels.count)
        for x in 0..<width {
            for y in 0..<height { column[y] = squared[y * width + x] }
            var count = 0
            lowest[0] = 0
            bounds[0] = -.infinity
            bounds[1] = .infinity
            // Where the parabolas from rows q and p cross, written without squaring the row numbers, which would
            // lose precision in Float on a tall image.
            func crossing(_ q: Int, _ p: Int) -> Float {
                ((column[q] - column[p]) / Float(q - p) + Float(q + p)) / 2
            }
            for q in 1..<max(1, height) {
                var crossesAt = crossing(q, lowest[count])
                while crossesAt <= bounds[count] {
                    count -= 1
                    crossesAt = crossing(q, lowest[count])
                }
                count += 1
                lowest[count] = q
                bounds[count] = crossesAt
                bounds[count + 1] = .infinity
            }
            count = 0
            for y in 0..<height {
                while bounds[count + 1] < Float(y) { count += 1 }
                let p = lowest[count]
                var distance = Float((y - p) * (y - p)) + column[p]
                // Past the top and bottom edges counts as around the shape.
                if inside { distance = min(distance, Float((y + 1) * (y + 1)), Float((height - y) * (height - y))) }
                result[y * width + x] = distance.squareRoot()
            }
        }
        return result
    }

    static func fill(_ color: PaletteColor, alpha: Double, coverage: CGImage, in rect: CGRect, context: CGContext) {
        // Coverage is a CGImage: use the same local image flip as the source, so asymmetric marks
        // and their effects line up instead of mirroring the coverage vertically.
        BrushRaster.fill(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1),
                         coverage: coverage, in: rect, alpha: CGFloat(alpha), context: context)
    }
}
