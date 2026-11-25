import SwiftUI

/// Photoshop-style lock toggle strip in the Layers panel header.
struct LayerLockControls: View {
    @Bindable var session: EditorSession

    private var activeLock: LayerLock { session.activeLayer?.lock ?? LayerLock() }
    private var inheritedLock: LayerLock {
        guard let id = session.activeLayerID else { return LayerLock() }
        return session.effectiveLock(for: id)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Lock").font(.caption)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(LayerLockKind.allCases, id: \.self) { kind in
                    let own = activeLock[kind]
                    let effective = inheritedLock[kind]
                    let active = own || (kind == .all && effective)
                    Button { session.toggleLayerLock(kind) } label: {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 24, height: 22)
                            .background(active ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 5))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(active ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
                            }
                            .foregroundStyle(active ? Color.accentColor : .secondary)
                            .contentShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.canToggleLayerLock(kind))
                    .help(L10n.text(kind.rawValue))
                    .accessibilityLabel(L10n.text(kind.rawValue))
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
    }
}
