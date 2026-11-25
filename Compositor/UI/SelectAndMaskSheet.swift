import SwiftUI

struct SelectAndMaskSheet: View {
    @Bindable var session: EditorSession
    @State private var previewImage: CGImage?

    private var settings: Binding<SelectAndMaskSettings> {
        Binding(get: { session.selectAndMask?.settings ?? SelectAndMaskSettings() },
                set: { next in
                    session.selectAndMask?.settings = next
                    refreshPreview()
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Select and Mask").font(.headline)
                Spacer()
                Picker("View", selection: settings.viewMode) {
                    ForEach(SelectAndMaskViewMode.allCases, id: \.self) { mode in
                        Text(L10n.text(mode.rawValue)).tag(mode)
                    }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
            }

            // Live refined preview thumbnail.
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.14))
                if let img = previewImage {
                    Image(decorative: img, scale: 1)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            .frame(height: 170)

            sliderRow("Smooth", value: settings.smooth, range: 0...50, suffix: "px")
            sliderRow("Feather", value: settings.feather, range: 0...100, suffix: "px")
            sliderRow("Contrast", value: settings.contrast, range: 0...100, suffix: "%")
            sliderRow("Shift Edge", value: settings.shiftEdge, range: -100...100, suffix: "%")

            Divider()
            Toggle("Decontaminate Colors", isOn: settings.decontaminateColors)
                .toggleStyle(.checkbox)
            if settings.wrappedValue.decontaminateColors {
                sliderRow("Amount", value: settings.decontaminateAmount, range: 0...100, suffix: "%")
            }

            HStack {
                Text("Output To").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Output To", selection: settings.outputMode) {
                    ForEach(SelectAndMaskOutput.allCases, id: \.self) { out in
                        Text(L10n.text(out.rawValue)).tag(out)
                    }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
            }

            Divider()
            HStack {
                Button("Reset") {
                    session.selectAndMask?.settings = SelectAndMaskSettings()
                    refreshPreview()
                }
                Spacer()
                Button("Cancel") { session.cancelSelectAndMask() }.keyboardShortcut(.cancelAction)
                Button("Apply") { session.applySelectAndMask() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { refreshPreview() }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(L10n.text(title)).font(.caption)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded())) \(suffix)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func refreshPreview() {
        previewImage = session.selectAndMask?.previewImage()
    }
}
