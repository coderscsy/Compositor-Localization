import SwiftUI

/// One effect's controls, bound to the layer that opened the panel. Changes preview on the canvas.
struct EffectsSheet: View {
    @Bindable var session: EditorSession
    let kind: LayerEffectKind

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch kind {
            case .stroke: stroke
            case .shadow: shadow
            case .colorOverlay: colorOverlay
            case .gradientOverlay: gradientOverlay
            case .patternOverlay: patternOverlay
            case .innerShadow: innerShadow
            case .outerGlow: outerGlow
            case .innerGlow: innerGlow
            case .bevelEmboss: bevelEmboss
            }
            Divider()
            HStack {
                Button("Cancel") { session.finishEffectsEditing(commit: false) }
                    .configuredNativeShortcut(.escape)
                Spacer()
                Button("OK") { session.finishEffectsEditing(commit: true) }
                    .configuredNativeShortcut(.return).buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 360).fixedSize()
        // The picker previews its working color on the layer while it is open.
        .onChange(of: session.colorPicker?.color) { _, _ in session.previewEffectColor() }
    }

    @ViewBuilder private var stroke: some View {
        let effect = session.editingEffects.stroke
        HStack {
            Text("Stroke").font(.headline)
            Spacer()
            if effect != nil { swatch(.stroke) }
        }
        if let effect {
            blendPicker("Blend Mode", selection: Binding(
                get: { effect.blendMode ?? .normal },
                set: { mode in session.changeEffects { $0.stroke?.blendMode = mode == .normal ? nil : mode } }
            ))
            slider("Size", value: Binding(get: { effect.size }, set: { size in
                session.changeEffects { $0.stroke?.size = size }
            }), range: 0...20, inputRange: 0...StrokeEffect.maxSize, unit: "px")
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.stroke?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
            HStack(spacing: 10) {
                Text("Position").frame(width: 64, alignment: .leading)
                Picker("Position", selection: Binding(get: { effect.resolvedPosition }, set: { pos in
                    session.changeEffects { $0.stroke?.resolvedPosition = pos }
                })) {
                    ForEach(StrokePosition.allCases, id: \.self) { pos in
                        Text(L10n.text(pos.rawValue)).tag(pos)
                    }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
        }
    }

    @ViewBuilder private var shadow: some View {
        let effect = session.editingEffects.shadow
        HStack {
            Text("Drop Shadow").font(.headline)
            Spacer()
            if effect != nil { swatch(.shadow) }
        }
        if let effect {
            blendPicker("Blend Mode", selection: Binding(
                get: { effect.blendMode ?? .normal },
                set: { mode in session.changeEffects { $0.shadow?.blendMode = mode == .normal ? nil : mode } }
            ))
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.shadow?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
            slider("Angle", value: Binding(get: { effect.angle }, set: { angle in
                session.changeEffects { $0.shadow?.angle = angle }
            }), range: -180...180, unit: "°")
            slider("Distance", value: Binding(get: { effect.distance }, set: { distance in
                session.changeEffects { $0.shadow?.distance = distance }
            }), range: 0...100, inputRange: 0...5000, unit: "px")
            slider("Spread", value: Binding(get: { effect.spread ?? 0 }, set: { spread in
                session.changeEffects { $0.shadow?.spread = spread > 0 ? spread : nil }
            }), range: 0...100, unit: "%")
            slider("Blur", value: Binding(get: { effect.blur }, set: { blur in
                session.changeEffects { $0.shadow?.blur = blur }
            }), range: 0...100, inputRange: 0...500, unit: "px")
        }
    }

    @ViewBuilder private var colorOverlay: some View {
        let effect = session.editingEffects.colorOverlay
        HStack {
            Text("Color Overlay").font(.headline)
            Spacer()
            if effect != nil { swatch(.colorOverlay) }
        }
        if let effect {
            blendPicker("Blend Mode", selection: Binding(
                get: { effect.blendMode ?? .normal },
                set: { mode in session.changeEffects { $0.colorOverlay?.blendMode = mode == .normal ? nil : mode } }
            ))
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.colorOverlay?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
        }
    }

    @ViewBuilder private var gradientOverlay: some View {
        let effect = session.editingEffects.gradientOverlay
        HStack {
            Text("Gradient Overlay").font(.headline)
            Spacer()
        }
        if let effect {
            blendPicker("Blend Mode", selection: Binding(
                get: { effect.blendMode },
                set: { mode in session.changeEffects { $0.gradientOverlay?.blendMode = mode } }
            ))
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.gradientOverlay?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
            HStack(spacing: 10) {
                Text("Colors").frame(width: 64, alignment: .leading)
                colorWell(color: effect.startColor, label: L10n.text("Start Color")) { c in
                    session.changeEffects {
                        guard $0.gradientOverlay?.stops.isEmpty == false else { return }
                        $0.gradientOverlay?.stops[0].red = c.red
                        $0.gradientOverlay?.stops[0].green = c.green
                        $0.gradientOverlay?.stops[0].blue = c.blue
                    }
                }
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(
                        stops: effect.stops.sorted { $0.position < $1.position }.map {
                            Gradient.Stop(color: Color(red: Double($0.red), green: Double($0.green), blue: Double($0.blue), opacity: Double($0.alpha)),
                                          location: $0.position)
                        },
                        startPoint: effect.reverse ? .trailing : .leading,
                        endPoint: effect.reverse ? .leading : .trailing
                    ))
                    .frame(height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
                colorWell(color: effect.endColor, label: L10n.text("End Color")) { c in
                    session.changeEffects {
                        guard let last = $0.gradientOverlay?.stops.indices.last else { return }
                        $0.gradientOverlay?.stops[last].red = c.red
                        $0.gradientOverlay?.stops[last].green = c.green
                        $0.gradientOverlay?.stops[last].blue = c.blue
                    }
                }
            }
            HStack(spacing: 10) {
                Text("Style").frame(width: 64, alignment: .leading)
                Picker("Style", selection: Binding(
                    get: { effect.style },
                    set: { style in session.changeEffects { $0.gradientOverlay?.style = style } }
                )) {
                    ForEach(GradientOverlayStyle.allCases, id: \.self) { style in
                        Text(L10n.text(style.rawValue)).tag(style)
                    }
                }.labelsHidden()
                Toggle("Reverse", isOn: Binding(
                    get: { effect.reverse },
                    set: { rev in session.changeEffects { $0.gradientOverlay?.reverse = rev } }
                ))
            }
            slider("Angle", value: Binding(get: { effect.angle }, set: { angle in
                session.changeEffects { $0.gradientOverlay?.angle = angle }
            }), range: -180...180, unit: "°")
            slider("Scale", value: Binding(get: { effect.scale }, set: { scale in
                session.changeEffects { $0.gradientOverlay?.scale = scale }
            }), range: 10...150, unit: "%")
        }
    }

    @ViewBuilder private var patternOverlay: some View {
        let effect = session.editingEffects.patternOverlay
        HStack {
            Text("Pattern Overlay").font(.headline)
            Spacer()
            if effect != nil { swatch(.patternOverlay) }
        }
        if let effect {
            blendPicker("Blend Mode", selection: Binding(
                get: { effect.blendMode },
                set: { mode in session.changeEffects { $0.patternOverlay?.blendMode = mode } }
            ))
            HStack(spacing: 10) {
                Text("Pattern").frame(width: 64, alignment: .leading)
                Picker("Pattern", selection: Binding(
                    get: { effect.pattern },
                    set: { pat in session.changeEffects { $0.patternOverlay?.pattern = pat } }
                )) {
                    ForEach(PatternPreset.allCases, id: \.self) { pat in
                        Text(L10n.text(pat.rawValue)).tag(pat)
                    }
                }.labelsHidden()
            }
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.patternOverlay?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
            slider("Scale", value: Binding(get: { effect.scale }, set: { scale in
                session.changeEffects { $0.patternOverlay?.scale = scale }
            }), range: 10...500, unit: "%")
        }
    }

    @ViewBuilder private var innerShadow: some View {
        let effect = session.editingEffects.innerShadow
        HStack {
            Text("Inner Shadow").font(.headline)
            Spacer()
            if effect != nil { swatch(.innerShadow) }
        }
        if let effect {
            blendPicker("Blend Mode", selection: Binding(
                get: { effect.blendMode ?? .normal },
                set: { mode in session.changeEffects { $0.innerShadow?.blendMode = mode == .normal ? nil : mode } }
            ))
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.innerShadow?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
            slider("Angle", value: Binding(get: { effect.angle }, set: { angle in
                session.changeEffects { $0.innerShadow?.angle = angle }
            }), range: -180...180, unit: "°")
            slider("Distance", value: Binding(get: { effect.distance }, set: { distance in
                session.changeEffects { $0.innerShadow?.distance = distance }
            }), range: 0...50, inputRange: 0...5000, unit: "px")
            slider("Choke", value: Binding(get: { effect.spread ?? 0 }, set: { choke in
                session.changeEffects { $0.innerShadow?.spread = choke > 0 ? choke : nil }
            }), range: 0...100, unit: "%")
            slider("Blur", value: Binding(get: { effect.blur }, set: { blur in
                session.changeEffects { $0.innerShadow?.blur = blur }
            }), range: 0...100, inputRange: 0...500, unit: "px")
        }
    }

    @ViewBuilder private var outerGlow: some View {
        let effect = session.editingEffects.outerGlow
        HStack {
            Text("Outer Glow").font(.headline)
            Spacer()
            if effect != nil { swatch(.outerGlow) }
        }
        if let effect {
            blendPicker("Blend Mode", selection: Binding(
                get: { effect.blendMode ?? .normal },
                set: { mode in session.changeEffects { $0.outerGlow?.blendMode = mode == .normal ? nil : mode } }
            ))
            slider("Spread", value: Binding(get: { effect.spread ?? 0 }, set: { spread in
                session.changeEffects { $0.outerGlow?.spread = spread > 0 ? spread : nil }
            }), range: 0...100, unit: "%")
            slider("Size", value: Binding(get: { effect.size }, set: { size in
                session.changeEffects { $0.outerGlow?.size = size }
            }), range: 0...100, inputRange: 0...500, unit: "px")
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.outerGlow?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
        }
    }

    @ViewBuilder private var innerGlow: some View {
        let effect = session.editingEffects.innerGlow
        HStack {
            Text("Inner Glow").font(.headline)
            Spacer()
            if effect != nil { swatch(.innerGlow) }
        }
        if let effect {
            blendPicker("Blend Mode", selection: Binding(
                get: { effect.blendMode ?? .normal },
                set: { mode in session.changeEffects { $0.innerGlow?.blendMode = mode == .normal ? nil : mode } }
            ))
            slider("Choke", value: Binding(get: { effect.spread ?? 0 }, set: { choke in
                session.changeEffects { $0.innerGlow?.spread = choke > 0 ? choke : nil }
            }), range: 0...100, unit: "%")
            slider("Size", value: Binding(get: { effect.size }, set: { size in
                session.changeEffects { $0.innerGlow?.size = size }
            }), range: 0...100, inputRange: 0...500, unit: "px")
            slider("Opacity", value: Binding(get: { CGFloat(effect.opacity * 100) }, set: { value in
                session.changeEffects { $0.innerGlow?.opacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
        }
    }

    @ViewBuilder private var bevelEmboss: some View {
        let effect = session.editingEffects.bevelEmboss
        HStack {
            Text("Bevel & Emboss").font(.headline)
            Spacer()
        }
        if let effect {
            HStack(spacing: 10) {
                Text("Style").frame(width: 64, alignment: .leading)
                Picker("Style", selection: Binding(
                    get: { effect.style },
                    set: { style in session.changeEffects { $0.bevelEmboss?.style = style } }
                )) {
                    ForEach(BevelEmbossStyle.allCases, id: \.self) { style in
                        Text(L10n.text(style.rawValue)).tag(style)
                    }
                }.labelsHidden()
            }
            HStack(spacing: 10) {
                Text("Direction").frame(width: 64, alignment: .leading)
                Picker("Direction", selection: Binding(
                    get: { effect.direction },
                    set: { dir in session.changeEffects { $0.bevelEmboss?.direction = dir } }
                )) {
                    ForEach(BevelDirection.allCases, id: \.self) { dir in
                        Text(L10n.text(dir.rawValue)).tag(dir)
                    }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            slider("Depth", value: Binding(get: { effect.depth }, set: { depth in
                session.changeEffects { $0.bevelEmboss?.depth = depth }
            }), range: 1...500, inputRange: 1...1000, unit: "%")
            slider("Size", value: Binding(get: { effect.size }, set: { size in
                session.changeEffects { $0.bevelEmboss?.size = size }
            }), range: 0...60, inputRange: 0...250, unit: "px")
            slider("Soften", value: Binding(get: { effect.soften }, set: { soften in
                session.changeEffects { $0.bevelEmboss?.soften = soften }
            }), range: 0...16, unit: "px")
            slider("Angle", value: Binding(get: { effect.angle }, set: { angle in
                session.changeEffects { $0.bevelEmboss?.angle = angle }
            }), range: -180...180, unit: "°")
            slider("Altitude", value: Binding(get: { effect.altitude }, set: { alt in
                session.changeEffects { $0.bevelEmboss?.altitude = alt }
            }), range: 0...90, unit: "°")
            HStack(spacing: 8) {
                Text("Highlight").frame(width: 64, alignment: .leading)
                colorWell(color: effect.highlightColor, label: L10n.text("Highlight Color")) { c in
                    session.changeEffects {
                        $0.bevelEmboss?.highlightRed = c.red
                        $0.bevelEmboss?.highlightGreen = c.green
                        $0.bevelEmboss?.highlightBlue = c.blue
                    }
                }
                Picker("Highlight Mode", selection: Binding(
                    get: { effect.highlightBlendMode },
                    set: { mode in session.changeEffects { $0.bevelEmboss?.highlightBlendMode = mode } }
                )) {
                    ForEach(EffectBlendMode.allCases, id: \.self) { m in Text(L10n.text(m.rawValue)).tag(m) }
                }.labelsHidden()
            }
            slider("Opacity", value: Binding(get: { CGFloat(effect.highlightOpacity * 100) }, set: { value in
                session.changeEffects { $0.bevelEmboss?.highlightOpacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
            HStack(spacing: 8) {
                Text("Shadow").frame(width: 64, alignment: .leading)
                colorWell(color: effect.shadowColor, label: L10n.text("Shadow Color")) { c in
                    session.changeEffects {
                        $0.bevelEmboss?.shadowRed = c.red
                        $0.bevelEmboss?.shadowGreen = c.green
                        $0.bevelEmboss?.shadowBlue = c.blue
                    }
                }
                Picker("Shadow Mode", selection: Binding(
                    get: { effect.shadowBlendMode },
                    set: { mode in session.changeEffects { $0.bevelEmboss?.shadowBlendMode = mode } }
                )) {
                    ForEach(EffectBlendMode.allCases, id: \.self) { m in Text(L10n.text(m.rawValue)).tag(m) }
                }.labelsHidden()
            }
            slider("Opacity", value: Binding(get: { CGFloat(effect.shadowOpacity * 100) }, set: { value in
                session.changeEffects { $0.bevelEmboss?.shadowOpacity = Double(value) / 100 }
            }), range: 0...100, unit: "%")
        }
    }

    private func blendPicker(_ title: String, selection: Binding<EffectBlendMode>) -> some View {
        HStack(spacing: 10) {
            Text(L10n.text(title)).frame(width: 64, alignment: .leading)
            Picker(L10n.text(title), selection: selection) {
                ForEach(EffectBlendMode.allCases, id: \.self) { mode in
                    Text(L10n.text(mode.rawValue)).tag(mode)
                }
            }.labelsHidden()
        }
    }

    private func colorWell(color: PaletteColor, label: String, onChange: @escaping (PaletteColor) -> Void) -> some View {
        ColorPicker(label, selection: Binding(
            get: { Color(red: Double(color.red), green: Double(color.green), blue: Double(color.blue)) },
            set: { newColor in
                if let srgb = NSColor(newColor).usingColorSpace(.sRGB) {
                    onChange(PaletteColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent))
                }
            }
        ), supportsOpacity: false)
        .labelsHidden()
        .frame(width: 28)
    }

    /// The effect's color, opened in the app's own picker.
    private func swatch(_ kind: LayerEffectKind) -> some View {
        let color = session.editingEffects.color(kind)
        return Button { session.openEffectColorPicker(kind) } label: {
            ColorSwatch(color: Color(red: Double(color?.red ?? 0), green: Double(color?.green ?? 0), blue: Double(color?.blue ?? 0)))
        }
        .buttonStyle(.plain)
        .help("\(L10n.text(kind.rawValue)) color")
        .accessibilityLabel("\(L10n.text(kind.rawValue)) color")
    }

    private func slider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>,
                        inputRange: ClosedRange<CGFloat>? = nil, unit: String) -> some View {
        let limits = inputRange ?? range
        let setAmount: (Double) -> Void = { amount in
            guard amount.isFinite else { return }
            value.wrappedValue = min(limits.upperBound, max(limits.lowerBound, CGFloat(amount)))
        }
        return HStack(spacing: 10) {
            Text(L10n.text(title)).frame(width: 64, alignment: .leading)
                .scrubbable(sensitivity: 1, value: value, range: limits)
            AppSlider(value: Binding(get: { min(range.upperBound, max(range.lowerBound, value.wrappedValue)) },
                                  set: { value.wrappedValue = $0 }), in: range)
                .accessibilityLabel(L10n.text(title))
            TextField(L10n.text(title), value: Binding(get: { Double(value.wrappedValue) },
                                            set: setAmount),
                      format: .number.precision(.fractionLength(0)))
                .frame(width: 48).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .arrowSteps(value: { Double(value.wrappedValue) },
                            change: setAmount)
            Text(unit).frame(width: 16, alignment: .trailing).padding(.leading, -8)
        }
    }
}
