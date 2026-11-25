import SwiftUI

struct LayerAppearanceControls: View {
    @Bindable var session: EditorSession
    let layerID: UUID?
    @State private var percentage = "100"
    @State private var fillPercentage = "100"
    @State private var stepper = ArrowStepper()
    @State private var fillStepper = ArrowStepper()
    @FocusState private var focusedField: Field?
    private enum Field { case opacity, fill }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Blend").font(.caption)
                BlendModePicker(session: session)
                Button {
                    session.openBlendIf()
                } label: {
                    Image(systemName: "slider.horizontal.below.square.filled.and.square")
                        .font(.system(size: 12))
                        .foregroundStyle(session.activeLayer?.blendIf?.nonIdentity != nil ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(L10n.text("Blending Options (Blend If)"))
                .accessibilityLabel(L10n.text("Blending Options"))
            }.disabled(!session.canEditBlendMode)
            HStack(spacing: 6) {
                Text("Opacity").font(.caption)
                    .frame(minWidth: 44, alignment: .leading)
                    .scrubbable(sensitivity: 1,
                                value: Binding<Double>(get: { (session.activeLayer?.opacity ?? 1) * 100 }, set: stepOpacity),
                                range: 0...100,
                                onStart: { session.beginOpacityEdit() },
                                onEnd: { session.finishOpacityEdit() })
                AppSlider(value: Binding(get: { session.activeLayer?.opacity ?? 1 },
                                         set: { session.setLayerOpacity($0) }), in: 0...1,
                          onEditingChanged: { if $0 { session.beginOpacityEdit() } else { session.finishOpacityEdit() } })
                    .accessibilityLabel("Opacity")
                HStack(spacing: 2) {
                    TextField("Opacity percent", text: $percentage)
                        .textFieldStyle(.roundedBorder).frame(width: 44).focused($focusedField, equals: .opacity)
                        .onSubmit { releaseFocus() }
                        .onExitCommand { releaseFocus() }
                        .onChange(of: focusedField) { old, new in
                            if old == .opacity && new != .opacity { applyOpacityPercentage() }
                            if old == .fill && new != .fill { applyFillPercentage() }
                        }
                        .arrowSteps(editing: focusedField == .opacity, stepper: stepper,
                                    value: { ((session.activeLayer?.opacity ?? 1) * 100).rounded() },
                                    change: { stepOpacity($0) })
                    Text("%").font(.caption)
                }
            }.disabled(!session.canEditOpacity)
            HStack(spacing: 6) {
                Text("Fill").font(.caption)
                    .frame(minWidth: 44, alignment: .leading)
                    .scrubbable(sensitivity: 1,
                                value: Binding<Double>(get: { (session.activeLayer?.fillOpacity ?? 1) * 100 }, set: stepFill),
                                range: 0...100,
                                onStart: { session.beginFillOpacityEdit() },
                                onEnd: { session.finishFillOpacityEdit() })
                AppSlider(value: Binding(get: { session.activeLayer?.fillOpacity ?? 1 },
                                         set: { session.setLayerFillOpacity($0) }), in: 0...1,
                          onEditingChanged: { if $0 { session.beginFillOpacityEdit() } else { session.finishFillOpacityEdit() } })
                    .accessibilityLabel("Fill")
                HStack(spacing: 2) {
                    TextField("Fill percent", text: $fillPercentage)
                        .textFieldStyle(.roundedBorder).frame(width: 44).focused($focusedField, equals: .fill)
                        .onSubmit { releaseFocus() }
                        .onExitCommand { releaseFocus() }
                        .arrowSteps(editing: focusedField == .fill, stepper: fillStepper,
                                    value: { ((session.activeLayer?.fillOpacity ?? 1) * 100).rounded() },
                                    change: { stepFill($0) })
                    Text("%").font(.caption)
                }
            }.disabled(!session.canEditFillOpacity)
            LayerLockControls(session: session)
        }.padding(12)
            .onAppear { syncOpacity(); syncFill() }
            .onChange(of: session.activeLayer?.opacity) { _, _ in if focusedField != .opacity { syncOpacity() } }
            .onChange(of: session.activeLayer?.fillOpacity) { _, _ in if focusedField != .fill { syncFill() } }
            .onDisappear { session.finishOpacityEdit() }
    }

    /// Up and Down nudge the opacity by one percent, or ten with Shift.
    private func stepOpacity(_ percent: Double) {
        guard session.activeLayerID == layerID else { return }
        session.setLayerOpacity(min(100, max(0, percent)) / 100)
        syncOpacity()
    }
    private func stepFill(_ percent: Double) {
        guard session.activeLayerID == layerID else { return }
        session.setLayerFillOpacity(min(100, max(0, percent)) / 100)
        syncFill()
    }
    /// Losing focus applies the value; the canvas takes the focus back so a tool's key works straight away.
    private func releaseFocus() {
        focusedField = nil
        session.canvasFocusRequest += 1
    }
    private func syncOpacity() { percentage = String(Int(((session.activeLayer?.opacity ?? 1) * 100).rounded())) }
    private func syncFill() { fillPercentage = String(Int(((session.activeLayer?.fillOpacity ?? 1) * 100).rounded())) }
    private func applyOpacityPercentage() {
        guard session.activeLayerID == layerID else { return }
        if let value = Double(percentage), value.isFinite { session.setLayerOpacity(value / 100) }
        syncOpacity()
    }
    private func applyFillPercentage() {
        guard session.activeLayerID == layerID else { return }
        if let value = Double(fillPercentage), value.isFinite { session.setLayerFillOpacity(value / 100) }
        syncFill()
    }
}
