import SwiftUI

struct PathsPanel: View {
    @Bindable var session: EditorSession

    private var paths: [VectorPath] { session.document?.paths ?? [] }
    private var hasActivePath: Bool { session.activePath?.isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if paths.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "pencil.tip.crop.circle").font(.system(size: 25, weight: .light))
                    Text("No paths yet").font(.callout.weight(.medium))
                    Text("Use the Pen tool (P) to draw Bézier paths, or convert a selection to a path.")
                        .font(.caption).multilineTextAlignment(.center)
                    if session.document != nil {
                        Button("New Path") { _ = session.addNewPath() }
                            .controlSize(.small)
                    }
                }
                .foregroundStyle(.secondary).padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(paths) { path in
                            pathRow(path)
                        }
                    }
                    .padding(.vertical, 6).padding(.horizontal, 8)
                }
            }
            Divider()
            pathsFooter
        }
    }

    private func pathRow(_ path: VectorPath) -> some View {
        let isSelected = session.activePathID == path.id
        return HStack(spacing: 8) {
            Button { session.togglePathVisibility(path.id) } label: {
                Image(systemName: path.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(path.isVisible ? .primary : .secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(L10n.text(path.isVisible ? "Hide path" : "Show path"))

            PathThumbnailView(path: path, canvasSize: session.document?.size ?? CGSize(width: 100, height: 100))
                .frame(width: 34, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(path.name).font(.system(size: 12, weight: isSelected ? .medium : .regular)).lineLimit(1)
                let count = path.subpaths.reduce(0) { $0 + $1.anchors.count }
                Text(L10n.format("%lld anchors", count))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { session.selectPath(path.id) }
        .contextMenu {
            Button("Make Selection") { session.pathToSelection(path.id) }.disabled(path.isEmpty)
            Button("Add as Vector Mask") { session.addVectorMask(from: path.id) }
                .disabled(path.isEmpty || session.activeLayer == nil || !session.canEditLayers)
            Button("Fill Path") { session.fillPath(path.id) }.disabled(path.isEmpty || !session.canEditLayers)
            Button("Stroke Path") { session.strokePath(path.id) }.disabled(path.isEmpty || !session.canEditLayers)
            if let activeID = session.activePathID, activeID != path.id, session.activePath?.isEmpty == false, !path.isEmpty {
                Menu("Combine with Active Path") {
                    ForEach(VectorBooleanOperation.allCases, id: \.self) { op in
                        Button(L10n.text(op.rawValue)) { _ = session.combinePaths(activeID, with: path.id, operation: op) }
                    }
                }
            }
            Divider()
            Button("Duplicate Path") { session.duplicatePath(path.id) }
            Button("Delete Path", role: .destructive) { session.deletePath(path.id) }
        }
    }

    private var pathsFooter: some View {
        HStack(spacing: 0) {
            Button { _ = session.addNewPath() } label: { FooterIcon(systemName: "plus.square") }
                .help("New Path").disabled(session.document == nil)
            Button { session.pathToSelection() } label: { FooterIcon(systemName: "circle.dashed") }
                .help("Make Selection from Path").disabled(!hasActivePath)
            Button { _ = session.selectionToPath() } label: { FooterIcon(systemName: "point.topleft.down.curvedto.point.bottomright.up") }
                .help("Make Path from Selection").disabled(session.selection?.isEmpty != false)
            Button { session.fillPath() } label: { FooterIcon(systemName: "drop.fill") }
                .help("Fill Path").disabled(!hasActivePath || !session.canEditLayers)
            Button { session.strokePath() } label: { FooterIcon(systemName: "scribble.variable") }
                .help("Stroke Path").disabled(!hasActivePath || !session.canEditLayers)
            Spacer(minLength: 0)
            Button {
                if let id = session.activePathID { session.deletePath(id) }
            } label: { FooterIcon(systemName: "trash") }
                .help("Delete Path").disabled(session.activePathID == nil)
        }
        .buttonStyle(.plain).padding(.horizontal, 8)
    }
}

private struct PathThumbnailView: View {
    let path: VectorPath
    let canvasSize: CGSize

    var body: some View {
        Canvas { context, size in
            let bg = RoundedRectangle(cornerRadius: 3).path(in: CGRect(origin: .zero, size: size))
            context.fill(bg, with: .color(Color(white: 0.18)))
            context.stroke(bg, with: .color(Color.white.opacity(0.15)), lineWidth: 0.75)
            guard !path.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return }
            let inset = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            let scale = min(inset.width / canvasSize.width, inset.height / canvasSize.height)
            let dx = inset.minX + (inset.width - canvasSize.width * scale) / 2
            let dy = inset.minY + (inset.height - canvasSize.height * scale) / 2
            let t = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
            let swiftPath = Path(path.cgPath(transform: t))
            context.stroke(swiftPath, with: .color(.white.opacity(0.85)), lineWidth: 1)
        }
    }
}
