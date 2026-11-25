import SwiftUI

struct HistoryPanel: View {
    @Bindable var session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Snapshots section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Snapshots").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        _ = session.createHistorySnapshot()
                    } label: {
                        Image(systemName: "camera.aperture")
                    }
                    .buttonStyle(.plain)
                    .help("Create a new snapshot of the current document state")
                    .disabled(session.document == nil)
                }
                .padding(.horizontal, 12).padding(.top, 8)

                if session.historySnapshots.isEmpty {
                    Text("No snapshots yet")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal, 12).padding(.bottom, 6)
                } else {
                    ForEach(session.historySnapshots) { snap in
                        HStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle").font(.caption).foregroundStyle(.secondary)
                            Text(snap.name).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Button { session.deleteHistorySnapshot(snap.id) } label: {
                                Image(systemName: "xmark.circle").font(.caption).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { session.restoreHistorySnapshot(snap.id) }
                    }
                }
            }
            Divider()

            // History states list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    let current = session.history.currentStepIndex
                    historyRow(title: L10n.text("Initial State"), step: 0, isCurrent: current == 0, isFuture: false)

                    ForEach(Array(session.history.pastNames.enumerated()), id: \.offset) { idx, name in
                        let step = idx + 1
                        historyRow(title: L10n.text(name), step: step, isCurrent: current == step, isFuture: false)
                    }

                    ForEach(Array(session.history.futureNames.enumerated()), id: \.offset) { idx, name in
                        let step = current + idx + 1
                        historyRow(title: L10n.text(name), step: step, isCurrent: false, isFuture: true)
                    }
                }
                .padding(6)
            }

            Divider()
            HStack {
                Button("New Snapshot") { _ = session.createHistorySnapshot() }
                    .controlSize(.small)
                    .disabled(session.document == nil)
                Spacer()
                Text(L10n.format("%lld states", session.history.totalSteps + 1))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(width: 260, height: 340)
    }

    private func historyRow(title: String, step: Int, isCurrent: Bool, isFuture: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isCurrent ? "arrowtriangle.right.fill" : "clock")
                .font(.system(size: 10))
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isFuture ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(isCurrent ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { session.jumpToHistoryStep(step) }
    }
}
