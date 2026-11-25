import SwiftUI

struct TransformInspector: View {
    @Bindable var session: EditorSession
    private var value: LayerTransform {
        session.transformEdit?.draft ?? session.activeLayer.map { session.editedTransform(for: $0) }
            ?? LayerTransform(origin: .zero, size: CGSize(width: 1, height: 1))
    }
    @State private var showsSkewPopover = false

    var body: some View {
        if let warp = session.meshWarpEdit {
            meshWarpBar(warp)
        } else {
            standardTransformBar
        }
    }

    private func meshWarpBar(_ warp: MeshWarpEdit) -> some View {
        HStack(spacing: 12) {
            Text("Warp").font(ToolHeaderStyle.titleFont).padding(.leading, 18)
            Picker("Preset", selection: Binding(get: { warp.preset }, set: { session.updateMeshWarpPreset($0) })) {
                ForEach(WarpMeshPreset.allCases, id: \.self) { p in
                    Text(L10n.text(p.rawValue)).tag(p)
                }
            }
            .pickerStyle(.menu).fixedSize()
            if warp.preset != .custom {
                HStack(spacing: 6) {
                    Text("Bend")
                    AppSlider(value: Binding(get: { warp.bend * 100 },
                                             set: { session.updateMeshWarpPreset(warp.preset, bend: $0 / 100) }), in: -100...100)
                        .frame(width: 110)
                    Text("\(Int((warp.bend * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
            }
            Button("Reset") { session.resetMeshWarp() }
            Spacer(minLength: 0)
            Button("Cancel") { session.cancelMeshWarp() }.configuredNativeShortcut(.escape)
            Button("Apply") { session.commitMeshWarp() }.configuredNativeShortcut(.return)
        }
        .padding(.trailing, 18).toolHeaderBar()
    }

    private var standardTransformBar: some View {
        HStack(spacing: 12) {
          Text(L10n.text(session.transformTargetsMask ? "Transform Mask" : "Transform")).font(ToolHeaderStyle.titleFont)
              .padding(.leading, 18)
          // Command flips Auto Select while it's held, and the box shows it flipped (see HeldModifiers).
          Toggle("Auto Select", isOn: Binding(get: { session.transformAutoSelect != held.contains(.command) },
                                              set: { session.transformAutoSelect = $0 != held.contains(.command) }))
              .help("Select layers by clicking the canvas. Hold Command to turn it the other way while you click.")
              .accessibilityIdentifier("transformAutoSelect")
          Toggle("Show Controls", isOn: $session.showsTransformControls)
              .help("Show the transform box and handles (⌘H). When hidden, drag anywhere to move the layer.")
          ScrollView(.horizontal) {
            HStack(spacing: 12) {
            HStack(spacing: 12) {
                PivotGridControl(pivot: $session.transformPivot)
                    .help("Transform reference point (pivot) for rotation, scaling, and skew")
                field("X", value: value.origin.x) { $0.origin.x = $1 }.fixedSize()
                field("Y", value: value.origin.y) { $0.origin.y = $1 }.fixedSize()
                TransformValueField(label: "W", fieldWidth: Self.longField, value: value.size.width, range: 1...30_000, finish: finish, returned: releaseFocus) { resize($0, width: true) }.fixedSize()
                TransformValueField(label: "H", fieldWidth: Self.longField, value: value.size.height, range: 1...30_000, finish: finish, returned: releaseFocus) { resize($0, width: false) }.fixedSize()
                // Shift flips the lock while dragging a handle, and the button shows it flipped.
                Toggle(isOn: Binding(get: { session.locksTransformRatio != held.contains(.shift) },
                                     set: { session.locksTransformRatio = $0 != held.contains(.shift) })) { Image(systemName: "link") }
                    .toggleStyle(.button).help("Lock aspect ratio. Hold Shift while dragging a handle to turn it the other way.")
                    .accessibilityLabel("Lock aspect ratio")
                TransformValueField(label: "Scale", suffix: "%", fieldWidth: Self.shortField, value: value.scalePercent(pixelSize: pixelSize), range: 0.1...30_000, finish: finish, returned: releaseFocus) { number in
                    change { value in
                        guard number > 0 else { return }
                        value = value.scaled(toPercent: number, pixelSize: pixelSize, aroundUnitPivot: session.transformPivot)
                    }
                }.fixedSize().help("Scale width and height together, about the reference point")
                TransformValueField(label: "°", fieldWidth: Self.shortField, value: value.rotation, range: -360...360, finish: finish, returned: releaseFocus) { number in
                    change { $0 = $0.rotated(toDegrees: number, aroundUnitPivot: session.transformPivot) }
                }.fixedSize()
                Button("Skew") { showsSkewPopover.toggle() }
                    .popover(isPresented: $showsSkewPopover, arrowEdge: .bottom) {
                        SkewPopover(session: session)
                    }
                    .help("Independent horizontal and vertical skew (-75° to 75°)")
                Button("Warp") { session.beginMeshWarp() }
                    .disabled(!session.canTransform || session.activeLayer?.asset == nil || session.activeLayer?.isGroup == true)
                    .help("3×3 bicubic Mesh Warp transform")
                Picker("Sampling", selection: Binding(get: { value.sampling }, set: { sampling in
                    change { $0.sampling = sampling }
                })) {
                    ForEach(LayerSampling.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
                }.frame(width: 170)
                ToolHeaderPill(segmentWidth: 34) {
                    Button { change { $0.flipX.toggle() } } label: {
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    }
                    .help("Flip Horizontal").accessibilityLabel("Flip Horizontal")
                    Button { change { $0.flipY.toggle() } } label: {
                        Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                    }
                    .help("Flip Vertical").accessibilityLabel("Flip Vertical")
                }
                Divider().frame(height: 16)

            // Numbers describe an ordinary transform; while distorted, the handles are the controls.
            }.disabled((!session.canTransform && session.transformEdit == nil) || session.transformEdit?.corners != nil)
            // Outside the group the numbers are disabled with, so a move in progress leaves it alone.
            AlignButton(session: session)
            }
                .padding(.horizontal, 18)
          }.scrollIndicators(.never)
          // Only an edit that waits for them — typed values, ⌘T, a distortion — has anything to cancel or apply. A
          // handle drag applies itself on release, and ghosted buttons after it read as the pixels being resampled,
          // which they never are. Left in place unseen, so Escape and Return still reach a drag in progress.
          let pending = session.transformEdit?.persistent == true
          HStack(spacing: 12) {
              Button("Cancel") { session.cancelTransform() }.configuredNativeShortcut(.escape)
                  .disabled(session.transformEdit == nil)
              Button("Apply") { session.commitTransform(); releaseFocus() }.configuredNativeShortcut(.return)
                  .disabled(session.transformEdit == nil).accessibilityIdentifier("applyTransform")
          }
          .opacity(pending ? 1 : 0).allowsHitTesting(pending).accessibilityHidden(!pending)
          .animation(.easeOut(duration: 0.12), value: pending)
        }.padding(.trailing, 18).toolHeaderBar().releasesFocusOnCommit(session)
    }

    /// 100% scale: the layer's pixels (a blank layer's size before this edit, so typing doesn't compound).
    private var held: NSEvent.ModifierFlags { HeldModifiers.shared.flags }
    private var pixelSize: CGSize { session.transformPixelSize ?? session.activeLayer?.size ?? value.size }
    /// Room for four digits, for Scale and rotation, and six and a half for position and size, which run to five and a
    /// sign or a decimal: 7.6 points a digit at the bar's 12-point text, and 8 for a field border's padding.
    static let shortField: CGFloat = 38
    static let longField: CGFloat = 57

    private func field(_ label: String, value: CGFloat, range: ClosedRange<CGFloat> = -30_000...30_000,
                       set: @escaping (inout LayerTransform, CGFloat) -> Void) -> some View {
        TransformValueField(label: label, fieldWidth: Self.longField, value: value, range: range, finish: finish, returned: releaseFocus) { number in change { set(&$0, number) } }
    }
    /// A value typed, stepped or dragged shows on the canvas as it changes, and is applied without Cancel or Apply —
    /// a transform never resamples the layer's pixels, so there is nothing to confirm — as one undo step once the
    /// field is done with it (see `finish`), as a handle drag is when it's let go. An edit already waiting for Apply —
    /// ⌘T, a distortion, selected pixels being transformed — takes it as part of that edit.
    private func change(_ update: (inout LayerTransform) -> Void) {
        if session.transformEdit == nil {
            session.beginTransform(persistent: false)
            session.transformEdit?.fromFields = true
        }
        guard var value = session.transformEdit?.draft else { return }
        update(&value)
        session.previewTransform(value)
    }
    /// Return in a field, or Apply: the canvas takes the keyboard back, so the field isn't left editing and the tool
    /// keys work again.
    private func releaseFocus() { session.canvasFocusRequest += 1 }
    /// A field done with its value — a drag on its label let go, or the field left (Return, Tab, a click elsewhere):
    /// what the fields changed is applied, one undo step.
    private func finish() {
        if session.transformEdit?.fromFields == true { session.commitTransform() }
    }
    private func resize(_ number: CGFloat, width: Bool) {
        change { value in
            guard number >= 1 else { return }
            let anchor = value.point(session.transformPivot)
            if width {
                if session.locksTransformRatio { value.size.height *= number / value.size.width }
                value.size.width = number
            } else {
                if session.locksTransformRatio { value.size.width *= number / value.size.height }
                value.size.height = number
            }
            let moved = value.point(session.transformPivot)
            value.origin.x += anchor.x - moved.x
            value.origin.y += anchor.y - moved.y
        }
    }
}

/// Compact 3×3 Photoshop-style reference point (pivot) picker.
private struct PivotGridControl: View {
    @Binding var pivot: CGPoint
    private let coords: [CGFloat] = [0, 0.5, 1]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { col in
                        let pt = CGPoint(x: coords[col], y: coords[row])
                        let selected = abs(pivot.x - pt.x) < 0.01 && abs(pivot.y - pt.y) < 0.01
                        Button { pivot = pt } label: {
                            Rectangle()
                                .fill(selected ? Color.accentColor : Color.white.opacity(0.35))
                                .frame(width: 5, height: 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct SkewPopover: View {
    @Bindable var session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Skew").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Horizontal").font(.caption)
                    Spacer()
                    Text(String(format: "%.1f°", session.transformSkewX)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { session.transformSkewX },
                                      set: { session.applyTransformSkew(skewX: $0, skewY: session.transformSkewY) }), in: -75...75)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Vertical").font(.caption)
                    Spacer()
                    Text(String(format: "%.1f°", session.transformSkewY)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { session.transformSkewY },
                                      set: { session.applyTransformSkew(skewX: session.transformSkewX, skewY: $0) }), in: -75...75)
            }
            HStack {
                Spacer()
                Button("Reset") { session.applyTransformSkew(skewX: 0, skewY: 0) }.controlSize(.small)
            }
        }
        .padding(14).frame(width: 240)
    }
}

struct TransformValueField: View {
    let label: String
    var suffix: String? = nil
    /// The text box's own width, when it's narrower than the space it's given: Scale and rotation take four digits.
    var fieldWidth: CGFloat? = nil
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    /// The field is done with its value: a drag on its label let go, or the field left.
    let finish: () -> Void
    /// Return pressed in the field, after it lets go of the keyboard.
    var returned: () -> Void = {}
    let change: (CGFloat) -> Void
    @State private var text = ""
    @State private var stepper = ArrowStepper()
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 4) {
            Text(L10n.text(label)).font(.caption).foregroundStyle(.secondary)
                .scrubbable(sensitivity: 1, value: Binding(get: { value }, set: { newValue in
                    change(newValue)
                    text = Self.formatted(Double(newValue))
                }), range: range, step: 1, onEnd: finish)
            TextField(L10n.text(label), text: $text)
                .textFieldStyle(.roundedBorder).focused($focused)
                .frame(width: fieldWidth)
                .accessibilityIdentifier("transform\(label)")
                .onAppear { sync() }
                .onChange(of: value) { if !focused { sync() } }
                .onChange(of: focused) { if !focused { finish(); sync() } }
                // Return applies the value and leaves the field, whichever of it and the bar's Apply takes the key.
                .onSubmit { focused = false; returned() }
                .onChange(of: text) {
                    if focused, let number = Double(text), number.isFinite { change(CGFloat(number)) }
                }
                // The field holds off syncing while it has focus, so as not to fight what is being typed; a step
                // is not typing, so it writes the number it applied.
                .arrowSteps(editing: focused, stepper: stepper, value: { Double(value) },
                            change: { stepped in
                                change(CGFloat(stepped))
                                text = Self.formatted(stepped)
                            })
            if let suffix { Text(suffix).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func sync() { text = Self.formatted(Double(value)) }
    /// No trailing zeros on a whole number, two decimals otherwise.
    static func formatted(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.005 ? String(Int(value.rounded())) : String(format: "%.2f", value)
    }
}

/// The Move bar's Align button: a small panel of icons, horizontal on one row and vertical on the next, each aligning
/// three ways and distributing two. Layers line up with
/// the selection, with the canvas when one layer is selected, or else with each other; distributing takes three or more.
private struct AlignButton: View {
    @Bindable var session: EditorSession
    @State private var showing = false

    var body: some View {
        Button("Align") { showing.toggle() }
            .disabled(!session.canAlignLayers)
            .help("Line layers up with each other, the selection, or the canvas when one is selected")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                // Horizontal on the top row, vertical below: align three ways, then distribute two.
                VStack(alignment: .leading, spacing: 6) {
                    row([.left, .horizontalCenter, .right], [.horizontalCenters, .horizontalSpacing])
                    row([.top, .verticalCenter, .bottom], [.verticalCenters, .verticalSpacing])
                }
                .padding(8)
            }
    }

    private func row(_ alignments: [LayerAlignment], _ distributions: [LayerDistribution]) -> some View {
        HStack(spacing: 2) {
            ForEach(alignments, id: \.self) { alignment in
                icon(alignment.symbol, L10n.text("Align " + alignment.rawValue)) { session.alignLayers(alignment) }
            }
            ForEach(distributions, id: \.self) { distribution in
                icon(distribution.symbol, L10n.text("Distribute " + distribution.rawValue + " (three or more layers)")) {
                    session.distributeLayers(distribution)
                }
                .disabled(!session.canDistributeLayers)
            }
        }
    }

    private func icon(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15)).frame(width: 30, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.borderless).help(title).accessibilityLabel(title)
    }
}
