import AppKit
import CoreGraphics

/// A single Bézier anchor point in document pixel coordinates.
nonisolated struct PathAnchor: Codable, Equatable, Sendable {
    var point: CGPoint
    /// Incoming cubic Bézier control point (document coordinates). Nil means no incoming handle (corner tangent).
    var handleIn: CGPoint?
    /// Outgoing cubic Bézier control point (document coordinates). Nil means no outgoing handle (corner tangent).
    var handleOut: CGPoint?

    init(point: CGPoint, handleIn: CGPoint? = nil, handleOut: CGPoint? = nil) {
        self.point = point
        self.handleIn = handleIn
        self.handleOut = handleOut
    }

    var isValid: Bool {
        guard point.x.isFinite && point.y.isFinite else { return false }
        if let h = handleIn, !(h.x.isFinite && h.y.isFinite) { return false }
        if let h = handleOut, !(h.x.isFinite && h.y.isFinite) { return false }
        return true
    }

    mutating func translate(dx: CGFloat, dy: CGFloat) {
        point.x += dx; point.y += dy
        if var h = handleIn { h.x += dx; h.y += dy; handleIn = h }
        if var h = handleOut { h.x += dx; h.y += dy; handleOut = h }
    }
}

/// An open or closed sequence of Bézier anchors.
nonisolated struct VectorSubpath: Codable, Equatable, Sendable {
    var anchors: [PathAnchor]
    var isClosed: Bool

    init(anchors: [PathAnchor] = [], isClosed: Bool = false) {
        self.anchors = anchors
        self.isClosed = isClosed
    }

    var isValid: Bool {
        anchors.count <= 4096 && anchors.allSatisfy(\.isValid)
    }

    func append(to path: CGMutablePath, transform: CGAffineTransform = .identity, forceClose: Bool = false) {
        guard let first = anchors.first else { return }
        path.move(to: first.point.applying(transform))
        if anchors.count > 1 {
            for i in 1..<anchors.count {
                let prev = anchors[i - 1], cur = anchors[i]
                addSegment(from: prev, to: cur, to: path, transform: transform)
            }
        }
        if (isClosed || forceClose), anchors.count >= 2 {
            let last = anchors[anchors.count - 1]
            addSegment(from: last, to: first, to: path, transform: transform)
            path.closeSubpath()
        }
    }

    private func addSegment(from a: PathAnchor, to b: PathAnchor, to path: CGMutablePath, transform: CGAffineTransform) {
        let end = b.point.applying(transform)
        if a.handleOut != nil || b.handleIn != nil {
            let c1 = (a.handleOut ?? a.point).applying(transform)
            let c2 = (b.handleIn ?? b.point).applying(transform)
            path.addCurve(to: end, control1: c1, control2: c2)
        } else {
            path.addLine(to: end)
        }
    }

    /// Evaluates points, unit tangents, and cumulative arc lengths along this subpath (for Text on Path and hit testing).
    struct ArcSample: Sendable {
        let point: CGPoint
        let tangent: CGVector
        let distance: CGFloat
    }

    func arcLengthSamples(stepsPerSegment: Int = 24) -> [ArcSample] {
        guard anchors.count >= 2 else { return [] }
        let segCount = isClosed ? anchors.count : anchors.count - 1
        var samples: [ArcSample] = []
        var totalDist: CGFloat = 0
        var prevPt: CGPoint?

        func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, t: CGFloat) -> CGPoint {
            let u = 1 - t
            let uu = u * u, tt = t * t
            let x = uu * u * p0.x + 3 * uu * t * p1.x + 3 * u * tt * p2.x + tt * t * p3.x
            let y = uu * u * p0.y + 3 * uu * t * p1.y + 3 * u * tt * p2.y + tt * t * p3.y
            return CGPoint(x: x, y: y)
        }

        func cubicTangent(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, t: CGFloat) -> CGVector {
            let u = 1 - t
            let dx = 3 * u * u * (p1.x - p0.x) + 6 * u * t * (p2.x - p1.x) + 3 * t * t * (p3.x - p2.x)
            let dy = 3 * u * u * (p1.y - p0.y) + 6 * u * t * (p2.y - p1.y) + 3 * t * t * (p3.y - p2.y)
            let len = hypot(dx, dy)
            guard len > 1e-6 else { return CGVector(dx: 1, dy: 0) }
            return CGVector(dx: dx / len, dy: dy / len)
        }

        for seg in 0..<segCount {
            let a = anchors[seg]
            let b = anchors[(seg + 1) % anchors.count]
            let p0 = a.point
            let p1 = a.handleOut ?? CGPoint(x: p0.x + (b.point.x - p0.x) / 3, y: p0.y + (b.point.y - p0.y) / 3)
            let p2 = b.handleIn ?? CGPoint(x: p0.x + 2 * (b.point.x - p0.x) / 3, y: p0.y + 2 * (b.point.y - p0.y) / 3)
            let p3 = b.point
            let steps = (a.handleOut == nil && b.handleIn == nil) ? 4 : max(4, stepsPerSegment)
            let startStep = (seg == 0) ? 0 : 1
            for s in startStep...steps {
                let t = CGFloat(s) / CGFloat(steps)
                let pt = cubic(p0, p1, p2, p3, t: t)
                let tan = cubicTangent(p0, p1, p2, p3, t: t)
                if let prev = prevPt {
                    totalDist += hypot(pt.x - prev.x, pt.y - prev.y)
                }
                samples.append(ArcSample(point: pt, tangent: tan, distance: totalDist))
                prevPt = pt
            }
        }
        return samples
    }
}

/// A named vector path stored on the document (or as a layer's vector mask).
nonisolated struct VectorPath: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var subpaths: [VectorSubpath]
    var isVisible: Bool

    init(id: UUID = UUID(), name: String, subpaths: [VectorSubpath] = [], isVisible: Bool = true) {
        self.id = id
        self.name = name
        self.subpaths = subpaths
        self.isVisible = isVisible
    }

    var isEmpty: Bool { subpaths.allSatisfy { $0.anchors.isEmpty } }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && subpaths.count <= 512
            && subpaths.allSatisfy(\.isValid)
    }

    func cgPath(transform: CGAffineTransform = .identity, closeForFill: Bool = false) -> CGPath {
        let path = CGMutablePath()
        for subpath in subpaths {
            subpath.append(to: path, transform: transform, forceClose: closeForFill)
        }
        return path
    }

    /// Builds a `VectorPath` from any Core Graphics path (preserving cubic Bézier curves and converting quads to cubics).
    static func fromCGPath(_ cgPath: CGPath, name: String, id: UUID = UUID()) -> VectorPath {
        var subpaths: [VectorSubpath] = []
        var currentAnchors: [PathAnchor] = []
        var currentClosed = false

        func flush() {
            guard !currentAnchors.isEmpty else { return }
            // When a closed path's last anchor coincides with the first, merge its incoming handle into the first anchor.
            if currentClosed, currentAnchors.count >= 2 {
                let first = currentAnchors[0], last = currentAnchors[currentAnchors.count - 1]
                if hypot(first.point.x - last.point.x, first.point.y - last.point.y) < 0.01 {
                    currentAnchors[0].handleIn = last.handleIn
                    currentAnchors.removeLast()
                }
            }
            subpaths.append(VectorSubpath(anchors: currentAnchors, isClosed: currentClosed))
            currentAnchors = []
            currentClosed = false
        }

        cgPath.applyWithBlock { ptr in
            let el = ptr.pointee
            switch el.type {
            case .moveToPoint:
                flush()
                currentAnchors = [PathAnchor(point: el.points[0])]
            case .addLineToPoint:
                let pt = el.points[0]
                if currentAnchors.isEmpty {
                    currentAnchors = [PathAnchor(point: pt)]
                } else {
                    currentAnchors.append(PathAnchor(point: pt))
                }
            case .addQuadCurveToPoint:
                let ctrl = el.points[0], end = el.points[1]
                if let prev = currentAnchors.last {
                    let c1 = CGPoint(x: prev.point.x + 2.0 / 3.0 * (ctrl.x - prev.point.x),
                                     y: prev.point.y + 2.0 / 3.0 * (ctrl.y - prev.point.y))
                    let c2 = CGPoint(x: end.x + 2.0 / 3.0 * (ctrl.x - end.x),
                                     y: end.y + 2.0 / 3.0 * (ctrl.y - end.y))
                    currentAnchors[currentAnchors.count - 1].handleOut = c1
                    currentAnchors.append(PathAnchor(point: end, handleIn: c2))
                }
            case .addCurveToPoint:
                let c1 = el.points[0], c2 = el.points[1], end = el.points[2]
                if !currentAnchors.isEmpty {
                    currentAnchors[currentAnchors.count - 1].handleOut = c1
                    currentAnchors.append(PathAnchor(point: end, handleIn: c2))
                }
            case .closeSubpath:
                currentClosed = true
                flush()
            @unknown default:
                break
            }
        }
        flush()
        return VectorPath(id: id, name: name, subpaths: subpaths)
    }

    func translated(dx: CGFloat, dy: CGFloat) -> VectorPath {
        var copy = self
        for s in copy.subpaths.indices {
            for a in copy.subpaths[s].anchors.indices {
                copy.subpaths[s].anchors[a].translate(dx: dx, dy: dy)
            }
        }
        return copy
    }
}

/// Interactive modes for the Pen tool (`P`).
nonisolated enum PenToolMode: String, CaseIterable, Sendable {
    case draw = "Pen"
    case edit = "Direct Select"
    case deleteAnchor = "Delete Anchor"
    case convertPoint = "Convert Point"
}

/// Identifies a specific anchor inside a document path.
struct PathAnchorRef: Equatable, Sendable {
    let pathID: UUID
    let subpathIndex: Int
    let anchorIndex: Int
}

/// Which part of an anchor is being dragged interactively on the canvas.
enum PenDragTarget: Equatable {
    case pullNewHandles(PathAnchorRef)
    case moveAnchor(PathAnchorRef, startPoint: CGPoint, original: PathAnchor)
    case moveHandleIn(PathAnchorRef, breakSymmetry: Bool)
    case moveHandleOut(PathAnchorRef, breakSymmetry: Bool)
}

/// Tabs in the right inspector dock.
enum RightPanelTab: String, CaseIterable, Sendable {
    case layers = "Layers"
    case paths = "Paths"
}

extension EditorSession {
    var activePath: VectorPath? {
        guard let id = activePathID else { return nil }
        return document?.paths.first(where: { $0.id == id })
    }

    func nextPathName() -> String {
        let existing = Set((document?.paths ?? []).map(\.name))
        var n = 1
        while existing.contains(L10n.format("Path %lld", n)) { n += 1 }
        return L10n.format("Path %lld", n)
    }

    @discardableResult
    func addNewPath(name: String? = nil, subpaths: [VectorSubpath] = []) -> UUID? {
        guard document != nil else { return nil }
        finishOpacityEdit()
        let path = VectorPath(name: name ?? nextPathName(), subpaths: subpaths)
        beginEdit("New Path")
        document?.paths.append(path)
        activePathID = path.id
        selectedAnchor = nil
        endEdit()
        return path.id
    }

    func selectPath(_ id: UUID?) {
        activePathID = id
        selectedAnchor = nil
        penDrag = nil
    }

    func deletePath(_ id: UUID) {
        guard let index = document?.paths.firstIndex(where: { $0.id == id }) else { return }
        finishOpacityEdit()
        beginEdit("Delete Path")
        document?.paths.remove(at: index)
        if activePathID == id {
            activePathID = document?.paths.last?.id
            selectedAnchor = nil
            penDrag = nil
        }
        endEdit()
    }

    func duplicatePath(_ id: UUID) {
        guard let original = document?.paths.first(where: { $0.id == id }) else { return }
        let copy = VectorPath(name: L10n.format("%@ copy", original.name), subpaths: original.subpaths, isVisible: original.isVisible)
        finishOpacityEdit()
        beginEdit("Duplicate Path")
        document?.paths.append(copy)
        activePathID = copy.id
        selectedAnchor = nil
        endEdit()
    }

    func togglePathVisibility(_ id: UUID) {
        guard let index = document?.paths.firstIndex(where: { $0.id == id }) else { return }
        beginEdit("Path Visibility")
        document?.paths[index].isVisible.toggle()
        endEdit()
    }

    func renamePath(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = document?.paths.firstIndex(where: { $0.id == id }),
              document?.paths[index].name != trimmed else { return }
        beginEdit("Rename Path")
        document?.paths[index].name = trimmed
        endEdit()
    }

    // MARK: - Interactive Pen Gestures

    func penMouseDown(at point: CGPoint, option: Bool, shift: Bool) {
        guard tool == .pen, let document, point.x.isFinite, point.y.isFinite else { return }
        finishOpacityEdit()
        let hitRadius = max(6.0, 9.0 / max(0.1, viewport.pointsPerPixel))

        switch penMode {
        case .draw:
            // Ensure an active path exists.
            var pathIndex: Int
            if let id = activePathID, let idx = document.paths.firstIndex(where: { $0.id == id }) {
                pathIndex = idx
            } else {
                let newPath = VectorPath(name: nextPathName(), subpaths: [])
                beginEdit("Pen")
                self.document?.paths.append(newPath)
                activePathID = newPath.id
                pathIndex = (self.document?.paths.count ?? 1) - 1
                self.document?.paths[pathIndex].subpaths.append(VectorSubpath(anchors: [PathAnchor(point: point)], isClosed: false))
                let ref = PathAnchorRef(pathID: newPath.id, subpathIndex: 0, anchorIndex: 0)
                selectedAnchor = ref
                penDrag = .pullNewHandles(ref)
                return
            }

            let pathID = document.paths[pathIndex].id
            let subpaths = document.paths[pathIndex].subpaths

            // If we have an open subpath with >= 2 anchors and clicked near its first anchor, close the subpath!
            if let lastSubIdx = subpaths.indices.last, !subpaths[lastSubIdx].isClosed,
               subpaths[lastSubIdx].anchors.count >= 2 {
                let first = subpaths[lastSubIdx].anchors[0]
                if hypot(point.x - first.point.x, point.y - first.point.y) <= hitRadius {
                    beginEdit("Close Path")
                    self.document?.paths[pathIndex].subpaths[lastSubIdx].isClosed = true
                    let ref = PathAnchorRef(pathID: pathID, subpathIndex: lastSubIdx, anchorIndex: 0)
                    selectedAnchor = ref
                    penDrag = .pullNewHandles(ref)
                    return
                }
            }

            beginEdit("Add Anchor")
            if subpaths.isEmpty || subpaths.last?.isClosed == true {
                self.document?.paths[pathIndex].subpaths.append(VectorSubpath(anchors: [PathAnchor(point: point)], isClosed: false))
                let subIdx = (self.document?.paths[pathIndex].subpaths.count ?? 1) - 1
                let ref = PathAnchorRef(pathID: pathID, subpathIndex: subIdx, anchorIndex: 0)
                selectedAnchor = ref
                penDrag = .pullNewHandles(ref)
            } else {
                let subIdx = subpaths.count - 1
                var pt = point
                if shift, let prev = subpaths[subIdx].anchors.last?.point {
                    let dx = pt.x - prev.x, dy = pt.y - prev.y
                    let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                    let len = hypot(dx, dy)
                    pt = CGPoint(x: prev.x + cos(angle) * len, y: prev.y + sin(angle) * len)
                }
                self.document?.paths[pathIndex].subpaths[subIdx].anchors.append(PathAnchor(point: pt))
                let aIdx = (self.document?.paths[pathIndex].subpaths[subIdx].anchors.count ?? 1) - 1
                let ref = PathAnchorRef(pathID: pathID, subpathIndex: subIdx, anchorIndex: aIdx)
                selectedAnchor = ref
                penDrag = .pullNewHandles(ref)
            }

        case .edit:
            // First check selected anchor's Bézier handles.
            if let ref = selectedAnchor, let anchor = anchor(for: ref) {
                if let hIn = anchor.handleIn, hypot(point.x - hIn.x, point.y - hIn.y) <= hitRadius {
                    beginEdit("Adjust Handle")
                    penDrag = .moveHandleIn(ref, breakSymmetry: option)
                    return
                }
                if let hOut = anchor.handleOut, hypot(point.x - hOut.x, point.y - hOut.y) <= hitRadius {
                    beginEdit("Adjust Handle")
                    penDrag = .moveHandleOut(ref, breakSymmetry: option)
                    return
                }
            }
            // Next hit-test any anchor in the active path.
            if let hit = hitTestAnchor(at: point, radius: hitRadius) {
                selectedAnchor = hit
                if let orig = anchor(for: hit) {
                    beginEdit("Move Anchor")
                    penDrag = .moveAnchor(hit, startPoint: point, original: orig)
                }
            } else {
                selectedAnchor = nil
            }

        case .deleteAnchor:
            if let hit = hitTestAnchor(at: point, radius: hitRadius) {
                deleteAnchor(hit)
            }

        case .convertPoint:
            if let hit = hitTestAnchor(at: point, radius: hitRadius) {
                selectedAnchor = hit
                beginEdit("Convert Anchor")
                mutateAnchor(hit) { a in
                    a.handleIn = nil
                    a.handleOut = nil
                }
                penDrag = .pullNewHandles(hit)
            }
        }
    }

    func penMouseDragged(to point: CGPoint, option: Bool, shift: Bool) {
        guard let drag = penDrag, point.x.isFinite, point.y.isFinite else { return }
        switch drag {
        case .pullNewHandles(let ref):
            mutateAnchor(ref) { anchor in
                var dx = point.x - anchor.point.x
                var dy = point.y - anchor.point.y
                if shift {
                    let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                    let len = hypot(dx, dy)
                    dx = cos(angle) * len; dy = sin(angle) * len
                }
                guard hypot(dx, dy) > 1.5 else { return }
                anchor.handleOut = CGPoint(x: anchor.point.x + dx, y: anchor.point.y + dy)
                if !option {
                    anchor.handleIn = CGPoint(x: anchor.point.x - dx, y: anchor.point.y - dy)
                }
            }
        case .moveAnchor(let ref, let start, let original):
            let dx = point.x - start.x, dy = point.y - start.y
            mutateAnchor(ref) { anchor in
                anchor = original
                anchor.translate(dx: dx, dy: dy)
            }
        case .moveHandleIn(let ref, let broken):
            mutateAnchor(ref) { anchor in
                anchor.handleIn = point
                if !broken && !option {
                    anchor.handleOut = CGPoint(x: 2 * anchor.point.x - point.x, y: 2 * anchor.point.y - point.y)
                }
            }
        case .moveHandleOut(let ref, let broken):
            mutateAnchor(ref) { anchor in
                anchor.handleOut = point
                if !broken && !option {
                    anchor.handleIn = CGPoint(x: 2 * anchor.point.x - point.x, y: 2 * anchor.point.y - point.y)
                }
            }
        }
    }

    func penMouseUp() {
        guard penDrag != nil else { return }
        penDrag = nil
        endEdit()
    }

    func finishCurrentSubpath() {
        penDrag = nil
        selectedAnchor = nil
        // Starting the next click as a fresh subpath is easiest when the current open subpath is sealed or deselected;
        // if an open path has only 1 anchor, leave it or start a new path on next click by creating a fresh subpath.
        guard let id = activePathID, let idx = document?.paths.firstIndex(where: { $0.id == id }),
              let last = document?.paths[idx].subpaths.last, !last.isClosed, !last.anchors.isEmpty else { return }
        // Append an empty placeholder only on next click? Even cleaner: close only on explicit close, otherwise deselect path
        // if user wants a new path, OR close when `closeActiveSubpath()` is called. Here `finishCurrentSubpath()` deselects anchor.
    }

    func closeActiveSubpath() {
        guard let id = activePathID, let idx = document?.paths.firstIndex(where: { $0.id == id }),
              let subIdx = document?.paths[idx].subpaths.indices.last,
              document?.paths[idx].subpaths[subIdx].isClosed == false,
              (document?.paths[idx].subpaths[subIdx].anchors.count ?? 0) >= 2 else { return }
        beginEdit("Close Path")
        document?.paths[idx].subpaths[subIdx].isClosed = true
        endEdit()
    }

    func deleteAnchor(_ ref: PathAnchorRef) {
        guard let idx = document?.paths.firstIndex(where: { $0.id == ref.pathID }),
              document?.paths[idx].subpaths.indices.contains(ref.subpathIndex) == true,
              document?.paths[idx].subpaths[ref.subpathIndex].anchors.indices.contains(ref.anchorIndex) == true else { return }
        beginEdit("Delete Anchor")
        document?.paths[idx].subpaths[ref.subpathIndex].anchors.remove(at: ref.anchorIndex)
        if document?.paths[idx].subpaths[ref.subpathIndex].anchors.isEmpty == true {
            document?.paths[idx].subpaths.remove(at: ref.subpathIndex)
        }
        if selectedAnchor == ref { selectedAnchor = nil }
        endEdit()
    }

    func deleteSelectedAnchorOrPath() -> Bool {
        if let ref = selectedAnchor {
            deleteAnchor(ref)
            return true
        }
        if let id = activePathID {
            deletePath(id)
            return true
        }
        return false
    }

    private func anchor(for ref: PathAnchorRef) -> PathAnchor? {
        guard let path = document?.paths.first(where: { $0.id == ref.pathID }),
              path.subpaths.indices.contains(ref.subpathIndex),
              path.subpaths[ref.subpathIndex].anchors.indices.contains(ref.anchorIndex) else { return nil }
        return path.subpaths[ref.subpathIndex].anchors[ref.anchorIndex]
    }

    private func mutateAnchor(_ ref: PathAnchorRef, _ body: (inout PathAnchor) -> Void) {
        guard let idx = document?.paths.firstIndex(where: { $0.id == ref.pathID }),
              document?.paths[idx].subpaths.indices.contains(ref.subpathIndex) == true,
              document?.paths[idx].subpaths[ref.subpathIndex].anchors.indices.contains(ref.anchorIndex) == true else { return }
        body(&document!.paths[idx].subpaths[ref.subpathIndex].anchors[ref.anchorIndex])
    }

    private func hitTestAnchor(at point: CGPoint, radius: CGFloat) -> PathAnchorRef? {
        guard let path = activePath else { return nil }
        var best: (PathAnchorRef, CGFloat)?
        for (sIdx, sub) in path.subpaths.enumerated() {
            for (aIdx, anchor) in sub.anchors.enumerated() {
                let d = hypot(point.x - anchor.point.x, point.y - anchor.point.y)
                if d <= radius, best == nil || d < best!.1 {
                    best = (PathAnchorRef(pathID: path.id, subpathIndex: sIdx, anchorIndex: aIdx), d)
                }
            }
        }
        return best?.0
    }

    // MARK: - Path Actions (Selection, Fill, Stroke, Selection -> Path)

    /// Converts a vector path into a marching-ants document selection.
    func pathToSelection(_ id: UUID? = nil, feather: CGFloat = 0) {
        guard let document,
              let path = (id.flatMap { pid in document.paths.first(where: { $0.id == pid }) }) ?? activePath,
              !path.isEmpty else { return }
        let cg = path.cgPath(closeForFill: true)
        let canvas = CGPath(rect: CGRect(origin: .zero, size: document.size), transform: nil)
        let clipped = cg.intersection(canvas)
        guard !clipped.isEmpty else { return }
        finishOpacityEdit()
        beginEdit("Path to Selection")
        self.document?.selection = DocumentSelection(path: clipped, antialiased: true, feather: max(0, feather))
        endEdit()
    }

    /// Converts the active document selection outline into a new editable `VectorPath`.
    @discardableResult
    func selectionToPath() -> UUID? {
        guard let selection = document?.selection, !selection.isEmpty else { return nil }
        let vp = VectorPath.fromCGPath(selection.path, name: nextPathName())
        guard !vp.isEmpty else { return nil }
        return addNewPath(name: vp.name, subpaths: vp.subpaths)
    }

    /// Fills the vector path with `color` (defaults to foreground color) onto a new raster layer above the active layer.
    func fillPath(_ id: UUID? = nil, color: PaletteColor? = nil) {
        guard canEditLayers, let document,
              let path = (id.flatMap { pid in document.paths.first(where: { $0.id == pid }) }) ?? activePath,
              !path.isEmpty else { return }
        let fill = color ?? foregroundColor
        let cg = path.cgPath(closeForFill: true)
        let bounds = cg.boundingBoxOfPath.integral.intersection(CGRect(origin: .zero, size: document.size))
        guard bounds.width >= 1, bounds.height >= 1 else { return }
        do {
            let ctx = try BrushRaster.context(width: Int(bounds.width), height: Int(bounds.height), mask: false)
            ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
            ctx.setFillColor(fill.nsColor.cgColor)
            ctx.addPath(cg)
            ctx.fillPath(using: .winding)
            guard let image = ctx.makeImage() else { throw ExportError.render }
            addPixelLayer(image, at: bounds.origin, name: L10n.format("%@ Fill", path.name), editName: "Fill Path", dropsSelection: false)
        } catch {
            brushError = error.localizedDescription
        }
    }

    /// Strokes the vector path with `width` (defaults to `penStrokeWidth`) and `color` (defaults to foreground color) onto a new layer.
    func strokePath(_ id: UUID? = nil, width: CGFloat? = nil, color: PaletteColor? = nil) {
        guard canEditLayers, let document,
              let path = (id.flatMap { pid in document.paths.first(where: { $0.id == pid }) }) ?? activePath,
              !path.isEmpty else { return }
        let strokeColor = color ?? foregroundColor
        let lineWidth = max(1, min(500, width ?? CGFloat(penStrokeWidth)))
        let cg = path.cgPath(closeForFill: false)
        let pad = ceil(lineWidth / 2) + 2
        let bounds = cg.boundingBoxOfPath.insetBy(dx: -pad, dy: -pad).integral
            .intersection(CGRect(origin: .zero, size: document.size))
        guard bounds.width >= 1, bounds.height >= 1 else { return }
        do {
            let ctx = try BrushRaster.context(width: Int(bounds.width), height: Int(bounds.height), mask: false)
            ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
            ctx.setStrokeColor(strokeColor.nsColor.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(cg)
            ctx.strokePath()
            guard let image = ctx.makeImage() else { throw ExportError.render }
            addPixelLayer(image, at: bounds.origin, name: L10n.format("%@ Stroke", path.name), editName: "Stroke Path", dropsSelection: false)
        } catch {
            brushError = error.localizedDescription
        }
    }
}
