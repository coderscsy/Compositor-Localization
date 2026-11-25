import AppKit

struct TransformOverlayGeometry: Equatable {
    let handles: [CGPoint]
    /// A distortion has no single rotation, so it can't be rotated.
    let showsRotation: Bool
    /// How far past a corner, outside the box, a press rotates rather than missing, as in Photoshop.
    static let rotationReach: CGFloat = 26

    init(transform: LayerTransform, viewport: CanvasViewport, documentSize: CGSize) {
        handles = LayerTransform.handles.map { viewport.viewPoint(from: transform.point($0), documentSize: documentSize) }
        showsRotation = true
    }

    /// Handles for a distortion: its four corners (document pixels) and the midpoints of its edges.
    init(corners: [CGPoint], viewport: CanvasViewport, documentSize: CGSize) {
        let view = corners.map { viewport.viewPoint(from: $0, documentSize: documentSize) }
        func middle(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        handles = [view[0], middle(view[0], view[1]), view[1], middle(view[1], view[2]),
                   view[2], middle(view[2], view[3]), view[3], middle(view[3], view[0])]
        showsRotation = false
    }

    func hit(_ point: CGPoint) -> TransformDrag.Mode? {
        func near(_ other: CGPoint) -> Bool { hypot(point.x - other.x, point.y - other.y) <= 10 }
        if let index = handles.firstIndex(where: near) { return .resize(index) }
        for (start, end, handle) in [(0, 2, 1), (2, 4, 3), (4, 6, 5), (6, 0, 7)] {
            let a = handles[start], b = handles[end]
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { continue }
            let t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
            if (0...1).contains(t), hypot(point.x - a.x - t * dx, point.y - a.y - t * dy) <= 10 {
                return .resize(handle)
            }
        }
        // Just outside the box, around a corner: rotates, from wherever the press lands.
        if showsRotation, !box.contains(point),
           [0, 2, 4, 6].contains(where: { hypot(point.x - handles[$0].x, point.y - handles[$0].y) <= Self.rotationReach }) {
            return .rotate
        }
        return nil
    }

    /// Which way the rotate pointer at `point` faces: out from the box's middle through its nearest corner, as an angle
    /// with y up, so each corner has its own curved arrow wrapped around it, as Photoshop's does.
    func rotationAngle(at point: CGPoint) -> CGFloat {
        let corners = [0, 2, 4, 6].map { handles[$0] }
        let middle = CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
        let corner = corners.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) }!
        return atan2(-(corner.y - middle.y), corner.x - middle.x)
    }

    /// The box through the four corner handles.
    var box: CGPath {
        let path = CGMutablePath()
        path.addLines(between: [handles[0], handles[2], handles[4], handles[6]])
        path.closeSubpath()
        return path
    }

    func resizeCursor(for index: Int) -> NSCursor {
        let angle = atan2(handles[2].y - handles[0].y, handles[2].x - handles[0].x)
        let offsets: [CGFloat] = [.pi / 4, .pi / 2, 3 * .pi / 4, 0, .pi / 4, .pi / 2, 3 * .pi / 4, 0]
        let direction = (Int(((angle + offsets[index]) / (.pi / 4)).rounded()) % 4 + 4) % 4
        let positions: [NSCursor.FrameResizePosition] = [.right, .bottomRight, .bottom, .topRight]
        return .frameResize(position: positions[direction], directions: [.inward, .outward])
    }
}

/// Separate overlay so selecting a layer does not redraw image pixels.
final class TransformOverlay: NSView {
    let session: EditorSession
    init(session: EditorSession) {
        self.session = session
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var geometry: TransformOverlayGeometry? {
        guard session.tool == .move, session.showsTransformControls || session.transformEdit?.persistent == true,
              let document = session.document else { return nil }
        // Several layers selected, or a folder: one box around them all.
        if session.transformEdit?.group != nil || (session.transformEdit == nil && session.transformsAsGroup) {
            if let corners = session.transformEdit?.corners {
                return TransformOverlayGeometry(corners: corners, viewport: session.viewport, documentSize: document.size)
            }
            guard let box = session.transformEdit?.draft ?? session.groupTransformBox else { return nil }
            return TransformOverlayGeometry(transform: box, viewport: session.viewport, documentSize: document.size)
        }
        guard let layer = session.activeLayer, layer.asset != nil, !layer.isGroup, document.effectiveVisibleIDs.contains(layer.id) else { return nil }
        if let edit = session.transformEdit, edit.layerID == layer.id, let corners = edit.corners {
            return TransformOverlayGeometry(corners: corners, viewport: session.viewport, documentSize: document.size)
        }
        return TransformOverlayGeometry(transform: session.editedTransform(for: layer),
                                        viewport: session.viewport, documentSize: document.size)
    }

    /// Pending gradient endpoints in view coordinates.
    var gradientLine: (start: CGPoint, end: CGPoint)? {
        guard let edit = session.gradientEdit, edit.hasLine, let document = session.document else { return nil }
        return (session.viewport.viewPoint(from: edit.start, documentSize: document.size),
                session.viewport.viewPoint(from: edit.end, documentSize: document.size))
    }

    /// Progressive Blur's line in view coordinates while its panel is open, and whether it's radial.
    var progressiveLine: (start: CGPoint, end: CGPoint, radial: Bool)? {
        guard let edit = session.filterEdit, edit.kind == .progressiveBlur, let start = edit.settings.progressiveStart,
              let end = edit.settings.progressiveEnd, let document = session.document else { return nil }
        return (session.viewport.viewPoint(from: start, documentSize: document.size),
                session.viewport.viewPoint(from: end, documentSize: document.size), edit.settings.progressiveRadial)
    }

    /// RGB Split's center in view coordinates while its panel is open on Radial.
    var rgbSplitCenter: CGPoint? {
        guard let edit = session.filterEdit, edit.kind == .rgbSplit, edit.settings.rgbSplitRadial,
              let center = edit.settings.rgbSplitCenter, let document = session.document else { return nil }
        return session.viewport.viewPoint(from: center, documentSize: document.size)
    }

    /// Volumetric Light's light in view coordinates while its panel is open.
    var volumetricLight: CGPoint? {
        guard let edit = session.filterEdit, edit.kind == .volumetricLight,
              let center = edit.settings.volumetric.center, let document = session.document else { return nil }
        return session.viewport.viewPoint(from: center, documentSize: document.size)
    }

    /// A crosshair in a ring, where the split spreads out from, or where Volumetric Light's light is.
    private func drawRGBSplitCenter(_ center: CGPoint) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        for (width, color) in [(3.0, NSColor.black.withAlphaComponent(0.7)), (1.0, NSColor.white)] {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.strokeEllipse(in: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
            context.move(to: CGPoint(x: center.x - 12, y: center.y)); context.addLine(to: CGPoint(x: center.x - 4, y: center.y))
            context.move(to: CGPoint(x: center.x + 4, y: center.y)); context.addLine(to: CGPoint(x: center.x + 12, y: center.y))
            context.move(to: CGPoint(x: center.x, y: center.y - 12)); context.addLine(to: CGPoint(x: center.x, y: center.y - 4))
            context.move(to: CGPoint(x: center.x, y: center.y + 4)); context.addLine(to: CGPoint(x: center.x, y: center.y + 12))
            context.strokePath()
        }
        context.restoreGState()
    }

    var antsPhase: CGFloat = 0

    // MARK: Marching ants level of detail
    //
    // A Magic Wand outline on detailed artwork can have hundreds of thousands of edges, one per pixel step. Stroked in
    // full every tick, zoomed out they pile into a few screen pixels and one redraw can take seconds, which froze the
    // app. Below 1:1 a complex outline is drawn from one traced at screen resolution instead: built in the background,
    // cached per power-of-two zoom step, so it never has more edges than the screen has pixels to show.

    /// Outlines at or under this many path elements are always drawn in full; marquees and lassos stay exact.
    private static let fullDetailLimit = 20_000
    private var antsSource: CGPath?
    private var antsSourceIsComplex = false
    /// The screen-resolution outline in document coordinates, and the zoom step it was traced for.
    private var antsLevel: (path: CGPath, step: CGFloat)?
    private var antsPendingStep: CGFloat?
    private var antsTask: Task<Void, Never>?

    /// What the ants stroke: the selection itself, or when zoomed out on a complex one, its screen-resolution outline.
    /// Nil while the first simplified outline is still being traced.
    private func antsOutline(for path: CGPath) -> CGPath? {
        if antsSource !== path {
            antsSource = path
            antsTask?.cancel()
            antsTask = nil
            antsLevel = nil
            antsPendingStep = nil
            var elements = 0
            path.applyWithBlock { _ in elements += 1 }
            antsSourceIsComplex = elements > Self.fullDetailLimit
        }
        let scale = session.viewport.pointsPerPixel * (window?.backingScaleFactor ?? 2)
        guard antsSourceIsComplex, scale < 1, let document = session.document else { return path }
        // Screen pixels per document pixel, rounded up to a power of two so zooming doesn't retrace on every frame.
        let step = min(1, pow(2, ceil(log2(max(scale, 1 / 4096)))))
        if antsLevel?.step != step, antsPendingStep != step {
            antsPendingStep = step
            antsTask?.cancel()
            let canvas = CGRect(origin: .zero, size: document.size)
            antsTask = Task { [weak self] in
                let traced = await Task.detached(priority: .userInitiated) { Self.traceOutline(path, canvas: canvas, step: step) }.value
                guard let self, !Task.isCancelled, self.antsSource === path, self.antsPendingStep == step else { return }
                self.antsPendingStep = nil
                if let traced { self.antsLevel = (traced, step) }
                self.needsDisplay = true
            }
        }
        // Until the new step is traced, the last one stands in: a little coarse or fine for a moment, never slow.
        return antsLevel?.path
    }

    /// `path` filled into a mask fine enough to fill quickly, averaged down to `step` screen pixels per document pixel,
    /// and traced along those pixels' edges. Any coverage counts, so thin parts stay outlined rather than vanishing.
    private nonisolated static func traceOutline(_ path: CGPath, canvas: CGRect, step: CGFloat) -> CGPath? {
        let region = path.boundingBoxOfPath.intersection(canvas).integral
        guard !region.isNull, region.width >= 1, region.height >= 1 else { return nil }
        // Filling costs about as much as the edges each output pixel has to sort through, so the mask is filled at no
        // less than half resolution and at most about 40 megapixels.
        let fill = min(1, max(step, (40_000_000 / (region.width * region.height)).squareRoot()))
        func mask(_ width: Int, _ height: Int) -> CGContext? {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        }
        let fillWidth = max(1, Int((region.width * fill).rounded(.up))), fillHeight = max(1, Int((region.height * fill).rounded(.up)))
        guard let filled = mask(fillWidth, fillHeight) else { return nil }
        // Top-left origin, so a mask row is a document row, as the tracer expects.
        filled.translateBy(x: 0, y: CGFloat(fillHeight))
        filled.scaleBy(x: fill, y: -fill)
        filled.translateBy(x: -region.minX, y: -region.minY)
        filled.addPath(path)
        filled.setFillColor(gray: 1, alpha: 1)
        filled.fillPath(using: .winding)
        guard let image = filled.makeImage() else { return nil }
        let width = max(1, Int((region.width * step).rounded(.up))), height = max(1, Int((region.height * step).rounded(.up)))
        guard let small = mask(width, height) else { return nil }
        small.interpolationQuality = .medium
        small.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = small.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let line = bytes + row * small.bytesPerRow
            for column in 0..<width where line[column] > 0 { pixels[row * width + column] = 255 }
        }
        guard let traced = try? MagicWand.outline(of: pixels, width: width, height: height) else { return nil }
        var toDocument = CGAffineTransform(translationX: region.minX, y: region.minY).scaledBy(x: 1 / step, y: 1 / step)
        return traced.copy(using: &toDocument)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawLayoutGrid()
        drawGuides()
        if let line = progressiveLine { drawProgressiveLine(line) }
        if let center = rgbSplitCenter ?? volumetricLight { drawRGBSplitCenter(center) }
        else if session.tool == .crop { drawCrop() }
        else if let warp = session.meshWarpEdit { drawMeshWarp(warp) }
        else if let line = gradientLine { drawGradientLine(line) }
        else { drawTransformHandles() }
        drawSelection()
        drawQuickMask()
        drawLassoDraft()
        drawVectorPaths()
        drawSnapGuides()
        drawDistances()
        drawDragOutSize()
    }

    /// Draws the translucent ruby Quick Mask (`Q`) overlay over masked/unselected document pixels.
    private func drawQuickMask() {
        guard let overlay = session.quickMask?.overlayImage, let document = session.document,
              let docToView = documentToView, let context = NSGraphicsContext.current?.cgContext else { return }
        let dest = CGRect(origin: .zero, size: document.size).applying(docToView)
        context.saveGState()
        // CGContext.draw expects bottom-up y, whereas TransformOverlay is flipped top-down.
        context.translateBy(x: dest.minX, y: dest.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(overlay, in: CGRect(origin: .zero, size: dest.size))
        context.restoreGState()
    }

    /// Draws active/visible Bézier vector paths, anchors, and control handles in native screen resolution.
    private func drawVectorPaths() {
        guard let document = session.document, let transform = documentToView,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let showAll = session.tool == .pen || session.rightPanelTab == .paths
        let pathsToDraw = document.paths.filter { path in
            guard path.isVisible, !path.isEmpty else { return false }
            return showAll || path.id == session.activePathID
        }
        guard !pathsToDraw.isEmpty else { return }
        context.saveGState()
        for path in pathsToDraw {
            let isActive = path.id == session.activePathID
            let cg = path.cgPath(transform: transform)
            // Subtle dark halo behind the path curve for contrast on light canvases.
            context.setStrokeColor(NSColor.black.withAlphaComponent(isActive ? 0.35 : 0.2).cgColor)
            context.setLineWidth(isActive ? 2.5 : 1.5)
            context.addPath(cg)
            context.strokePath()
            // Crisp cyan-blue vector path curve.
            let accent = isActive ? NSColor.systemBlue : NSColor.systemBlue.withAlphaComponent(0.55)
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(isActive ? 1.5 : 1.0)
            context.addPath(cg)
            context.strokePath()

            guard isActive, (session.tool == .pen || session.rightPanelTab == .paths) else { continue }
            for (sIdx, sub) in path.subpaths.enumerated() {
                for (aIdx, anchor) in sub.anchors.enumerated() {
                    let pt = anchor.point.applying(transform)
                    let ref = PathAnchorRef(pathID: path.id, subpathIndex: sIdx, anchorIndex: aIdx)
                    let isSelected = session.selectedAnchor == ref

                    // Draw tangent handles for selected anchor (or any anchor with handles while in Pen tool).
                    if isSelected || session.tool == .pen {
                        for handle in [anchor.handleIn, anchor.handleOut].compactMap({ $0 }) {
                            let hp = handle.applying(transform)
                            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.75).cgColor)
                            context.setLineWidth(1)
                            context.move(to: pt)
                            context.addLine(to: hp)
                            context.strokePath()
                            let knob = CGRect(x: hp.x - 3, y: hp.y - 3, width: 6, height: 6)
                            context.setFillColor(isSelected ? NSColor.systemBlue.cgColor : NSColor.white.cgColor)
                            context.setStrokeColor(NSColor.systemBlue.cgColor)
                            context.fillEllipse(in: knob)
                            context.strokeEllipse(in: knob)
                        }
                    }

                    // Anchor square.
                    let box = CGRect(x: pt.x - 3.5, y: pt.y - 3.5, width: 7, height: 7)
                    context.setFillColor(isSelected ? NSColor.systemBlue.cgColor : NSColor.white.cgColor)
                    context.setStrokeColor(NSColor.systemBlue.cgColor)
                    context.setLineWidth(1.2)
                    context.fill(box)
                    context.stroke(box)
                }
            }
        }
        context.restoreGState()
    }

    /// A Marquee's or shape's size, a line's length, or a resized layer's size, as it's dragged: in a dark label just
    /// above and right of the point being dragged, the other side of it near the view's edge.
    private func drawDragOutSize() {
        guard let size = session.dragOutSize, let transform = documentToView else { return }
        let corner = size.corner.applying(transform)
        let text = NSAttributedString(string: size.text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white,
        ])
        let textSize = text.size()
        var label = CGRect(x: corner.x + 14, y: corner.y - 14 - (textSize.height + 6), width: textSize.width + 12, height: textSize.height + 6)
        if label.maxX > bounds.maxX - 4 { label.origin.x = corner.x - 14 - label.width }
        if label.minY < bounds.minY + 4 { label.origin.y = corner.y + 14 }
        NSColor(white: 0.12, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: label, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: label.minX + 6, y: label.minY + 3))
    }

    /// The Move tool's pixel gaps: a line with an end bar at each side, and its length in a label on it, the same
    /// size at any zoom.
    private func drawDistances() {
        let lines = session.distanceLines
        guard !lines.isEmpty, let transform = documentToView, let context = NSGraphicsContext.current?.cgContext else { return }
        let color = NSColor.systemPink
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1)
        for line in lines {
            let start = (line.horizontal ? CGPoint(x: line.from, y: line.across) : CGPoint(x: line.across, y: line.from)).applying(transform)
            let end = (line.horizontal ? CGPoint(x: line.to, y: line.across) : CGPoint(x: line.across, y: line.to)).applying(transform)
            context.move(to: start)
            context.addLine(to: end)
            for point in [start, end] {
                context.move(to: line.horizontal ? CGPoint(x: point.x, y: point.y - 4) : CGPoint(x: point.x - 4, y: point.y))
                context.addLine(to: line.horizontal ? CGPoint(x: point.x, y: point.y + 4) : CGPoint(x: point.x + 4, y: point.y))
            }
        }
        context.strokePath()
        context.restoreGState()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white,
        ]
        for line in lines {
            let start = (line.horizontal ? CGPoint(x: line.from, y: line.across) : CGPoint(x: line.across, y: line.from)).applying(transform)
            let end = (line.horizontal ? CGPoint(x: line.to, y: line.across) : CGPoint(x: line.across, y: line.to)).applying(transform)
            let text = NSAttributedString(string: "\(Int(line.length.rounded())) px", attributes: attributes)
            let size = text.size()
            let label = CGRect(x: (start.x + end.x) / 2 - size.width / 2 - 5, y: (start.y + end.y) / 2 - size.height / 2 - 2,
                               width: size.width + 10, height: size.height + 4)
            color.setFill()
            NSBezierPath(roundedRect: label, xRadius: 4, yRadius: 4).fill()
            text.draw(at: CGPoint(x: label.minX + 5, y: label.minY + 2))
        }
    }

    /// Non-printing layout grid over the document: majors in the chosen style, dotted subdivisions, both in the
    /// chosen color.
    private func drawLayoutGrid() {
        guard session.showsGrid, let document = session.document, let transform = documentToView,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let grid = session.layoutGrid
        let appearance = session.gridAppearance
        let color = appearance.color.nsColor
        let size = document.size
        let scale = session.viewport.pointsPerPixel
        let hairline = 1 / max(session.viewport.backingScale, 1)
        let subdivisionGap = grid.step * scale
        context.saveGState()
        context.concatenate(transform)
        context.setLineWidth(hairline / max(scale, 0.0001))
        context.setStrokeColor(color.withAlphaComponent(appearance.subdivisionAlpha).cgColor)
        if subdivisionGap >= 4 {
            context.setLineDash(phase: 0, lengths: [1 / max(scale, 0.0001), 2 / max(scale, 0.0001)])
            let path = CGMutablePath()
            for x in grid.lines(along: size.width) where !grid.isMajor(x) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in grid.lines(along: size.height) where !grid.isMajor(y) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.addPath(path)
            context.strokePath()
        }
        context.setLineDash(phase: 0, lengths: appearance.style.dashes.map { $0 / max(scale, 0.0001) })
        context.setStrokeColor(color.withAlphaComponent(appearance.majorAlpha).cgColor)
        let majors = CGMutablePath()
        for x in grid.lines(along: size.width) where grid.isMajor(x) {
            majors.move(to: CGPoint(x: x, y: 0))
            majors.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in grid.lines(along: size.height) where grid.isMajor(y) {
            majors.move(to: CGPoint(x: 0, y: y))
            majors.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.addPath(majors)
        context.strokePath()
        context.restoreGState()
    }

    /// User guides span the whole view, including the pasteboard.
    private func drawGuides() {
        guard session.showsGuides, let document = session.document,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let guides = session.displayedGuides
        guard !guides.isEmpty else { return }
        context.saveGState()
        context.setStrokeColor(EditorSession.guideColor)
        context.setLineWidth(1 / max(session.viewport.backingScale, 1))
        for guide in guides {
            if guide.axis == .vertical {
                let x = session.viewport.viewPoint(from: CGPoint(x: guide.position, y: 0), documentSize: document.size).x
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: bounds.height))
            } else {
                let y = session.viewport.viewPoint(from: CGPoint(x: 0, y: guide.position), documentSize: document.size).y
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: bounds.width, y: y))
            }
        }
        context.strokePath()
        context.restoreGState()
    }

    /// While a move is snapped, a line along what it lined up with, across the whole canvas.
    private func drawSnapGuides() {
        let guides = session.snapGuides
        guard !guides.xs.isEmpty || !guides.ys.isEmpty, let document = session.document,
              let transform = documentToView, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1)
        for x in guides.xs {
            context.move(to: CGPoint(x: x, y: 0).applying(transform))
            context.addLine(to: CGPoint(x: x, y: document.size.height).applying(transform))
        }
        for y in guides.ys {
            context.move(to: CGPoint(x: 0, y: y).applying(transform))
            context.addLine(to: CGPoint(x: document.size.width, y: y).applying(transform))
        }
        context.strokePath()
        context.restoreGState()
    }

    private var documentToView: CGAffineTransform? {
        guard let document = session.document else { return nil }
        let origin = session.viewport.documentRect(document.size).origin
        let scale = session.viewport.pointsPerPixel
        return CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)
    }

    /// Marching ants: a white line under an animated black dash.
    private func drawSelection() {
        guard session.showsSelectionEdges, let selection = session.displayedSelection, !selection.isEmpty, var transform = documentToView,
              let outline = antsOutline(for: selection.path),
              let path = outline.copy(using: &transform), let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setLineWidth(1)
        context.addPath(path)
        context.setStrokeColor(NSColor.white.cgColor)
        context.strokePath()
        context.addPath(path)
        context.setLineDash(phase: antsPhase, lengths: [4, 4])
        context.setStrokeColor(NSColor.black.cgColor)
        context.strokePath()
        context.restoreGState()
    }


    private func drawLassoDraft() {
        guard let draft = session.lassoDraft, let transform = documentToView,
              let context = NSGraphicsContext.current?.cgContext else { return }
        var points = draft.points.map { $0.applying(transform) }
        if draft.kind == .polygonal, let cursor = draft.cursor { points.append(cursor.applying(transform)) }
        guard let first = points.first else { return }
        context.saveGState()
        let path = CGMutablePath()
        if draft.kind == .ellipse, points.count == 4 {
            let xs = points.map(\.x), ys = points.map(\.y)
            path.addEllipse(in: CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!))
        } else {
            path.addLines(between: points)
            if draft.kind == .rectangle { path.closeSubpath() }
        }
        context.addPath(path)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(2)
        context.strokePath()
        context.addPath(path)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.strokePath()
        if draft.kind == .polygonal {
            // The first corner: click it to close the outline.
            let handle = CGRect(x: first.x - 4, y: first.y - 4, width: 8, height: 8)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(handle)
            context.setStrokeColor(NSColor.black.cgColor)
            context.stroke(handle)
        }
        context.restoreGState()
    }

    /// Draws the 3×3 bicubic Bézier Mesh Warp wireframe and its 16 draggable control points.
    private func drawMeshWarp(_ edit: MeshWarpEdit) {
        guard let docToView = documentToView, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        let mesh = edit.mesh

        // Draw curved isoparametric lines at u, v ∈ {0, 1/3, 2/3, 1}.
        let stops: [CGFloat] = [0, 1.0 / 3.0, 2.0 / 3.0, 1]
        let steps = 24
        context.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1.2)
        for s in stops {
            // Horizontal curve (v = s)
            for i in 0...steps {
                let p = mesh.evaluate(u: CGFloat(i) / CGFloat(steps), v: s).applying(docToView)
                if i == 0 { context.move(to: p) } else { context.addLine(to: p) }
            }
            // Vertical curve (u = s)
            for j in 0...steps {
                let p = mesh.evaluate(u: s, v: CGFloat(j) / CGFloat(steps)).applying(docToView)
                if j == 0 { context.move(to: p) } else { context.addLine(to: p) }
            }
        }
        context.strokePath()

        // Draw the 16 control handles (corners as squares, interior/edge handles as circles).
        for (idx, pt) in mesh.points.enumerated() {
            let vp = pt.applying(docToView)
            let isCorner = idx == 0 || idx == 3 || idx == 12 || idx == 15
            let r: CGFloat = isCorner ? 5 : 4
            let rect = CGRect(x: vp.x - r, y: vp.y - r, width: r * 2, height: r * 2)
            context.setFillColor(isCorner ? NSColor.white.cgColor : NSColor.systemBlue.cgColor)
            context.setStrokeColor(isCorner ? NSColor.black.cgColor : NSColor.white.cgColor)
            context.setLineWidth(1.2)
            if isCorner {
                context.fill(rect); context.stroke(rect)
            } else {
                context.fillEllipse(in: rect); context.strokeEllipse(in: rect)
            }
        }
        context.restoreGState()
    }

    private func drawTransformHandles() {
        guard let geometry, let context = NSGraphicsContext.current?.cgContext else { return }
        // Draw custom reference point (pivot) crosshair when non-center or during persistent transform.
        if let docToView = documentToView,
           let layer = session.activeLayer,
           (session.transformPivot != CGPoint(x: 0.5, y: 0.5) || session.transformEdit?.persistent == true) {
            let t = session.transformEdit?.draft ?? session.editedTransform(for: layer)
            let pivotView = t.point(session.transformPivot).applying(docToView)
            context.saveGState()
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1.2)
            context.strokeEllipse(in: CGRect(x: pivotView.x - 5, y: pivotView.y - 5, width: 10, height: 10))
            context.move(to: CGPoint(x: pivotView.x - 8, y: pivotView.y))
            context.addLine(to: CGPoint(x: pivotView.x + 8, y: pivotView.y))
            context.move(to: CGPoint(x: pivotView.x, y: pivotView.y - 8))
            context.addLine(to: CGPoint(x: pivotView.x, y: pivotView.y + 8))
            context.strokePath()
            context.restoreGState()
        }
        let path = CGMutablePath()
        path.move(to: geometry.handles[0])
        for index in [2, 4, 6] { path.addLine(to: geometry.handles[index]) }
        path.closeSubpath()
        // Just the accent line: a dark line behind it read as a grey halo around the box.
        context.addPath(path)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        for point in geometry.handles {
            let rect = CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)
            context.fill(rect)
            context.stroke(rect)
        }
    }

    var cropViewRect: CGRect? {
        guard let rect = session.visibleCropRect, let document = session.document else { return nil }
        return CGRect(origin: session.viewport.viewPoint(from: rect.origin, documentSize: document.size),
                      size: CGSize(width: rect.width * session.viewport.pointsPerPixel,
                                   height: rect.height * session.viewport.pointsPerPixel))
    }
    var cropHandles: [CGPoint] {
        guard let rect = cropViewRect else { return [] }
        return LayerTransform.handles.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
    }
    var cropResizeRegions: [(index: Int, rect: CGRect)] {
        guard let rect = cropViewRect else { return [] }
        let handles = cropHandles
        let radius: CGFloat = 10
        var regions = [0, 2, 4, 6].map { index in
            (index: index, rect: CGRect(x: handles[index].x - radius, y: handles[index].y - radius,
                                        width: radius * 2, height: radius * 2))
        }
        // Entire edges are draggable, not just the small midpoint squares.
        for index in [1, 5] {
            regions.append((index, CGRect(x: rect.minX + radius, y: handles[index].y - radius,
                width: max(0, rect.width - radius * 2), height: radius * 2)))
        }
        for index in [3, 7] {
            regions.append((index, CGRect(x: handles[index].x - radius, y: rect.minY + radius,
                width: radius * 2, height: max(0, rect.height - radius * 2))))
        }
        return regions
    }
    /// Progressive Blur's line: a solid handle where it's sharp, a hollow one where it's fully blurred, and for a radial
    /// one the circle it reaches full blur at.
    private func drawProgressiveLine(_ line: (start: CGPoint, end: CGPoint, radial: Bool)) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        if line.radial {
            let radius = hypot(line.end.x - line.start.x, line.end.y - line.start.y)
            let rim = CGRect(x: line.start.x - radius, y: line.start.y - radius, width: radius * 2, height: radius * 2)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: rim)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: rim)
            context.setLineDash(phase: 0, lengths: [])
        }
        for (width, color) in [(3.0, NSColor.black.withAlphaComponent(0.7)), (1.0, NSColor.white)] {
            context.move(to: line.start)
            context.addLine(to: line.end)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.strokePath()
        }
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1)
        // Sharp: a solid handle.
        let sharp = CGRect(x: line.start.x - 6, y: line.start.y - 6, width: 12, height: 12)
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: sharp)
        context.strokeEllipse(in: sharp)
        // Blurred: a ring, soft gray inside.
        let blurred = CGRect(x: line.end.x - 6, y: line.end.y - 6, width: 12, height: 12)
        context.setFillColor(NSColor(white: 0.6, alpha: 0.9).cgColor)
        context.fillEllipse(in: blurred)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: blurred.insetBy(dx: 1, dy: 1))
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: blurred)
        context.restoreGState()
    }

    private func drawGradientLine(_ line: (start: CGPoint, end: CGPoint)) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        if session.gradientSettings.shape == .radial {
            // Faint rim where the radial gradient reaches its end color.
            let radius = hypot(line.end.x - line.start.x, line.end.y - line.start.y)
            let rim = CGRect(x: line.start.x - radius, y: line.start.y - radius, width: radius * 2, height: radius * 2)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: rim)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: rim)
            context.setLineDash(phase: 0, lengths: [])
        }
        context.move(to: line.start)
        context.addLine(to: line.end)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(3)
        context.strokePath()
        context.move(to: line.start)
        context.addLine(to: line.end)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1)
        for (point, color) in [(line.start, session.gradientColors(mask: false).first), (line.end, session.gradientColors(mask: false).last)] {
            let rect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: rect)
            context.strokeEllipse(in: rect)
            // Checkerboard shows through transparent ends.
            let inner = rect.insetBy(dx: 2.5, dy: 2.5)
            context.setFillColor(NSColor(white: 0.75, alpha: 1).cgColor)
            context.fillEllipse(in: inner)
            if let color { context.setFillColor(color); context.fillEllipse(in: inner) }
        }
        context.restoreGState()
    }

    private func drawCrop() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Perspective Crop mode: 4-corner draggable quad with 3×3 perspective grid.
        if session.cropPerspectiveMode, let quad = session.perspectiveCropQuad, quad.corners.count == 4,
           let docToView = documentToView {
            let pts = quad.corners.map { $0.applying(docToView) }
            context.saveGState()
            let outer = CGMutablePath()
            outer.addRect(bounds)
            let quadPath = CGMutablePath()
            quadPath.addLines(between: pts)
            quadPath.closeSubpath()
            outer.addPath(quadPath)
            context.addPath(outer)
            context.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
            context.drawPath(using: .eoFill)

            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.2)
            context.addPath(quadPath)
            context.strokePath()

            // 3x3 perspective-interpolated composition mesh inside the quad.
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(1)
            func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
                CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            for step in 1...2 {
                let t = CGFloat(step) / 3
                context.move(to: lerp(pts[0], pts[1], t))
                context.addLine(to: lerp(pts[3], pts[2], t))
                context.move(to: lerp(pts[0], pts[3], t))
                context.addLine(to: lerp(pts[1], pts[2], t))
            }
            context.strokePath()

            context.setFillColor(NSColor.white.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)
            for pt in pts {
                let handle = CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)
                context.fill(handle)
                context.stroke(handle)
            }
            context.restoreGState()
            return
        }

        guard let rect = cropViewRect else { return }
        context.saveGState()

        let angleRad = CGFloat(session.cropAngle * .pi / 180.0)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var rotPath: CGPath = CGPath(rect: rect, transform: nil)
        if abs(angleRad) > 0.0001 {
            var t = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angleRad)
                .translatedBy(x: -center.x, y: -center.y)
            rotPath = CGPath(rect: rect, transform: &t)
        }

        context.addRect(bounds)
        context.addPath(rotPath)
        context.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        context.drawPath(using: .eoFill)

        if abs(angleRad) > 0.0001 {
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: angleRad)
            context.translateBy(x: -center.x, y: -center.y)
        }

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.stroke(rect)

        // Composition overlay guides.
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.45).cgColor)
        switch session.cropOverlayStyle {
        case .ruleOfThirds:
            for index in 1...2 {
                let f = CGFloat(index) / 3
                context.move(to: CGPoint(x: rect.minX + rect.width * f, y: rect.minY))
                context.addLine(to: CGPoint(x: rect.minX + rect.width * f, y: rect.maxY))
                context.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * f))
                context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * f))
            }
        case .goldenRatio:
            let ratios: [CGFloat] = [0.381966, 0.618034]
            for f in ratios {
                context.move(to: CGPoint(x: rect.minX + rect.width * f, y: rect.minY))
                context.addLine(to: CGPoint(x: rect.minX + rect.width * f, y: rect.maxY))
                context.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * f))
                context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * f))
            }
        case .diagonal:
            let short = min(rect.width, rect.height)
            context.move(to: CGPoint(x: rect.minX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.minX + short, y: rect.minY + short))
            context.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.maxX - short, y: rect.minY + short))
            context.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            context.addLine(to: CGPoint(x: rect.minX + short, y: rect.maxY - short))
            context.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            context.addLine(to: CGPoint(x: rect.maxX - short, y: rect.maxY - short))
        case .grid:
            for index in 1...5 {
                let f = CGFloat(index) / 6
                context.move(to: CGPoint(x: rect.minX + rect.width * f, y: rect.minY))
                context.addLine(to: CGPoint(x: rect.minX + rect.width * f, y: rect.maxY))
                context.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * f))
                context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * f))
            }
        case .none:
            break
        }
        context.strokePath()

        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.black.cgColor)
        for point in cropHandles {
            let handle = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            context.fill(handle)
            context.stroke(handle)
        }
        context.restoreGState()

        // Interactive Straighten horizon line.
        if let line = session.cropStraightenLine, let docToView = documentToView {
            let a = line.start.applying(docToView), b = line.end.applying(docToView)
            context.saveGState()
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(3)
            context.move(to: a); context.addLine(to: b); context.strokePath()
            context.setStrokeColor(NSColor.systemYellow.cgColor)
            context.setLineWidth(1.5)
            context.move(to: a); context.addLine(to: b); context.strokePath()
            context.restoreGState()
        }
    }
}
