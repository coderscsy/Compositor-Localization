import Foundation

nonisolated struct BrushPreset: Codable, Identifiable, Sendable {
    static let defaultID = "hard-round"

    let id: String
    let name: String
    let isBuiltIn: Bool
    let tip: BrushTip?
    let diameter: CGFloat
    let hardness: CGFloat
    let opacity: CGFloat
    let smoothing: CGFloat
    let pressureSize: Bool
    let pressureOpacity: Bool
    let antialiased: Bool
    let spacing: CGFloat?
    let flow: CGFloat
    let angle: CGFloat
    let roundness: CGFloat
    let scatter: CGFloat
    let sizeJitter: CGFloat
    let angleJitter: CGFloat
    let opacityJitter: CGFloat
    let scatterCount: Int
    let scatterBothAxes: Bool
    let airbrush: Bool

    var displayName: String { isBuiltIn ? L10n.text(name) : name }

    init(id: String = UUID().uuidString, name: String, isBuiltIn: Bool = false, settings: BrushSettings) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        tip = settings.tip
        diameter = settings.diameter
        hardness = settings.hardness
        opacity = settings.opacity
        smoothing = settings.smoothing
        pressureSize = settings.pressureSize
        pressureOpacity = settings.pressureOpacity
        antialiased = settings.antialiased
        spacing = settings.spacing
        flow = settings.flow
        angle = settings.angle
        roundness = settings.roundness
        scatter = settings.scatter
        sizeJitter = settings.sizeJitter
        angleJitter = settings.angleJitter
        opacityJitter = settings.opacityJitter
        scatterCount = settings.scatterCount
        scatterBothAxes = settings.scatterBothAxes
        airbrush = settings.airbrush
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isBuiltIn, tip, diameter, hardness, opacity, smoothing
        case pressureSize, pressureOpacity, antialiased, spacing, flow, angle, roundness
        case scatter, sizeJitter, angleJitter, opacityJitter, scatterCount, scatterBothAxes, airbrush
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isBuiltIn = try c.decode(Bool.self, forKey: .isBuiltIn)
        tip = try c.decodeIfPresent(BrushTip.self, forKey: .tip)
        diameter = try c.decode(CGFloat.self, forKey: .diameter)
        hardness = try c.decode(CGFloat.self, forKey: .hardness)
        opacity = try c.decode(CGFloat.self, forKey: .opacity)
        smoothing = try c.decode(CGFloat.self, forKey: .smoothing)
        pressureSize = try c.decode(Bool.self, forKey: .pressureSize)
        pressureOpacity = try c.decode(Bool.self, forKey: .pressureOpacity)
        antialiased = try c.decode(Bool.self, forKey: .antialiased)
        spacing = try c.decodeIfPresent(CGFloat.self, forKey: .spacing)
        flow = try c.decode(CGFloat.self, forKey: .flow)
        angle = try c.decode(CGFloat.self, forKey: .angle)
        roundness = try c.decode(CGFloat.self, forKey: .roundness)
        scatter = try c.decode(CGFloat.self, forKey: .scatter)
        sizeJitter = try c.decode(CGFloat.self, forKey: .sizeJitter)
        angleJitter = try c.decode(CGFloat.self, forKey: .angleJitter)
        opacityJitter = try c.decode(CGFloat.self, forKey: .opacityJitter)
        scatterCount = try c.decode(Int.self, forKey: .scatterCount)
        scatterBothAxes = try c.decode(Bool.self, forKey: .scatterBothAxes)
        airbrush = try c.decodeIfPresent(Bool.self, forKey: .airbrush) ?? false
    }

    func apply(to settings: inout BrushSettings) {
        // The foreground color and the Brush/Eraser mode belong to the current tool.
        let defaults = BrushSettings()
        settings.tip = tip
        settings.diameter = Self.clamped(diameter, to: 1...2000, fallback: defaults.diameter)
        settings.hardness = Self.clamped(hardness, to: 0...1, fallback: defaults.hardness)
        settings.opacity = Self.clamped(opacity, to: 0.01...1, fallback: defaults.opacity)
        settings.smoothing = Self.clamped(smoothing, to: 0...100, fallback: defaults.smoothing)
        settings.pressureSize = pressureSize
        settings.pressureOpacity = pressureOpacity
        settings.antialiased = antialiased
        settings.spacing = spacing.map { Self.clamped($0, to: 0.01...10, fallback: 0.25) }
        settings.flow = Self.clamped(flow, to: 0...1, fallback: defaults.flow)
        settings.angle = Self.clamped(angle, to: -360...360, fallback: defaults.angle)
        settings.roundness = Self.clamped(roundness, to: 0.01...1, fallback: defaults.roundness)
        settings.scatter = Self.clamped(scatter, to: 0...10, fallback: defaults.scatter)
        settings.sizeJitter = Self.clamped(sizeJitter, to: 0...1, fallback: defaults.sizeJitter)
        settings.angleJitter = Self.clamped(angleJitter, to: 0...1, fallback: defaults.angleJitter)
        settings.opacityJitter = Self.clamped(opacityJitter, to: 0...1, fallback: defaults.opacityJitter)
        settings.scatterCount = min(16, max(1, scatterCount))
        settings.scatterBothAxes = scatterBothAxes
        settings.airbrush = airbrush
    }

    private static func clamped(_ value: CGFloat, to range: ClosedRange<CGFloat>, fallback: CGFloat) -> CGFloat {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }

    static var builtIn: [BrushPreset] { builtIns }

    static let builtIns: [BrushPreset] = {
        let hard = BrushSettings()
        var soft = hard
        soft.hardness = 0
        var airbrushSoft = soft
        airbrushSoft.diameter = 80
        airbrushSoft.flow = 0.20
        airbrushSoft.spacing = 0.12
        airbrushSoft.airbrush = true
        var chisel = hard
        chisel.roundness = 0.24
        chisel.angle = 30
        chisel.spacing = 0.10
        var grain = hard
        grain.tip = texturedTip(flecks: false)
        grain.spacing = 0.22
        grain.flow = 0.55
        var flecks = hard
        flecks.tip = texturedTip(flecks: true)
        flecks.spacing = 0.35
        flecks.scatter = 0.16
        return [
            .init(id: defaultID, name: "Hard Round", isBuiltIn: true, settings: hard),
            .init(id: "soft-round", name: "Soft Round", isBuiltIn: true, settings: soft),
            .init(id: "airbrush-soft", name: "Airbrush Soft", isBuiltIn: true, settings: airbrushSoft),
            .init(id: "chisel", name: "Chisel", isBuiltIn: true, settings: chisel),
            .init(id: "grain", name: "Grain", isBuiltIn: true, settings: grain),
            .init(id: "ink-flecks", name: "Ink Flecks", isBuiltIn: true, settings: flecks)
        ]
    }()

    private static func texturedTip(flecks: Bool) -> BrushTip? {
        let side = 64
        var bytes = Data(capacity: side * side)
        var noise: UInt32 = flecks ? 2909 : 2153
        for y in 0..<side {
            for x in 0..<side {
                let u = (Double(x) + 0.5) * 2 / Double(side) - 1
                let v = (Double(y) + 0.5) * 2 / Double(side) - 1
                let edge = max(0, 1 - hypot(u, v))
                noise = noise &* 1_664_525 &+ 1_013_904_223
                let sample = Double(noise >> 24) / 255
                let coverage = flecks ? max(0, sample - 0.83) * 5 * min(1, edge * 2)
                    : sample * min(1, edge * 3)
                bytes.append(UInt8((255 * coverage).rounded()))
            }
        }
        return BrushTip(width: side, height: side, coverage: bytes)
    }
}
