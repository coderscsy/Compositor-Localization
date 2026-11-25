import SwiftUI

struct GradientControls: View {
    @Bindable var session: EditorSession
    @State private var showsGradientEditor = false
    @State private var selectedStopIndex = 0

    var body: some View {
        HStack(spacing: 12) {
            Text(L10n.text(session.fillToolMode.rawValue)).font(ToolHeaderStyle.titleFont)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    Picker("Tool", selection: $session.fillToolMode) {
                        ForEach(FillToolMode.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    if session.fillToolMode == .paintBucket {
                        if !session.isMaskSelected {
                            Picker("Blend Mode", selection: $session.paintBucketSettings.blendMode) {
                                ForEach(BrushBlendMode.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
                            }
                            .pickerStyle(.menu).labelsHidden().fixedSize()
                        }
                        Text("Tolerance")
                        AppSlider(value: Binding<Double>(
                            get: { Double(session.paintBucketSettings.tolerance) },
                            set: { session.paintBucketSettings.tolerance = Int($0.rounded()) }
                        ), in: 0...255).frame(width: 90)
                        TextField("Tolerance", value: $session.paintBucketSettings.tolerance, format: .number)
                            .frame(width: 42).textFieldStyle(.roundedBorder)
                        Toggle("Contiguous", isOn: $session.paintBucketSettings.contiguous)
                        Toggle("All Layers", isOn: $session.paintBucketSettings.sampleAllLayers)
                            .disabled(session.isMaskSelected)
                        Text("Opacity").scrubbable(sensitivity: 0.01, value: $session.paintBucketSettings.opacity, range: 0.01...1)
                        AppSlider(value: $session.paintBucketSettings.opacity, in: 0.01...1).frame(width: 90)
                        Text("\(Int((session.paintBucketSettings.opacity * 100).rounded()))%").monospacedDigit().frame(width: 36)
                    } else if let liveFill = session.activeLayer?.gradientFill, !session.isMaskSelected {
                        Picker("Shape", selection: Binding(
                            get: { liveFill.shape },
                            set: { var next = liveFill; next.shape = $0; session.updateLiveGradientFill(next) }
                        )) {
                            ForEach(GradientShape.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
                        }
                        .pickerStyle(.menu).labelsHidden().fixedSize()
                        Button { showsGradientEditor.toggle() } label: { liveSwatch(stops: liveFill.stops, reversed: liveFill.reversed) }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showsGradientEditor) {
                                GradientStopEditor(
                                    stops: Binding(
                                        get: { session.activeLayer?.gradientFill?.stops ?? liveFill.stops },
                                        set: { stops in
                                            guard var next = session.activeLayer?.gradientFill else { return }
                                            next.stops = stops
                                            session.updateLiveGradientFill(next)
                                        }
                                    ),
                                    selectedIndex: $selectedStopIndex
                                )
                            }
                        Text("Angle")
                        AppSlider(value: Binding(
                            get: { liveFill.angle },
                            set: { var next = liveFill; next.angle = $0; session.updateLiveGradientFill(next) }
                        ), in: -180...180).frame(width: 80)
                        Text("\(Int(liveFill.angle.rounded()))°").monospacedDigit().frame(width: 36)
                        Text("Scale")
                        AppSlider(value: Binding(
                            get: { liveFill.scale },
                            set: { var next = liveFill; next.scale = $0; session.updateLiveGradientFill(next) }
                        ), in: 10...200).frame(width: 80)
                        Text("\(Int(liveFill.scale.rounded()))%").monospacedDigit().frame(width: 40)
                        Toggle("Reverse", isOn: Binding(
                            get: { liveFill.reversed },
                            set: { var next = liveFill; next.reversed = $0; session.updateLiveGradientFill(next) }
                        ))
                    } else {
                        Picker("Shape", selection: $session.gradientSettings.shape) {
                            ForEach(GradientShape.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
                        }
                        .pickerStyle(.menu).labelsHidden().fixedSize()
                        .help("Linear, Radial, Angle, Reflected, or Diamond gradient")
                        Button {
                            if session.gradientSettings.style != .custom {
                                session.gradientSettings.customStops = session.gradientStops(mask: false)
                                session.gradientSettings.style = .custom
                            }
                            showsGradientEditor.toggle()
                        } label: {
                            swatch
                        }
                        .buttonStyle(.plain)
                        .help("Edit multi-stop gradient")
                        .popover(isPresented: $showsGradientEditor) {
                            GradientStopEditor(
                                stops: $session.gradientSettings.customStops,
                                selectedIndex: $selectedStopIndex
                            )
                        }
                        Picker("Colors", selection: $session.gradientSettings.style) {
                            ForEach(GradientStyle.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        Toggle("Reverse", isOn: $session.gradientSettings.reversed)
                        Text("Opacity").scrubbable(sensitivity: 0.01, value: $session.gradientSettings.opacity, range: 0.01...1)
                        AppSlider(value: $session.gradientSettings.opacity, in: 0.01...1).frame(width: 90)
                            .accessibilityLabel("Opacity")
                        TextField("Opacity", value: Binding<Double>(get: { Double(session.gradientSettings.opacity * 100) },
                                                                    set: { session.gradientSettings.opacity = $0.isFinite ? CGFloat(min(100, max(1, $0)) / 100) : 1 }),
                                  format: .number.precision(.fractionLength(0)))
                        .frame(width: 42).textFieldStyle(.roundedBorder)
                        .arrowSteps(value: { Double(session.gradientSettings.opacity * 100) },
                                    change: { session.gradientSettings.opacity = CGFloat(min(100, max(1, $0)) / 100) })
                        .help("Press 1–9 for 10–90%, 0 for 100%")
                        .unitSuffix("%")
                        Button("New Fill Layer") { session.addGradientFillLayer() }
                            .help("Create a non-destructive live Gradient Fill layer")
                    }
                }
            }
            .scrollIndicators(.never)
            Spacer(minLength: 0)
            if session.isMaskSelected { Text("Mask").foregroundStyle(.secondary) }
            if session.gradientEdit != nil {
                Button("Cancel") { session.cancelGradient() }
                Button("Apply") { Task { await session.commitGradient() } }
            }
        }
        .padding(.horizontal, 18).toolHeaderBar().releasesFocusOnCommit(session)
        .disabled(session.showsBusy || session.document == nil)
    }

    private func liveSwatch(stops: [GradientOverlayStop], reversed: Bool) -> some View {
        let sorted = stops.sorted { $0.position < $1.position }
        let gStops = sorted.map {
            Gradient.Stop(color: Color(red: Double($0.red), green: Double($0.green), blue: Double($0.blue), opacity: Double($0.alpha)),
                          location: reversed ? 1 - $0.position : $0.position)
        }.sorted { $0.location < $1.location }
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return Canvas { context, size in
            let tile: CGFloat = 4
            for row in 0..<Int(ceil(size.height / tile)) {
                for column in 0..<Int(ceil(size.width / tile)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)),
                                 with: .color(.gray.opacity(0.45)))
                }
            }
        }
        .background(.white)
        .overlay { LinearGradient(stops: gStops, startPoint: .leading, endPoint: .trailing) }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.black.opacity(0.5), lineWidth: 1) }
        .frame(width: 56, height: 18)
    }

    /// Current colors, over a checkerboard so transparency reads as transparency.
    private var swatch: some View {
        liveSwatch(stops: session.gradientStops(mask: false), reversed: false)
            .accessibilityHidden(true)
    }
}

private struct GradientStopEditor: View {
    @Binding var stops: [GradientOverlayStop]
    @Binding var selectedIndex: Int

    private var safeIndex: Int {
        guard !stops.isEmpty else { return 0 }
        return min(stops.count - 1, max(0, selectedIndex))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gradient Editor").font(.headline)
            HStack(spacing: 6) {
                ForEach(GradientPreset.builtIn) { preset in
                    Button {
                        stops = preset.stops
                        selectedIndex = 0
                    } label: {
                        LinearGradient(
                            stops: preset.stops.map {
                                Gradient.Stop(color: Color(red: Double($0.red), green: Double($0.green), blue: Double($0.blue), opacity: Double($0.alpha)),
                                              location: $0.position)
                            },
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 44, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text(preset.name))
                }
            }
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let sortedStops = stops.sorted { $0.position < $1.position }.map {
                    Gradient.Stop(color: Color(red: Double($0.red), green: Double($0.green), blue: Double($0.blue), opacity: Double($0.alpha)),
                                  location: $0.position)
                }
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(stops: sortedStops, startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1))
                        .frame(height: 22)
                        .onTapGesture { loc in
                            guard stops.count < 16 else { return }
                            let pos = min(1, max(0, Double(loc.x / width)))
                            let newStop = GradientOverlayStop(position: pos, red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
                            stops.append(newStop)
                            selectedIndex = stops.count - 1
                        }
                    ForEach(stops.indices, id: \.self) { idx in
                        let stop = stops[idx]
                        Circle()
                            .fill(Color(red: Double(stop.red), green: Double(stop.green), blue: Double(stop.blue)))
                            .overlay(Circle().stroke(idx == safeIndex ? Color.accentColor : Color.primary, lineWidth: idx == safeIndex ? 2.5 : 1))
                            .frame(width: 12, height: 12)
                            .offset(x: CGFloat(stop.position) * width - 6, y: 24)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        selectedIndex = idx
                                        let pos = min(1, max(0, Double(value.location.x / width)))
                                        stops[idx].position = pos
                                    }
                            )
                    }
                }
            }
            .frame(height: 40)

            if stops.indices.contains(safeIndex) {
                HStack(spacing: 10) {
                    ColorPicker("Color", selection: Binding(
                        get: {
                            let s = stops[safeIndex]
                            return Color(red: Double(s.red), green: Double(s.green), blue: Double(s.blue))
                        },
                        set: { color in
                            if let srgb = NSColor(color).usingColorSpace(.sRGB) {
                                stops[safeIndex].red = srgb.redComponent
                                stops[safeIndex].green = srgb.greenComponent
                                stops[safeIndex].blue = srgb.blueComponent
                            }
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    Text("Alpha")
                    AppSlider(value: Binding(
                        get: { Double(stops[safeIndex].alpha) },
                        set: { stops[safeIndex].alpha = CGFloat($0) }
                    ), in: 0...1).frame(width: 80)
                    Text("\(Int((stops[safeIndex].position * 100).rounded()))%")
                        .monospacedDigit().frame(width: 34)
                    Spacer()
                    Button(role: .destructive) {
                        guard stops.count > 2 else { return }
                        stops.remove(at: safeIndex)
                        selectedIndex = max(0, min(selectedIndex, stops.count - 1))
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(stops.count <= 2)
                    .help("Remove color stop")
                }
            }
            Text("Click the gradient bar to add a color stop; drag stops to reposition.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// One-color tool-rail icon: a Floyd–Steinberg dithered fade from empty to solid, so it
/// reads as a gradient in the same monochrome style as the SF Symbols beside it.
struct GradientToolIcon: View {
    /// 16×16 so each dot is exactly 1 pt inside the icon's 16 pt frame.
    private static let pattern: [[Bool]] = {
        let size = 16
        var ramp = (0..<size).map { _ in (0..<size).map { CGFloat($0) / CGFloat(size - 1) } }
        var result = Array(repeating: Array(repeating: false, count: size), count: size)
        for y in 0..<size {
            for x in 0..<size {
                let on = ramp[y][x] >= 0.5
                result[y][x] = on
                let error = ramp[y][x] - (on ? 1 : 0)
                if x + 1 < size { ramp[y][x + 1] += error * 7 / 16 }
                guard y + 1 < size else { continue }
                if x > 0 { ramp[y + 1][x - 1] += error * 3 / 16 }
                ramp[y + 1][x] += error * 5 / 16
                if x + 1 < size { ramp[y + 1][x + 1] += error / 16 }
            }
        }
        return result
    }()
    var body: some View {
        Canvas { context, size in
            let frame = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let shape = Path(roundedRect: frame, cornerRadius: 3.5)
            let cell = frame.width / CGFloat(Self.pattern.count)
            var dots = Path()
            for (row, line) in Self.pattern.enumerated() {
                for (column, on) in line.enumerated() where on {
                    dots.addRect(CGRect(x: frame.minX + CGFloat(column) * cell, y: frame.minY + CGFloat(row) * cell,
                                        width: cell, height: cell))
                }
            }
            context.clip(to: shape)
            context.fill(dots, with: .foreground)
            context.stroke(shape, with: .foreground, lineWidth: 1.4)
        }
        .accessibilityHidden(true)
    }
}
