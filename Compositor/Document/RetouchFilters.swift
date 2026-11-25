import AppKit
import CoreImage

// MARK: - Brightness / Contrast

nonisolated struct BrightnessContrastSettings: Codable, Equatable, Sendable {
    static let brightnessRange: ClosedRange<Double> = -150...150
    static let contrastRange: ClosedRange<Double> = -50...100

    var brightness: Double = 0
    var contrast: Double = 0
    var useLegacy = false

    var isValid: Bool {
        brightness.isFinite && Self.brightnessRange.contains(brightness)
            && contrast.isFinite && Self.contrastRange.contains(contrast)
    }

    var normalized: Self {
        Self(brightness: ImageAdjustmentPixels.clamp(brightness, Self.brightnessRange, 0),
             contrast: ImageAdjustmentPixels.clamp(contrast, Self.contrastRange, 0),
             useLegacy: useLegacy)
    }

    func apply(_ image: CGImage) throws -> CGImage {
        guard isValid else { throw ProjectError.invalid }
        return try ImageAdjustmentPixels.run(image) { pixels, width, height, stride in
            adjust_brightness_contrast(pixels, width, height, stride,
                                       Float(brightness), Float(contrast), useLegacy ? 1 : 0)
        }
    }
}

// MARK: - Vibrance

nonisolated struct VibranceSettings: Codable, Equatable, Sendable {
    static let range: ClosedRange<Double> = -100...100

    var vibrance: Double = 0
    var saturation: Double = 0

    var isValid: Bool {
        vibrance.isFinite && Self.range.contains(vibrance)
            && saturation.isFinite && Self.range.contains(saturation)
    }

    var normalized: Self {
        Self(vibrance: ImageAdjustmentPixels.clamp(vibrance, Self.range, 0),
             saturation: ImageAdjustmentPixels.clamp(saturation, Self.range, 0))
    }

    func apply(_ image: CGImage) throws -> CGImage {
        guard isValid else { throw ProjectError.invalid }
        return try ImageAdjustmentPixels.run(image) { pixels, width, height, stride in
            adjust_vibrance(pixels, width, height, stride, Float(vibrance), Float(saturation))
        }
    }
}

// MARK: - Threshold

nonisolated struct ThresholdSettings: Codable, Equatable, Sendable {
    static let range: ClosedRange<Double> = 1...255

    var level: Double = 128

    var isValid: Bool { level.isFinite && Self.range.contains(level) }

    var normalized: Self {
        Self(level: ImageAdjustmentPixels.clamp(level.rounded(), Self.range, 128))
    }

    func apply(_ image: CGImage) throws -> CGImage {
        guard isValid else { throw ProjectError.invalid }
        return try ImageAdjustmentPixels.run(image) { pixels, width, height, stride in
            adjust_threshold(pixels, width, height, stride, Int32(level.rounded()))
        }
    }
}

// MARK: - Posterize

nonisolated struct PosterizeSettings: Codable, Equatable, Sendable {
    static let range: ClosedRange<Double> = 2...255

    var levels: Double = 4

    var isValid: Bool { levels.isFinite && Self.range.contains(levels) }

    var normalized: Self {
        Self(levels: ImageAdjustmentPixels.clamp(levels.rounded(), Self.range, 4))
    }

    func apply(_ image: CGImage) throws -> CGImage {
        guard isValid else { throw ProjectError.invalid }
        return try ImageAdjustmentPixels.run(image) { pixels, width, height, stride in
            adjust_posterize(pixels, width, height, stride, Int32(levels.rounded()))
        }
    }
}

// MARK: - Selective Color

nonisolated enum SelectiveColorFamily: String, CaseIterable, Codable, Sendable {
    case reds = "Reds"
    case yellows = "Yellows"
    case greens = "Greens"
    case cyans = "Cyans"
    case blues = "Blues"
    case magentas = "Magentas"
    case whites = "Whites"
    case neutrals = "Neutrals"
    case blacks = "Blacks"

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

nonisolated struct SelectiveColorAdjust: Codable, Equatable, Sendable {
    static let range: ClosedRange<Double> = -100...100

    var cyan: Double = 0
    var magenta: Double = 0
    var yellow: Double = 0
    var black: Double = 0

    var isValid: Bool {
        [cyan, magenta, yellow, black].allSatisfy { $0.isFinite && Self.range.contains($0) }
    }

    var normalized: Self {
        Self(cyan: ImageAdjustmentPixels.clamp(cyan, Self.range, 0),
             magenta: ImageAdjustmentPixels.clamp(magenta, Self.range, 0),
             yellow: ImageAdjustmentPixels.clamp(yellow, Self.range, 0),
             black: ImageAdjustmentPixels.clamp(black, Self.range, 0))
    }
}

nonisolated struct SelectiveColorSettings: Codable, Equatable, Sendable {
    var reds = SelectiveColorAdjust()
    var yellows = SelectiveColorAdjust()
    var greens = SelectiveColorAdjust()
    var cyans = SelectiveColorAdjust()
    var blues = SelectiveColorAdjust()
    var magentas = SelectiveColorAdjust()
    var whites = SelectiveColorAdjust()
    var neutrals = SelectiveColorAdjust()
    var blacks = SelectiveColorAdjust()
    /// Relative scales changes by existing ink headroom; Absolute adds ink linearly.
    var relative = true

    subscript(family: SelectiveColorFamily) -> SelectiveColorAdjust {
        get {
            switch family {
            case .reds: reds
            case .yellows: yellows
            case .greens: greens
            case .cyans: cyans
            case .blues: blues
            case .magentas: magentas
            case .whites: whites
            case .neutrals: neutrals
            case .blacks: blacks
            }
        }
        set {
            switch family {
            case .reds: reds = newValue
            case .yellows: yellows = newValue
            case .greens: greens = newValue
            case .cyans: cyans = newValue
            case .blues: blues = newValue
            case .magentas: magentas = newValue
            case .whites: whites = newValue
            case .neutrals: neutrals = newValue
            case .blacks: blacks = newValue
            }
        }
    }

    var isValid: Bool {
        SelectiveColorFamily.allCases.allSatisfy { self[$0].isValid }
    }

    var normalized: Self {
        var result = self
        for family in SelectiveColorFamily.allCases { result[family] = result[family].normalized }
        return result
    }

    func apply(_ image: CGImage) throws -> CGImage {
        guard isValid else { throw ProjectError.invalid }
        var table = [Float]()
        table.reserveCapacity(9 * 4)
        for family in SelectiveColorFamily.allCases {
            let adj = self[family]
            table.append(Float(adj.cyan / 100))
            table.append(Float(adj.magenta / 100))
            table.append(Float(adj.yellow / 100))
            table.append(Float(adj.black / 100))
        }
        return try ImageAdjustmentPixels.run(image) { pixels, width, height, stride in
            adjust_selective_color(pixels, width, height, stride, table, relative ? 1 : 0)
        }
    }
}

// MARK: - Color Lookup (3D LUT)

nonisolated enum ColorLookupPreset: String, CaseIterable, Codable, Sendable {
    case none = "None"
    case tealOrange = "Teal & Orange"
    case warmFilm = "Warm Film"
    case coolMatte = "Cool Matte"
    case bleachBypass = "Bleach Bypass"
    case crispWinter = "Crisp Winter"
    case custom = "Custom .cube"

    /// Built-in presets shown in the menu; `.custom` appears once a `.cube` file is loaded.
    static let builtIn: [Self] = [.none, .tealOrange, .warmFilm, .coolMatte, .bleachBypass, .crispWinter]

    /// Evaluates a built-in look analytically to synthesize a 17^3 3D LUT cube.
    func cubeTable(dimension: Int = 17) -> [Float]? {
        guard self != .none && self != .custom else { return nil }
        let n = dimension
        let denom = Float(n - 1)
        var data = [Float]()
        data.reserveCapacity(n * n * n * 3)
        func clamp01(_ v: Float) -> Float { min(1, max(0, v)) }
        for bi in 0..<n {
            let b = Float(bi) / denom
            for gi in 0..<n {
                let g = Float(gi) / denom
                for ri in 0..<n {
                    let r = Float(ri) / denom
                    let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    var outR = r, outG = g, outB = b
                    switch self {
                    case .tealOrange:
                        let shadow = (1 - lum) * (1 - lum)
                        let high = lum * lum
                        outR = clamp01(r + high * 0.14 - shadow * 0.12)
                        outG = clamp01(g + high * 0.04 + shadow * 0.03)
                        outB = clamp01(b - high * 0.12 + shadow * 0.14)
                    case .warmFilm:
                        let s = lum * lum * (3 - 2 * lum)
                        let lift: Float = 0.035
                        outR = clamp01((r + (s - lum) * 0.20) * 1.05 + lift)
                        outG = clamp01((g + (s - lum) * 0.20) * 1.01 + lift * 0.85)
                        outB = clamp01((b + (s - lum) * 0.20) * 0.90 + lift * 0.65)
                    case .coolMatte:
                        let lift: Float = 0.06
                        let compress: Float = 0.88
                        outR = clamp01(r * compress * 0.94 + lift * 0.85)
                        outG = clamp01(g * compress * 0.99 + lift * 0.98)
                        outB = clamp01(b * compress * 1.08 + lift * 1.15)
                    case .bleachBypass:
                        let desatR = lum + (r - lum) * 0.42
                        let desatG = lum + (g - lum) * 0.42
                        let desatB = lum + (b - lum) * 0.42
                        func contrast(_ v: Float) -> Float {
                            let s = v * v * (3 - 2 * v)
                            return clamp01(v + (s - v) * 0.75)
                        }
                        outR = contrast(desatR)
                        outG = contrast(desatG)
                        outB = contrast(desatB)
                    case .crispWinter:
                        let high = lum * lum
                        outR = clamp01(r * 0.95 + high * 0.03)
                        outG = clamp01(g * 1.01 + high * 0.04)
                        outB = clamp01(b * 1.10 + (1 - lum) * 0.06)
                    case .none, .custom:
                        break
                    }
                    data.append(outR); data.append(outG); data.append(outB)
                }
            }
        }
        return data
    }
}

/// Parses standard Adobe / Resolve `.cube` 3D LUT text files.
nonisolated enum ColorLookupParser {
    enum ParseError: LocalizedError {
        case invalidFormat
        var errorDescription: String? {
            L10n.text("This file is not a valid 3D .cube LUT (supported sizes: 2 to 65).")
        }
    }

    static func parse(_ text: String, fallbackTitle: String = "Custom LUT") throws -> (title: String, dimension: Int, table: [Float]) {
        var title = fallbackTitle
        var dimension = 0
        var domainMin: [Float] = [0, 0, 0]
        var domainMax: [Float] = [1, 1, 1]
        var values: [Float] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("TITLE") {
                let rest = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                let cleaned = rest.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !cleaned.isEmpty { title = String(cleaned.prefix(120)) }
                continue
            }
            if line.hasPrefix("LUT_3D_SIZE") {
                let parts = line.split(whereSeparator: \.isWhitespace)
                guard parts.count >= 2, let size = Int(parts[1]), (2...65).contains(size) else {
                    throw ParseError.invalidFormat
                }
                dimension = size
                values.reserveCapacity(size * size * size * 3)
                continue
            }
            if line.hasPrefix("DOMAIN_MIN") {
                let parts = line.split(whereSeparator: \.isWhitespace).dropFirst().compactMap { Float($0) }
                if parts.count == 3 { domainMin = parts }
                continue
            }
            if line.hasPrefix("DOMAIN_MAX") {
                let parts = line.split(whereSeparator: \.isWhitespace).dropFirst().compactMap { Float($0) }
                if parts.count == 3 { domainMax = parts }
                continue
            }
            if line.hasPrefix("LUT_1D_SIZE") {
                // Only 3D LUTs are supported here.
                throw ParseError.invalidFormat
            }
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3,
                  let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]),
                  r.isFinite, g.isFinite, b.isFinite else { continue }
            let nr = (domainMax[0] > domainMin[0]) ? (r - domainMin[0]) / (domainMax[0] - domainMin[0]) : r
            let ng = (domainMax[1] > domainMin[1]) ? (g - domainMin[1]) / (domainMax[1] - domainMin[1]) : g
            let nb = (domainMax[2] > domainMin[2]) ? (b - domainMin[2]) / (domainMax[2] - domainMin[2]) : b
            values.append(min(1, max(0, nr)))
            values.append(min(1, max(0, ng)))
            values.append(min(1, max(0, nb)))
        }

        guard (2...65).contains(dimension), values.count == dimension * dimension * dimension * 3 else {
            throw ParseError.invalidFormat
        }
        return (title, dimension, values)
    }
}

nonisolated struct ColorLookupSettings: Codable, Equatable, Sendable {
    static let intensityRange: ClosedRange<Double> = 0...100

    var preset: ColorLookupPreset = .none
    var title: String? = nil
    var dimension: Int? = nil
    /// Compact base64-encoded UInt16 RGB cube table (0...65535) when `preset == .custom`.
    var customCubeBase64: String? = nil
    var intensity: Double = 100

    var isValid: Bool {
        guard intensity.isFinite && Self.intensityRange.contains(intensity) else { return false }
        if preset == .custom {
            guard let dim = dimension, (2...65).contains(dim),
                  let base64 = customCubeBase64, let raw = Data(base64Encoded: base64),
                  raw.count == dim * dim * dim * 3 * MemoryLayout<UInt16>.size else { return false }
        }
        return true
    }

    var normalized: Self {
        var result = self
        result.intensity = ImageAdjustmentPixels.clamp(intensity, Self.intensityRange, 100)
        if result.preset != .custom {
            result.dimension = nil
            result.customCubeBase64 = nil
            result.title = nil
        }
        return result
    }

    mutating func setCustomLUT(title: String, dimension: Int, table: [Float]) {
        guard (2...65).contains(dimension), table.count == dimension * dimension * dimension * 3 else { return }
        var packed = [UInt16]()
        packed.reserveCapacity(table.count)
        for v in table {
            packed.append(UInt16(min(65535, max(0, Int((v * 65535).rounded())))))
        }
        let data = packed.withUnsafeBufferPointer { Data(buffer: $0) }
        self.preset = .custom
        self.title = title
        self.dimension = dimension
        self.customCubeBase64 = data.base64EncodedString()
    }

    func resolvedCube() -> (dimension: Int, table: [Float])? {
        if preset == .none { return nil }
        if preset == .custom {
            guard let dim = dimension, (2...65).contains(dim),
                  let base64 = customCubeBase64, let raw = Data(base64Encoded: base64),
                  raw.count == dim * dim * dim * 3 * MemoryLayout<UInt16>.size else { return nil }
            let count = dim * dim * dim * 3
            var floats = [Float](repeating: 0, count: count)
            raw.withUnsafeBytes { buffer in
                let words = buffer.bindMemory(to: UInt16.self)
                for i in 0..<count { floats[i] = Float(words[i]) / 65535.0 }
            }
            return (dim, floats)
        }
        guard let table = preset.cubeTable(dimension: 17) else { return nil }
        return (17, table)
    }

    func apply(_ image: CGImage) throws -> CGImage {
        guard isValid else { throw ProjectError.invalid }
        guard intensity > 0, let resolved = resolvedCube() else { return image }
        return try ImageAdjustmentPixels.run(image) { pixels, width, height, stride in
            adjust_color_lut(pixels, width, height, stride, resolved.table, Int32(resolved.dimension), Float(intensity / 100))
        }
    }
}

// MARK: - High Pass

nonisolated struct HighPassLayerSettings: Codable, Equatable, Sendable {
    static let radiusRange: ClosedRange<Double> = 0.1...250

    var radius: Double = 10

    init(radius: Double = 10) { self.radius = radius }

    init(_ settings: FilterSettings) {
        self.radius = settings.normalized.highPassRadius
    }

    func applied(to settings: FilterSettings) -> FilterSettings {
        var next = settings
        next.highPassRadius = radius
        return next
    }

    var isValid: Bool { radius.isFinite && Self.radiusRange.contains(radius) }
}

// MARK: - Offset

nonisolated enum OffsetEdgeMode: String, CaseIterable, Codable, Sendable {
    case wrapAround = "Wrap Around"
    case repeatEdge = "Repeat Edge Pixels"
    case transparent = "Set to Transparent"

    var kernelValue: Int32 {
        switch self {
        case .wrapAround: 0
        case .repeatEdge: 1
        case .transparent: 2
        }
    }
}

nonisolated struct OffsetSettings: Codable, Equatable, Sendable {
    static let range: ClosedRange<Double> = -10_000...10_000

    var horizontal: Double = 0
    var vertical: Double = 0
    var edgeMode: OffsetEdgeMode = .wrapAround

    var isValid: Bool {
        horizontal.isFinite && Self.range.contains(horizontal)
            && vertical.isFinite && Self.range.contains(vertical)
    }

    var normalized: Self {
        Self(horizontal: ImageAdjustmentPixels.clamp(horizontal.rounded(), Self.range, 0),
             vertical: ImageAdjustmentPixels.clamp(vertical.rounded(), Self.range, 0),
             edgeMode: edgeMode)
    }

    func apply(_ image: CGImage, scale: CGFloat = 1) throws -> CGImage {
        guard isValid else { throw ProjectError.invalid }
        let dx = Int32((horizontal * scale).rounded())
        let dy = Int32((vertical * scale).rounded())
        guard dx != 0 || dy != 0 else { return image }
        let width = image.width, height = image.height
        let source = try BrushRaster.context(width: width, height: height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), mask: false, context: source)
        let dest = try BrushRaster.context(width: width, height: height, mask: false)
        guard let srcData = source.data, let dstData = dest.data else { throw ExportError.render }
        filter_offset(srcData.assumingMemoryBound(to: UInt8.self), dstData.assumingMemoryBound(to: UInt8.self),
                      width, height, source.bytesPerRow, dest.bytesPerRow, dx, dy, edgeMode.kernelValue)
        guard let result = dest.makeImage() else { throw ExportError.render }
        return result
    }
}
