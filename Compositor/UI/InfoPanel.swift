import SwiftUI

struct InfoPanel: View {
    @Bindable var session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Color readouts under cursor
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RGB").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    if let info = session.pointerInfo {
                        readout("R", "\(info.r)")
                        readout("G", "\(info.g)")
                        readout("B", "\(info.b)")
                        readout("A", "\(info.a)")
                        Text(info.hex).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    } else {
                        readout("R", "—"); readout("G", "—"); readout("B", "—"); readout("A", "—")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text("CMYK").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    if let cmyk = session.pointerInfo?.cmyk {
                        readout("C", "\(cmyk.c)%")
                        readout("M", "\(cmyk.m)%")
                        readout("Y", "\(cmyk.y)%")
                        readout("K", "\(cmyk.k)%")
                    } else {
                        readout("C", "—"); readout("M", "—"); readout("Y", "—"); readout("K", "—")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text("HSB").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    if let hsb = session.pointerInfo?.hsb {
                        readout("H", "\(hsb.h)°")
                        readout("S", "\(hsb.s)%")
                        readout("B", "\(hsb.b)%")
                    } else {
                        readout("H", "—"); readout("S", "—"); readout("B", "—")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Coordinates & active region dimensions
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cursor").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    if let pt = session.pointerInfo?.point {
                        readout("X", "\(Int(pt.x.rounded())) px")
                        readout("Y", "\(Int(pt.y.rounded())) px")
                    } else {
                        readout("X", "—"); readout("Y", "—")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Selection / Crop").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    if let crop = session.cropRect {
                        readout("W", "\(Int(crop.width.rounded())) px")
                        readout("H", "\(Int(crop.height.rounded())) px")
                    } else if let sel = session.selection, !sel.isEmpty {
                        let b = sel.path.boundingBoxOfPath
                        readout("W", "\(Int(b.width.rounded())) px")
                        readout("H", "\(Int(b.height.rounded())) px")
                    } else {
                        readout("W", "—"); readout("H", "—")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Document summary
            if let doc = session.document {
                let is16Bit = doc.layers.contains { $0.asset?.deep != nil }
                HStack {
                    Text("\(doc.width) × \(doc.height) px · \(Int(doc.resolution.rounded())) ppi")
                    Spacer()
                    Text(is16Bit ? "16-bit" : "8-bit")
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 270)
    }

    private func readout(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary).frame(width: 14, alignment: .leading)
            Text(value).font(.system(size: 11).monospacedDigit())
        }
    }
}
