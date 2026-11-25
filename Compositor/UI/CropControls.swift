import SwiftUI

/// The Crop tool's header. A view of its own because dragging the crop frame changes `cropRect` on
/// every mouse move: read here, only this bar re-renders, not the whole editor and its Layers panel.
struct CropControls: View {
    @Bindable var session: EditorSession
    @State private var showsCustomRatio = false
    @State private var customRatio = "4:5"
    private let ratioGroups = [["Free", "Canvas"], ["1:1"], ["4:3", "16:9", "2.39:1"], ["3:4", "9:16"]]
    private var ratios: [String] { ratioGroups.flatMap { $0 } }

    var body: some View {
        HStack(spacing: 12) {
            Text("Crop").font(ToolHeaderStyle.titleFont)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    if !session.cropPerspectiveMode {
                        Picker("Ratio", selection: ratioSelection) {
                            // Grouped by shape: free and the canvas's own proportions, square, wide, tall.
                            ForEach(ratioGroups.indices, id: \.self) { index in
                                if index > 0 { Divider() }
                                ForEach(ratioGroups[index], id: \.self) { Text(L10n.text($0)) }
                            }
                            if !ratios.contains(session.cropRatioChoice) {
                                Text(session.cropRatioChoice).tag(session.cropRatioChoice)
                            }
                            Divider()
                            Text("Custom…").tag("Custom")
                        }.frame(width: 140)
                            .popover(isPresented: $showsCustomRatio) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Custom ratio").font(.headline)
                                    TextField("Width:Height", text: $customRatio)
                                        .textFieldStyle(.roundedBorder)
                                        .onSubmit { applyCustomRatio() }
                                    Text("Width:height, such as 4:5 or 3:2")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if CropGeometry.ratio(customRatio) == nil {
                                        Text("Enter a positive ratio within the document size limits.")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                    HStack {
                                        Button("Cancel") { showsCustomRatio = false }
                                        Spacer()
                                        Button("Apply") { applyCustomRatio() }
                                            .disabled(CropGeometry.ratio(customRatio) == nil)
                                    }
                                }.padding(16).frame(width: 280)
                            }
                    }

                    Picker("Overlay", selection: $session.cropOverlayStyle) {
                        ForEach(CropOverlayStyle.allCases, id: \.self) { style in
                            Text(L10n.text(style.rawValue)).tag(style)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                    .help("Crop composition overlay guides")

                    if !session.cropPerspectiveMode {
                        Button {
                            session.cropStraightening.toggle()
                        } label: {
                            Label("Straighten", systemImage: "level")
                        }
                        .tint(session.cropStraightening ? .accentColor : nil)
                        .help("Drag along a tilted horizon or vertical edge to straighten")

                        HStack(spacing: 4) {
                            AppSlider(value: $session.cropAngle, in: -45...45)
                                .frame(width: 80).accessibilityLabel("Angle")
                            Text(String(format: "%.1f°", session.cropAngle))
                                .monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                        .help("Crop rotation angle (-45° to 45°)")

                        Toggle("Delete Cropped Pixels", isOn: $session.deleteCroppedPixels)
                            .toggleStyle(.checkbox).fixedSize()
                            .help("When unchecked, cropped pixels outside the canvas stay intact for later adjustment")
                    }

                    Button {
                        session.togglePerspectiveCrop()
                    } label: {
                        Label("Perspective", systemImage: "perspective")
                    }
                    .tint(session.cropPerspectiveMode ? .accentColor : nil)
                    .help("Drag 4 corners to rectify perspective distortion")

                    if session.cropPerspectiveMode, let size = session.perspectiveCropQuad?.outputSize {
                        Text("\(Int(size.width)) × \(Int(size.height)) px").monospacedDigit()
                    } else if let rect = session.cropRect {
                        Text("\(Int(rect.width)) × \(Int(rect.height)) px").monospacedDigit()
                    }
                }
            }.scrollIndicators(.never)
            Spacer(minLength: 0)
            Button("Cancel") { session.cancelCrop() }.disabled(!session.hasPendingCrop)
            Button("Apply Crop") { Task { await session.commitCrop() } }
                .disabled(!session.hasPendingCrop)
        }.padding(.horizontal, 18).toolHeaderBar().disabled(session.showsBusy || session.document == nil)
    }

    private var ratioSelection: Binding<String> {
        Binding(get: { session.cropRatioChoice }, set: { choice in
            if choice == "Custom" {
                if CropGeometry.ratio(session.cropRatioChoice) != nil { customRatio = session.cropRatioChoice }
                showsCustomRatio = true
            } else {
                session.cropRatioChoice = choice
                session.changeCropRatio()
            }
        })
    }

    private func applyCustomRatio() {
        guard CropGeometry.ratio(customRatio) != nil else { return }
        session.cropRatioChoice = customRatio.split(separator: ":").map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        }.joined(separator: ":")
        session.changeCropRatio()
        showsCustomRatio = false
    }
}
