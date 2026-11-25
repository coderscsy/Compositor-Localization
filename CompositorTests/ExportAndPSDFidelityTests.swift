import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Compositor

@MainActor
struct ExportAndPSDFidelityTests {
    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        // BrushRaster.context uses top-left origin:
        // Top-left opaque red
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        // Top-right semi-transparent green
        context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height / 2))
        // Bottom-left opaque blue
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height - height / 2))
        // Bottom-right transparent
        return try #require(context.makeImage())
    }

    private func solid(_ width: Int, _ height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func rgbaPixel(in image: CGImage, x: Int, y: Int) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        let ctx = try #require(CGContext(data: &bytes, width: width, height: height,
                                         bitsPerComponent: 8, bytesPerRow: width * 4,
                                         space: colorSpace, bitmapInfo: info.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    @Test func webpLosslessRoundTripsPixelsAndAlpha() async throws {
        let source = try makeTestImage(width: 24, height: 16)
        let raster = ExportRaster(image: source, resolution: 72)
        let encoded = try await ImageExporter.shared.webp(raster)
        // Verify RIFF / WEBP / VP8L container signature
        #expect(encoded.data.count > 24)
        #expect(String(data: encoded.data[0..<4], encoding: .ascii) == "RIFF")
        #expect(String(data: encoded.data[8..<12], encoding: .ascii) == "WEBP")
        #expect(String(data: encoded.data[12..<16], encoding: .ascii) == "VP8L")

        let imgSource = try #require(CGImageSourceCreateWithData(encoded.data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(imgSource, 0, nil))
        #expect(decoded.width == 24 && decoded.height == 16)

        // Compare pixels at all four quadrants (top-left red, top-right 50% green, bottom-left blue, bottom-right transparent)
        let red = try rgbaPixel(in: decoded, x: 4, y: 2)
        #expect(red.r > 245 && red.g < 10 && red.b < 10 && red.a == 255)
        let halfGreen = try rgbaPixel(in: decoded, x: 18, y: 2)
        #expect(abs(Int(halfGreen.a) - 128) <= 2 && halfGreen.g >= 120 && halfGreen.r < 10)
        let blue = try rgbaPixel(in: decoded, x: 4, y: 12)
        #expect(blue.b > 245 && blue.r < 10 && blue.g < 10 && blue.a == 255)
        let clear = try rgbaPixel(in: decoded, x: 18, y: 12)
        #expect(clear.a == 0)
    }

    @Test func heicExportProducesValidDecodableHEIC() async throws {
        let source = try makeTestImage(width: 64, height: 48)
        let raster = ExportRaster(image: source, resolution: 144)
        let encoded = try await ImageExporter.shared.heic(raster, quality: 0.9)
        #expect(encoded.data.count > 64)

        let imgSource = try #require(CGImageSourceCreateWithData(encoded.data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(imgSource, 0, nil))
        #expect(decoded.width == 64 && decoded.height == 48)

        let red = try rgbaPixel(in: decoded, x: 10, y: 10)
        #expect(red.r > 210 && red.g < 40 && red.b < 40 && red.a > 240)
        let clear = try rgbaPixel(in: decoded, x: 54, y: 40)
        #expect(clear.a < 20)
    }

    @Test func psdExportsAndRoundTripsAllNativeAdjustmentLayers() async throws {
        let session = EditorSession()
        session.createDocument(width: 80, height: 60)
        let thumb = try solid(1, 1, red: 0, green: 0, blue: 0)
        session.insert(ImportedImage(image: try solid(80, 60, red: 0.4, green: 0.5, blue: 0.6), thumbnail: thumb, name: "Base"))

        var layers = try #require(session.document?.layers)
        let size = CGSize(width: 80, height: 60)

        var levelsLayer = ImageLayer(name: "Adj Levels", blankSize: size)
        var lvl = LevelsSettings()
        lvl.ranges[0] = LevelRange(black: 15, gamma: 1.35, white: 235, outputBlack: 10, outputWhite: 245)
        levelsLayer.adjustment = LayerAdjustment(kind: .levels, levels: lvl)
        layers.append(levelsLayer)

        var curvesLayer = ImageLayer(name: "Adj Curves", blankSize: size)
        var crv = CurvesSettings()
        crv.channels[0] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 128, y: 168), CurvePoint(x: 255, y: 255)]
        curvesLayer.adjustment = LayerAdjustment(kind: .curves, curves: crv)
        layers.append(curvesLayer)

        var hsvLayer = ImageLayer(name: "Adj HSV", blankSize: size)
        var hsv = HueSaturationSettings()
        hsv.adjustments[.master] = RangeAdjustment(hue: 25, saturation: -15, lightness: 8)
        hsvLayer.adjustment = LayerAdjustment(kind: .hsv, hsvSettings: hsv)
        layers.append(hsvLayer)

        var bcLayer = ImageLayer(name: "Adj BC", blankSize: size)
        bcLayer.adjustment = LayerAdjustment(kind: .brightnessContrast,
                                             brightnessContrastSettings: BrightnessContrastSettings(brightness: 22, contrast: -14))
        layers.append(bcLayer)

        var cbLayer = ImageLayer(name: "Adj CB", blankSize: size)
        cbLayer.adjustment = LayerAdjustment(kind: .colorBalance,
                                             colorBalanceSettings: ColorBalanceSettings(shadowCyanRed: -10, midMagentaGreen: 18,
                                                                                        highlightYellowBlue: 12, preserveLuminosity: false))
        layers.append(cbLayer)

        var invLayer = ImageLayer(name: "Adj Invert", blankSize: size)
        invLayer.adjustment = LayerAdjustment(kind: .invert)
        layers.append(invLayer)

        var postLayer = ImageLayer(name: "Adj Posterize", blankSize: size)
        postLayer.adjustment = LayerAdjustment(kind: .posterize, posterizeSettings: PosterizeSettings(levels: 6))
        layers.append(postLayer)

        var thrsLayer = ImageLayer(name: "Adj Threshold", blankSize: size)
        thrsLayer.adjustment = LayerAdjustment(kind: .threshold, thresholdSettings: ThresholdSettings(level: 142))
        layers.append(thrsLayer)

        var expLayer = ImageLayer(name: "Adj Exposure", blankSize: size)
        expLayer.adjustment = LayerAdjustment(kind: .exposure, exposureSettings: ExposureSettings(exposure: 1.25, offset: -0.05, gamma: 1.4))
        layers.append(expLayer)

        session.document?.layers = layers
        let snapshot = try #require(session.projectSnapshot())
        #expect(PSDWriter.notes(for: snapshot).isEmpty)

        let written = try await ImageExporter.shared.psdData(snapshot)
        let parsed = try PSDReader.read(written.data)
        let byName = Dictionary(uniqueKeysWithValues: parsed.layers.map { ($0.name, $0) })

        let outLevels = try #require(byName["Adj Levels"]?.adjustment)
        #expect(outLevels.kind == .levels)
        #expect(outLevels.levels.ranges[0].black == 15)
        #expect(abs(outLevels.levels.ranges[0].gamma - 1.35) < 0.02)
        #expect(outLevels.levels.ranges[0].white == 235)

        let outCurves = try #require(byName["Adj Curves"]?.adjustment)
        #expect(outCurves.kind == .curves)
        #expect(outCurves.curves.channels[0].count == 3)
        #expect(outCurves.curves.channels[0][1] == CurvePoint(x: 128, y: 168))

        let outHSV = try #require(byName["Adj HSV"]?.adjustment)
        #expect(outHSV.kind == .hsv)
        #expect(outHSV.resolvedHSV.adjustments[.master] == RangeAdjustment(hue: 25, saturation: -15, lightness: 8))

        let outBC = try #require(byName["Adj BC"]?.adjustment)
        #expect(outBC.kind == .brightnessContrast)
        #expect(outBC.brightnessContrastSettings?.brightness == 22)
        #expect(outBC.brightnessContrastSettings?.contrast == -14)

        let outCB = try #require(byName["Adj CB"]?.adjustment)
        #expect(outCB.kind == .colorBalance)
        #expect(outCB.colorBalanceSettings?.shadowCyanRed == -10)
        #expect(outCB.colorBalanceSettings?.midMagentaGreen == 18)
        #expect(outCB.colorBalanceSettings?.highlightYellowBlue == 12)
        #expect(outCB.colorBalanceSettings?.preserveLuminosity == false)

        #expect(byName["Adj Invert"]?.adjustment?.kind == .invert)
        #expect(byName["Adj Posterize"]?.adjustment?.posterizeSettings?.levels == 6)
        #expect(byName["Adj Threshold"]?.adjustment?.thresholdSettings?.level == 142)

        let outExp = try #require(byName["Adj Exposure"]?.adjustment?.exposureSettings)
        #expect(abs(outExp.exposure - 1.25) < 0.001)
        #expect(abs(outExp.offset - (-0.05)) < 0.001)
        #expect(abs(outExp.gamma - 1.4) < 0.001)
    }

    @Test func psdRoundTripsBlendIfAndWritesLayerEffectsBlock() async throws {
        let session = EditorSession()
        session.createDocument(width: 80, height: 60)
        let thumb = try solid(1, 1, red: 0, green: 0, blue: 0)
        session.insert(ImportedImage(image: try solid(40, 30, red: 0.9, green: 0.3, blue: 0.2), thumbnail: thumb, name: "Styled"))

        var layers = try #require(session.document?.layers)
        let idx = try #require(layers.firstIndex { $0.name == "Styled" })
        let expectedBlendIf = BlendIfSettings(
            channel: .red,
            thisLayer: BlendIfRange(blackLow: 20, blackHigh: 50, whiteLow: 200, whiteHigh: 240),
            underlyingLayer: BlendIfRange(blackLow: 10, blackHigh: 40, whiteLow: 210, whiteHigh: 255)
        )
        layers[idx].blendIf = expectedBlendIf
        layers[idx].fillOpacity = 0.6
        layers[idx].effects = LayerEffects(
            shadow: ShadowEffect(angle: 135, distance: 6, blur: 8, opacity: 0.7),
            colorOverlay: ColorOverlayEffect(red: 0.2, green: 0.6, blue: 0.9, opacity: 0.5)
        )
        session.document?.layers = layers

        let snapshot = try #require(session.projectSnapshot())
        let written = try await ImageExporter.shared.psdData(snapshot)

        // Verify lrFX block signature is written in the PSD binary
        let marker = Data("8BIMlrFX".utf8)
        #expect(written.data.range(of: marker) != nil)

        // Verify Blend If round-trips through PSDReader and PSDDocumentBuilder
        let parsed = try PSDReader.read(written.data)
        let styledRecord = try #require(parsed.layers.first { $0.name == "Styled" })
        #expect(styledRecord.blendIf == expectedBlendIf)

        let imported = try PSDDocumentBuilder.makeImport(parsed)
        let importedStyled = try #require(imported.layers.first { $0.name == "Styled" })
        #expect(importedStyled.blendIf == expectedBlendIf)
    }
}
