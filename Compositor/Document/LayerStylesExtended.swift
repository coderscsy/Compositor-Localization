import CoreGraphics
import Foundation

/// Blend modes available on individual Layer Styles (matching Photoshop's Layer Style blend choices).
nonisolated enum EffectBlendMode: String, Codable, CaseIterable, Sendable {
    case normal = "Normal"
    case multiply = "Multiply"
    case screen = "Screen"
    case overlay = "Overlay"
    case softLight = "Soft Light"
    case hardLight = "Hard Light"
    case darken = "Darken"
    case lighten = "Lighten"
    case colorDodge = "Color Dodge"
    case colorBurn = "Color Burn"
    case linearDodge = "Linear Dodge (Add)"

    var kernelIndex: Int32 {
        switch self {
        case .normal: 0
        case .multiply: 1
        case .screen: 2
        case .overlay: 3
        case .softLight: 4
        case .hardLight: 5
        case .darken: 6
        case .lighten: 7
        case .colorDodge: 8
        case .colorBurn: 9
        case .linearDodge: 10
        }
    }
}

/// Stroke placement relative to the layer's alpha boundary.
nonisolated enum StrokePosition: String, Codable, CaseIterable, Sendable {
    case outside = "Outside"
    case center = "Center"
    case inside = "Inside"
}

// MARK: - Bevel & Emboss

nonisolated enum BevelEmbossStyle: String, Codable, CaseIterable, Sendable {
    case innerBevel = "Inner Bevel"
    case outerBevel = "Outer Bevel"
    case emboss = "Emboss"
    case pillowEmboss = "Pillow Emboss"

    var kernelIndex: Int32 {
        switch self {
        case .innerBevel: 0
        case .outerBevel: 1
        case .emboss: 2
        case .pillowEmboss: 3
        }
    }
}

nonisolated enum BevelDirection: String, Codable, CaseIterable, Sendable {
    case up = "Up"
    case down = "Down"
}

nonisolated struct BevelEmbossEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var style: BevelEmbossStyle = .innerBevel
    var direction: BevelDirection = .up
    var depth: CGFloat = 100
    var size: CGFloat = 6
    var soften: CGFloat = 0
    var angle: CGFloat = 120
    var altitude: CGFloat = 30
    var highlightRed: CGFloat = 1
    var highlightGreen: CGFloat = 1
    var highlightBlue: CGFloat = 1
    var highlightOpacity: Double = 0.75
    var highlightBlendMode: EffectBlendMode = .screen
    var shadowRed: CGFloat = 0
    var shadowGreen: CGFloat = 0
    var shadowBlue: CGFloat = 0
    var shadowOpacity: Double = 0.75
    var shadowBlendMode: EffectBlendMode = .multiply

    var highlightColor: PaletteColor { PaletteColor(red: highlightRed, green: highlightGreen, blue: highlightBlue) }
    var shadowColor: PaletteColor { PaletteColor(red: shadowRed, green: shadowGreen, blue: shadowBlue) }

    var isValid: Bool {
        depth.isFinite && (1...1000).contains(depth)
            && size.isFinite && (0...250).contains(size)
            && soften.isFinite && (0...16).contains(soften)
            && angle.isFinite && (-360...360).contains(angle)
            && altitude.isFinite && (0...90).contains(altitude)
            && highlightOpacity.isFinite && (0...1).contains(highlightOpacity)
            && shadowOpacity.isFinite && (0...1).contains(shadowOpacity)
            && [highlightRed, highlightGreen, highlightBlue, shadowRed, shadowGreen, shadowBlue]
                .allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

// MARK: - Gradient Overlay

nonisolated struct GradientOverlayStop: Codable, Equatable, Sendable {
    var position: Double
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat = 1

    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }

    var isValid: Bool {
        position.isFinite && (0...1).contains(position)
            && [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

nonisolated enum GradientOverlayStyle: String, Codable, CaseIterable, Sendable {
    case linear = "Linear"
    case radial = "Radial"
    case angle = "Angle"
    case reflected = "Reflected"
    case diamond = "Diamond"

    var kernelIndex: Int32 {
        switch self {
        case .linear: 0
        case .radial: 1
        case .angle: 2
        case .reflected: 3
        case .diamond: 4
        }
    }
}

nonisolated struct GradientOverlayEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var style: GradientOverlayStyle = .linear
    var angle: CGFloat = 90
    var scale: CGFloat = 100
    var reverse: Bool = false
    var opacity: Double = 1
    var blendMode: EffectBlendMode = .normal
    var stops: [GradientOverlayStop] = [
        GradientOverlayStop(position: 0, red: 0, green: 0, blue: 0, alpha: 1),
        GradientOverlayStop(position: 1, red: 1, green: 1, blue: 1, alpha: 1),
    ]

    var startColor: PaletteColor { stops.first?.color ?? PaletteColor(red: 0, green: 0, blue: 0) }
    var endColor: PaletteColor { stops.last?.color ?? PaletteColor(red: 1, green: 1, blue: 1) }

    var isValid: Bool {
        angle.isFinite && (-360...360).contains(angle)
            && scale.isFinite && (10...150).contains(scale)
            && opacity.isFinite && (0...1).contains(opacity)
            && (2...16).contains(stops.count)
            && stops.allSatisfy(\.isValid)
    }

    var sortedStops: [StyleGradientStop] {
        stops.sorted { $0.position < $1.position }.map {
            StyleGradientStop(position: Float($0.position),
                              r: Float($0.red), g: Float($0.green), b: Float($0.blue), a: Float($0.alpha))
        }
    }
}

// MARK: - Pattern Overlay

nonisolated enum PatternPreset: String, Codable, CaseIterable, Sendable {
    case checkerboard = "Checkerboard"
    case stripes = "Stripes"
    case diagonalStripes = "Diagonal Stripes"
    case dots = "Polka Dots"
    case grid = "Grid"
    case crosshatch = "Crosshatch"
    case noise = "Fine Noise"

    var kernelIndex: Int32 {
        switch self {
        case .checkerboard: 0
        case .stripes: 1
        case .diagonalStripes: 2
        case .dots: 3
        case .grid: 4
        case .crosshatch: 5
        case .noise: 6
        }
    }
}

nonisolated struct PatternOverlayEffect: Codable, Equatable, Sendable {
    var enabled: Bool? = nil
    var isEnabled: Bool { enabled ?? true }
    var pattern: PatternPreset = .checkerboard
    var scale: CGFloat = 100
    var opacity: Double = 0.5
    var blendMode: EffectBlendMode = .normal
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0

    var color: PaletteColor { PaletteColor(red: red, green: green, blue: blue) }

    var isValid: Bool {
        scale.isFinite && (10...500).contains(scale)
            && opacity.isFinite && (0...1).contains(opacity)
            && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}
