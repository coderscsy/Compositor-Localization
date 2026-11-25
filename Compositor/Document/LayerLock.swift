import Foundation

/// The four Photoshop-style lock toggles a layer or folder can hold.
nonisolated enum LayerLockKind: String, CaseIterable, Sendable {
    case transparent = "Lock Transparent Pixels"
    case pixels = "Lock Image Pixels"
    case position = "Lock Position"
    case all = "Lock All"

    var symbol: String {
        switch self {
        case .transparent: "checkerboard.rectangle"
        case .pixels: "paintbrush.pointed"
        case .position: "arrow.up.and.down.and.arrow.left.and.right"
        case .all: "lock.fill"
        }
    }
}

/// Per-layer edit restrictions. Omitted from saved manifests when empty (all false).
nonisolated struct LayerLock: Codable, Equatable, Hashable, Sendable {
    var transparent = false
    var pixels = false
    var position = false
    var all = false

    var isEmpty: Bool { !transparent && !pixels && !position && !all }
    var isLocked: Bool { !isEmpty }
    /// Prevents painting, erasing, filters, adjustments, fills, and pixel edits.
    var blocksPixels: Bool { all || pixels }
    /// Prevents moving, scaling, rotating, flipping, aligning, and distorting.
    var blocksPosition: Bool { all || position }
    /// Keeps every pixel's alpha intact while allowing RGB edits inside existing opacity.
    var locksTransparentPixels: Bool { transparent && !blocksPixels }
    /// Prevents opacity and blend mode edits.
    var blocksAppearance: Bool { all }
    /// Prevents deleting, renaming, reordering, merging, clipping, masks, and effects.
    var blocksStructure: Bool { all }

    /// Combines this layer's own lock with an enclosing folder's lock.
    func inheriting(_ ancestor: LayerLock) -> LayerLock {
        LayerLock(transparent: transparent,
                  pixels: pixels || ancestor.pixels,
                  position: position || ancestor.position,
                  all: all || ancestor.all)
    }

    subscript(kind: LayerLockKind) -> Bool {
        get {
            switch kind {
            case .transparent: transparent
            case .pixels: pixels
            case .position: position
            case .all: all
            }
        }
        set {
            switch kind {
            case .transparent: transparent = newValue
            case .pixels: pixels = newValue
            case .position: position = newValue
            case .all: all = newValue
            }
        }
    }

    /// Encodes only true flags so manifests stay compact and readable; missing keys default to false.
    private enum CodingKeys: String, CodingKey { case transparent, pixels, position, all }

    init(transparent: Bool = false, pixels: Bool = false, position: Bool = false, all: Bool = false) {
        self.transparent = transparent
        self.pixels = pixels
        self.position = position
        self.all = all
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transparent = try container.decodeIfPresent(Bool.self, forKey: .transparent) ?? false
        pixels = try container.decodeIfPresent(Bool.self, forKey: .pixels) ?? false
        position = try container.decodeIfPresent(Bool.self, forKey: .position) ?? false
        all = try container.decodeIfPresent(Bool.self, forKey: .all) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if transparent { try container.encode(true, forKey: .transparent) }
        if pixels { try container.encode(true, forKey: .pixels) }
        if position { try container.encode(true, forKey: .position) }
        if all { try container.encode(true, forKey: .all) }
    }
}

extension CanvasDocument {
    /// A layer's effective lock, combining its own lock with any enclosing folder's locks.
    func effectiveLock(for id: UUID) -> LayerLock {
        let byID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        guard let target = byID[id] else { return LayerLock() }
        var result = target.lock
        var parent = target.parentID
        var depth = 0
        while let current = parent, let folder = byID[current], depth < 64 {
            result = result.inheriting(folder.lock)
            parent = folder.parentID
            depth += 1
        }
        return result
    }
}

extension EditorSession {
    func effectiveLock(for id: UUID) -> LayerLock {
        document?.effectiveLock(for: id) ?? LayerLock()
    }

    /// True if the active layer or any selected layer (or its contents) has structure locked.
    var hasStructureLockedSelection: Bool {
        guard let document else { return false }
        let selected = selectedLayerIDs.isEmpty ? (activeLayerID.map { Set([$0]) } ?? []) : selectedLayerIDs
        for id in selected {
            if document.effectiveLock(for: id).blocksStructure { return true }
            if document.layers.first(where: { $0.id == id })?.isGroup == true {
                for child in descendantIDs(of: id) where document.effectiveLock(for: child).blocksStructure { return true }
            }
        }
        return false
    }

    /// True if any selected layer (or descendant of a selected folder) has position locked.
    var hasPositionLockedSelection: Bool {
        guard let document else { return false }
        let selected = selectedLayerIDs.isEmpty ? (activeLayerID.map { Set([$0]) } ?? []) : selectedLayerIDs
        for id in selected {
            if document.effectiveLock(for: id).blocksPosition { return true }
            if document.layers.first(where: { $0.id == id })?.isGroup == true {
                for child in descendantIDs(of: id) where document.effectiveLock(for: child).blocksPosition { return true }
            }
        }
        return false
    }

    /// Whether `kind` can be toggled for the current selection.
    func canToggleLayerLock(_ kind: LayerLockKind) -> Bool {
        guard canEditLayers, let document, let active = activeLayer else { return false }
        if kind == .all { return true }
        // While Lock All is active on the primary layer, the other three locks are superseded.
        if active.lock.all { return false }
        let selected = selectedLayerIDs.isEmpty ? [active.id] : selectedLayerIDs
        if kind == .transparent {
            // Transparent-pixel lock only applies to raster/image layers (not folders or adjustments).
            return document.layers.contains { selected.contains($0.id) && !$0.isGroup && $0.adjustment == nil }
        }
        return true
    }

    /// Toggles `kind` across every selected layer as one undo step.
    func toggleLayerLock(_ kind: LayerLockKind) {
        guard canToggleLayerLock(kind), let document, let active = activeLayer else { return }
        let selected = selectedLayerIDs.isEmpty ? Set([active.id]) : selectedLayerIDs
        let targetState = !active.lock[kind]
        var next = document.layers
        var changed = false
        for index in next.indices where selected.contains(next[index].id) {
            if kind == .transparent, next[index].isGroup || next[index].adjustment != nil { continue }
            if kind != .all, next[index].lock.all { continue }
            if next[index].lock[kind] != targetState {
                next[index].lock[kind] = targetState
                changed = true
            }
        }
        guard changed else { return }
        if targetState, kind == .position || kind == .all { commitTransform() }
        finishOpacityEdit()
        beginEdit(targetState ? kind.rawValue : "Unlock Layer")
        self.document?.layers = next
        endEdit()
    }
}
