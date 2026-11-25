import SwiftUI

struct PenControls: View {
    @Bindable var session: EditorSession

    private var hasActivePath: Bool { session.activePath?.isEmpty == false }

    var body: some View {
        HStack(spacing: 12) {
            Text("Pen").font(ToolHeaderStyle.titleFont)
            Picker("Mode", selection: $session.penMode) {
                ForEach(PenToolMode.allCases, id: \.self) { mode in
                    Text(L10n.text(mode.rawValue)).tag(mode)
                }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("Tab cycles Pen, Direct Select, Delete Anchor, and Convert Point")

            Button("Selection") { session.pathToSelection() }
                .disabled(!hasActivePath)
                .help("Convert active path to a marching-ants selection")

            Button("Fill") { session.fillPath() }
                .disabled(!hasActivePath || !session.canEditLayers)
                .help("Fill active path with the foreground color on a new layer")

            HStack(spacing: 6) {
                Button("Stroke") { session.strokePath() }
                    .disabled(!hasActivePath || !session.canEditLayers)
                    .help("Stroke active path with the foreground color on a new layer")
                TextField("Width", value: $session.penStrokeWidth, format: .number.precision(.fractionLength(0)))
                    .frame(width: 40).textFieldStyle(.roundedBorder)
                    .help("Path stroke width in pixels")
            }

            Button("Close") { session.closeActiveSubpath() }
                .disabled(!hasActivePath)
                .help("Close the current subpath (Return)")

            Button("New Path") { _ = session.addNewPath() }
                .disabled(session.document == nil)
                .help("Start a new vector path")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).toolHeaderBar().releasesFocusOnCommit(session)
        .disabled(session.showsBusy || session.document == nil)
    }
}
