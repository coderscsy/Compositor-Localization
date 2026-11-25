import SwiftUI

struct HistogramPanel: View {
    @Bindable var session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Channel", selection: $session.histogramChannel) {
                    ForEach(HistogramChannel.allCases, id: \.self) { ch in
                        Text(L10n.text(ch.rawValue)).tag(ch)
                    }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
                Spacer()
                Button {
                    Task { await session.refreshHistogram() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh histogram")
            }

            // Vector histogram plot
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.11))
                if let stats = session.histogramStats {
                    HistogramPlotCanvas(stats: stats, channel: session.histogramChannel)
                        .padding(4)
                } else {
                    Text("No image data").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(height: 120)

            // Statistical readouts
            if let stats = session.histogramStats {
                let summary = stats.summary(for: session.histogramChannel)
                HStack(spacing: 12) {
                    statItem("Mean", String(format: "%.1f", summary.mean))
                    statItem("Std Dev", String(format: "%.1f", summary.stdDev))
                    statItem("Median", "\(summary.median)")
                    statItem("Pixels", stats.pixelCount.formatted())
                }
            }
        }
        .padding(14)
        .frame(width: 270)
        .task(id: session.history.currentRevision) {
            await session.refreshHistogram()
        }
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text(label)).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistogramPlotCanvas: View {
    let stats: HistogramStats
    let channel: HistogramChannel

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            func drawCurve(_ bins: [Int], color: Color, peak: Int) {
                guard peak > 0 else { return }
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for i in 0..<256 {
                    let x = CGFloat(i) / 255.0 * size.width
                    let h = CGFloat(bins[i]) / CGFloat(peak) * size.height
                    path.addLine(to: CGPoint(x: x, y: size.height - h))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(color))
            }

            switch channel {
            case .colors:
                let peak = max(1, max(stats.red.max() ?? 1, max(stats.green.max() ?? 1, stats.blue.max() ?? 1)))
                drawCurve(stats.red, color: Color.red.opacity(0.45), peak: peak)
                drawCurve(stats.green, color: Color.green.opacity(0.45), peak: peak)
                drawCurve(stats.blue, color: Color.blue.opacity(0.45), peak: peak)
            case .red:
                drawCurve(stats.red, color: Color.red.opacity(0.75), peak: max(1, stats.red.max() ?? 1))
            case .green:
                drawCurve(stats.green, color: Color.green.opacity(0.75), peak: max(1, stats.green.max() ?? 1))
            case .blue:
                drawCurve(stats.blue, color: Color.blue.opacity(0.75), peak: max(1, stats.blue.max() ?? 1))
            case .luminosity:
                drawCurve(stats.luminosity, color: Color.white.opacity(0.78), peak: max(1, stats.luminosity.max() ?? 1))
            case .rgb:
                let bins = stats.bins(for: .rgb)
                drawCurve(bins, color: Color.white.opacity(0.75), peak: max(1, bins.max() ?? 1))
            }
        }
    }
}
