import AppKit

/// An 8-bit brush mask in top-to-bottom rows. Zero is empty, and 255 is full coverage.
nonisolated struct BrushTip: Codable, Equatable, Sendable {
    static let maximumDimension = 4096

    let width: Int
    let height: Int
    let coverage: Data

    init?(width: Int, height: Int, coverage: Data) {
        guard (1...Self.maximumDimension).contains(width), (1...Self.maximumDimension).contains(height),
              coverage.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.coverage = coverage
    }

    private enum CodingKeys: String, CodingKey { case width, height, coverage }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let width = try values.decode(Int.self, forKey: .width)
        let height = try values.decode(Int.self, forKey: .height)
        let coverage = try values.decode(Data.self, forKey: .coverage)
        guard let tip = Self(width: width, height: height, coverage: coverage) else {
            throw DecodingError.dataCorruptedError(forKey: .coverage, in: values, debugDescription: "Invalid brush tip dimensions or coverage")
        }
        self = tip
    }

    var image: CGImage? {
        guard let provider = CGDataProvider(data: coverage as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
