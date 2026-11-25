import SwiftUI
import UniformTypeIdentifiers

struct BrushPresetControls: View {
    @Bindable var session: EditorSession
    @State private var showsLibrary = false
    @State private var showsDynamics = false
    @State private var showsImporter = false
    @State private var importInitiator: ObjectIdentifier?

    var body: some View {
        let library = session.brushLibrary
        let preset = library.presets.first { $0.id == session.selectedBrushPresetID }
        HStack(spacing: 6) {
            Button {
                showsDynamics = false
                showsLibrary.toggle()
            } label: {
                HStack(spacing: 6) {
                    if library.isImporting {
                        ProgressView().controlSize(.small).frame(width: 18, height: 18).accessibilityHidden(true)
                    } else if let preset {
                        BrushPresetThumbnail(preset: preset).frame(width: 18, height: 18)
                    }
                    Text(preset?.displayName ?? L10n.text("Brush Presets")).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .frame(maxWidth: 140)
            }
            .accessibilityLabel("Brush Presets")
            .accessibilityValue(library.isImporting ? L10n.text("Importing…") : preset?.displayName ?? "")
            .accessibilityIdentifier("brushPresets")
            .help("Brush Presets")
            .popover(isPresented: $showsLibrary, arrowEdge: .bottom) {
                BrushLibraryPopover(session: session, choose: { preset in
                    session.selectBrushPreset(preset)
                    showsLibrary = false
                }, chooseFiles: {
                    showsLibrary = false
                    showsImporter = true
                })
            }

            Button {
                showsLibrary = false
                showsDynamics.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Brush Settings")
            .accessibilityLabel("Brush Settings")
            .accessibilityIdentifier("brushDynamics")
            .popover(isPresented: $showsDynamics, arrowEdge: .bottom) {
                BrushDynamicsPopover(settings: $session.brushSettings)
            }
        }
        .buttonStyle(.bordered)
        .onChange(of: ObjectIdentifier(session)) { _, _ in
            showsLibrary = false
            showsDynamics = false
            importInitiator = nil
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [UTType(filenameExtension: "abr") ?? .data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                let initiator = ObjectIdentifier(session)
                importInitiator = initiator
                Task {
                    await library.importFiles(urls)
                    if importInitiator == initiator, library.importError == nil {
                        importInitiator = nil
                        if session.tool == .brush { showsLibrary = true }
                    }
                }
            case .failure(let error):
                let cocoaError = error as NSError
                if cocoaError.domain != NSCocoaErrorDomain || cocoaError.code != NSUserCancelledError {
                    importInitiator = ObjectIdentifier(session)
                    library.importError = error.localizedDescription
                }
            }
        }
        .alert("Brush Library", isPresented: Binding(
            get: { library.importError != nil && (showsLibrary || importInitiator == ObjectIdentifier(session)) },
            set: { if !$0 { library.importError = nil; importInitiator = nil } })) {
                Button("OK") { library.importError = nil; importInitiator = nil }
            } message: { Text(library.importError ?? "") }
    }
}

private struct BrushLibraryPopover: View {
    var session: EditorSession
    var choose: (BrushPreset) -> Void
    var chooseFiles: () -> Void
    @State private var query = ""
    @State private var isNamingPreset = false
    @State private var name = ""
    @FocusState private var editingName: Bool

    var body: some View {
        let library = session.brushLibrary
        let presets = library.presets.filter { query.isEmpty || $0.displayName.localizedStandardContains(query) }
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search Brushes", text: $query)
                .textFieldStyle(.roundedBorder)
            if presets.isEmpty {
                Text(query.isEmpty ? L10n.text("No brush presets") : L10n.text("No brushes match"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(presets) { preset in
                            presetRow(preset)
                        }
                    }
                }
                .frame(height: CGFloat(min(presets.count, 7)) * 34)
            }
            Divider()
            if isNamingPreset {
                HStack(spacing: 6) {
                    TextField("Preset Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($editingName)
                        .onAppear { editingName = true }
                        .onSubmit(savePreset)
                    Button("Cancel") { isNamingPreset = false }
                    Button("Save", action: savePreset).disabled(trimmedName.isEmpty)
                }
            } else {
                HStack {
                    Button("Import ABR…", action: chooseFiles).disabled(library.isImporting)
                    Spacer()
                    if library.isImporting {
                        ProgressView().controlSize(.small).accessibilityLabel("Importing…")
                    }
                    Button("Save Current Brush…") {
                        name = ""
                        isNamingPreset = true
                    }
                    .disabled(library.isImporting)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .roundedControls()
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func savePreset() {
        guard !trimmedName.isEmpty else { return }
        session.brushLibrary.savePreset(name: trimmedName, settings: session.brushSettings)
        isNamingPreset = false
    }

    private func presetRow(_ preset: BrushPreset) -> some View {
        let isSelected = session.selectedBrushPresetID == preset.id
        return Button { choose(preset) } label: {
            HStack(spacing: 8) {
                BrushPresetThumbnail(preset: preset).frame(width: 26, height: 26)
                Text(preset.displayName).lineLimit(1)
                Spacer(minLength: 4)
                if isSelected { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
            }
            .padding(.horizontal, 6)
            .frame(height: 32)
            .background(isSelected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            if !preset.isBuiltIn {
                Button("Remove Brush Preset", role: .destructive) { session.brushLibrary.removePreset(preset) }
                    .disabled(session.brushLibrary.isImporting)
            }
        }
    }
}

private struct BrushPresetThumbnail: View {
    let preset: BrushPreset

    var body: some View {
        Group {
            if let tip = preset.tip, let image = thumbnail(of: tip) {
                Rectangle().fill(.primary).mask {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                }
            } else if preset.hardness >= 1 {
                Circle().fill(.primary)
            } else {
                GeometryReader { geometry in
                    Circle().fill(RadialGradient(stops: [
                        .init(color: .primary, location: min(0.99, max(0, preset.hardness))),
                        .init(color: .primary.opacity(0), location: 1)
                    ], center: .center, startRadius: 0, endRadius: min(geometry.size.width, geometry.size.height) / 2))
                }
            }
        }
        .padding(2)
        .scaleEffect(x: 1, y: min(1, max(0.01, preset.roundness)))
        .rotationEffect(.degrees(-Double(preset.angle)))
        .accessibilityHidden(true)
    }

    private func thumbnail(of tip: BrushTip) -> CGImage? {
        guard let mask = tip.image else { return nil }
        let scale = min(1, 48 / Double(max(mask.width, mask.height)))
        let width = max(1, Int((Double(mask.width) * scale).rounded()))
        let height = max(1, Int((Double(mask.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.clip(to: frame, mask: mask)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(frame)
        return context.makeImage()
    }
}

private struct BrushDynamicsPopover: View {
    @Binding var settings: BrushSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("Automatic Spacing", isOn: Binding(
                get: { settings.spacing == nil },
                set: { settings.spacing = $0 ? nil : 0.25 }
            ))
            if settings.spacing != nil {
                valueRow("Spacing", value: Binding(get: { settings.spacing ?? 0.25 }, set: { settings.spacing = $0 }),
                         in: 0.01...10)
            }
            valueRow("Flow", value: $settings.flow, in: 0...1)
            valueRow("Angle", value: $settings.angle, in: -360...360, degrees: true)
            valueRow("Roundness", value: $settings.roundness, in: 0.01...1)
            Divider()
            DisclosureGroup("Brush Dynamics") {
                VStack(alignment: .leading, spacing: 9) {
                    valueRow("Size Jitter", value: $settings.sizeJitter, in: 0...1)
                    valueRow("Angle Jitter", value: $settings.angleJitter, in: 0...1)
                    valueRow("Opacity Jitter", value: $settings.opacityJitter, in: 0...1)
                    valueRow("Scatter", value: $settings.scatter, in: 0...10)
                    Stepper(value: $settings.scatterCount, in: 1...16) {
                        LabeledContent("Scatter Count") {
                            Text(settings.scatterCount, format: .number).monospacedDigit()
                        }
                    }
                    Toggle("Scatter on Both Axes", isOn: $settings.scatterBothAxes)
                }
                .padding(.vertical, 6)
            }
            Divider()
            Toggle("Pressure for size", isOn: $settings.pressureSize)
            Toggle("Pressure for opacity", isOn: $settings.pressureOpacity)
        }
        .padding(12)
        .frame(width: 348)
        .roundedControls()
    }

    private func valueRow(_ title: LocalizedStringKey, value: Binding<CGFloat>, in range: ClosedRange<CGFloat>,
                          degrees: Bool = false) -> some View {
        let scale: CGFloat = degrees ? 1 : 100
        let number = Binding<Double>(get: { Double(value.wrappedValue * scale) }, set: {
            guard $0.isFinite else { return }
            value.wrappedValue = min(range.upperBound, max(range.lowerBound, CGFloat($0) / scale))
        })
        let unit = degrees ? "°" : "%"
        return HStack(spacing: 8) {
            Text(title).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 0)
            AppSlider(value: value, in: range)
                .frame(minWidth: 70, idealWidth: 112, maxWidth: 112)
                .accessibilityLabel(title)
                .accessibilityValue(number.wrappedValue.formatted(.number.precision(.fractionLength(0))) + unit)
            TextField(title, value: number, format: .number.precision(.fractionLength(0)))
                .frame(width: 57)
                .textFieldStyle(.roundedBorder)
                .unitSuffix(unit)
        }
    }
}
