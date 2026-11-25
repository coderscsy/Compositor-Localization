import SwiftUI
import AppKit

/// Photoshop-style Blending Options (Blend If) floating panel with live canvas preview.
struct BlendIfSheet: View {
    @Bindable var session: EditorSession

    private var settings: BlendIfSettings {
        session.blendIfEdit?.settings ?? BlendIfSettings()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Blend If:").font(.callout)
                Picker("Blend If Channel", selection: Binding(
                    get: { settings.channel },
                    set: { update { $0.channel = $1 } ($0) }
                )) {
                    ForEach(BlendIfChannel.allCases, id: \.self) { channel in
                        Text(L10n.text(channel.rawValue)).tag(channel)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                Spacer()
            }

            BlendIfRangeControl(
                title: L10n.text("This Layer"),
                channel: settings.channel,
                range: Binding(
                    get: { settings.thisLayer },
                    set: { value in
                        var next = settings
                        next.thisLayer = value.normalized
                        session.updateBlendIf(next)
                    }
                )
            )

            BlendIfRangeControl(
                title: L10n.text("Underlying Layer"),
                channel: settings.channel,
                range: Binding(
                    get: { settings.underlyingLayer },
                    set: { value in
                        var next = settings
                        next.underlyingLayer = value.normalized
                        session.updateBlendIf(next)
                    }
                )
            )

            Text("Option-drag a handle to split it for smooth feathering.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Reset") { session.resetBlendIf() }
                    .disabled(settings.isIdentity)
                Spacer()
                Button("Cancel") { session.cancelBlendIf() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { session.commitBlendIf() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func update<T>(_ apply: @escaping (inout BlendIfSettings, T) -> Void) -> (T) -> Void {
        { value in
            var next = settings
            apply(&next, value)
            session.updateBlendIf(next)
        }
    }
}

private struct BlendIfRangeControl: View {
    let title: String
    let channel: BlendIfChannel
    @Binding var range: BlendIfRange

    private enum Handle { case blackLow, blackHigh, whiteLow, whiteHigh }
    @State private var activeHandle: Handle?

    private var gradientColors: [Color] {
        switch channel {
        case .gray: [.black, .white]
        case .red: [.black, .red]
        case .green: [.black, .green]
        case .blue: [.black, .blue]
        }
    }

    private var blackLabel: String {
        range.blackLow == range.blackHigh ? "\(range.blackLow)" : "\(range.blackLow) / \(range.blackHigh)"
    }

    private var whiteLabel: String {
        range.whiteLow == range.whiteHigh ? "\(range.whiteHigh)" : "\(range.whiteLow) / \(range.whiteHigh)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Text("\(blackLabel)  –  \(whiteLabel)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1))
                        .frame(height: 16)

                    handleView(value: range.blackLow, width: width, isBlack: true, half: range.blackLow != range.blackHigh ? .left : .full)
                    if range.blackHigh != range.blackLow {
                        handleView(value: range.blackHigh, width: width, isBlack: true, half: .right)
                    }
                    if range.whiteLow != range.whiteHigh {
                        handleView(value: range.whiteLow, width: width, isBlack: false, half: .left)
                    }
                    handleView(value: range.whiteHigh, width: width, isBlack: false, half: range.whiteLow != range.whiteHigh ? .right : .full)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let pos = Int(((value.location.x / width) * 255).rounded())
                            let clamped = min(255, max(0, pos))
                            let optionHeld = NSEvent.modifierFlags.contains(.option)
                            if activeHandle == nil {
                                activeHandle = pickHandle(at: clamped, optionHeld: optionHeld)
                            }
                            applyDrag(to: clamped, optionHeld: optionHeld)
                        }
                        .onEnded { _ in activeHandle = nil }
                )
            }
            .frame(height: 30)
        }
    }

    fileprivate enum Half { case full, left, right }

    private func handleView(value: Int, width: CGFloat, isBlack: Bool, half: Half) -> some View {
        let x = (CGFloat(value) / 255.0) * width
        return HandleTriangle(half: half)
            .fill(isBlack ? Color.black : Color.white)
            .overlay(HandleTriangle(half: half).stroke(Color.primary.opacity(0.75), lineWidth: 1))
            .frame(width: 10, height: 10)
            .offset(x: x - 5, y: 18)
    }

    private func pickHandle(at value: Int, optionHeld: Bool) -> Handle {
        let blackSplit = range.blackLow != range.blackHigh
        let whiteSplit = range.whiteLow != range.whiteHigh
        var candidates: [(Handle, Int)] = []
        if blackSplit {
            candidates.append((.blackLow, range.blackLow))
            candidates.append((.blackHigh, range.blackHigh))
        } else {
            candidates.append((optionHeld ? .blackHigh : .blackLow, range.blackLow))
        }
        if whiteSplit {
            candidates.append((.whiteLow, range.whiteLow))
            candidates.append((.whiteHigh, range.whiteHigh))
        } else {
            candidates.append((optionHeld ? .whiteLow : .whiteHigh, range.whiteHigh))
        }
        return candidates.min(by: { abs($0.1 - value) < abs($1.1 - value) })?.0 ?? .blackLow
    }

    private func applyDrag(to value: Int, optionHeld: Bool) {
        guard let handle = activeHandle else { return }
        var next = range
        switch handle {
        case .blackLow:
            let wasJoined = !optionHeld && next.blackLow == next.blackHigh
            if wasJoined {
                let target = min(value, next.whiteLow)
                next.blackLow = target
                next.blackHigh = target
            } else {
                next.blackLow = min(value, next.blackHigh)
            }
        case .blackHigh:
            next.blackHigh = min(max(value, next.blackLow), next.whiteLow)
        case .whiteLow:
            next.whiteLow = max(min(value, next.whiteHigh), next.blackHigh)
        case .whiteHigh:
            let wasJoined = !optionHeld && next.whiteLow == next.whiteHigh
            if wasJoined {
                let target = max(value, next.blackHigh)
                next.whiteLow = target
                next.whiteHigh = target
            } else {
                next.whiteHigh = max(value, next.whiteLow)
            }
        }
        range = next.normalized
    }
}

private struct HandleTriangle: Shape {
    let half: Half
    enum Half { case full, left, right }
    init(half: BlendIfRangeControl.Half) {
        switch half {
        case .full: self.half = .full
        case .left: self.half = .left
        case .right: self.half = .right
        }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch half {
        case .full:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .left:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .right:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
