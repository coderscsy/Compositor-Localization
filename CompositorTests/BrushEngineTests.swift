import AppKit
import CoreGraphics
import Testing
@testable import Compositor

@MainActor
struct BrushEngineTests {
    private func splitAsset(width: Int, height: Int, left: (CGFloat, CGFloat, CGFloat, CGFloat), right: (CGFloat, CGFloat, CGFloat, CGFloat)) throws -> ImportedImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: width * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(colorSpace: space, components: [left.0, left.1, left.2, left.3])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        ctx.setFillColor(CGColor(colorSpace: space, components: [right.0, right.1, right.2, right.3])!)
        ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        let image = try #require(ctx.makeImage())
        return ImportedImage(image: image, thumbnail: image, name: "Split")
    }

    private func rgba(_ image: CGImage, x: Int, y: Int) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                         bytesPerRow: image.width * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let ptr = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * ctx.bytesPerRow + x * 4
        return (ptr[offset], ptr[offset + 1], ptr[offset + 2], ptr[offset + 3])
    }

    @Test func flowAndAirbrushBuildUpWithinStrokeUpToOpacityCap() async throws {
        let session = EditorSession()
        session.createDocument(width: 32, height: 32)
        session.addBlankLayer()
        session.selectTool(.brush)
        session.foregroundColor = PaletteColor(red: 1, green: 0, blue: 0)
        session.brushSettings.diameter = 16
        session.brushSettings.hardness = 1
        session.brushSettings.opacity = 0.5
        session.brushSettings.flow = 0.2
        session.brushSettings.airbrush = true

        session.beginBrush(at: CGPoint(x: 16, y: 16))
        // After 1 dab at 20% flow * 50% opacity = ~10% alpha (~26).
        let stroke = try #require(session.brushStroke)
        let firstImg = try stroke.paintSnapshot().asset.image
        let firstAlpha = try rgba(firstImg, x: firstImg.width / 2, y: firstImg.height / 2).a
        // Deposit 12 more airbrush pulses at the same point -> builds up toward opacity cap 50% (~128).
        for _ in 0..<12 { try stroke.airbrushPulse(at: CGPoint(x: 16, y: 16)) }
        session.finishBrushImmediately()

        let rendered = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let builtUp = try rgba(rendered.image, x: 16, y: 16)
        #expect(firstAlpha > 15 && firstAlpha < 45)
        #expect(builtUp.a > firstAlpha + 60)
        #expect(builtUp.a <= 135) // Capped by 50% stroke opacity (~128)
    }

    @Test func brushBlendModesApplyMultiplyBehindAndClear() async throws {
        // Left half opaque mid-gray, right half transparent.
        let session = EditorSession()
        session.createDocument(width: 32, height: 16)
        session.insert(try splitAsset(width: 32, height: 16, left: (0.5, 0.5, 0.5, 1), right: (0, 0, 0, 0)))
        session.selectTool(.brush)
        session.foregroundColor = PaletteColor(red: 1, green: 0, blue: 0)
        session.brushSettings.diameter = 32
        session.brushSettings.hardness = 1
        session.brushSettings.opacity = 1
        session.brushSettings.flow = 1

        // 1. Behind mode paints ONLY transparent right side, leaving opaque left gray untouched.
        session.brushSettings.blendMode = .behind
        session.beginBrush(at: CGPoint(x: 16, y: 8))
        session.finishBrushImmediately()
        let behindRaster = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let bLeft = try rgba(behindRaster.image, x: 8, y: 8)
        let bRight = try rgba(behindRaster.image, x: 24, y: 8)
        #expect(abs(Int(bLeft.r) - 128) <= 3 && abs(Int(bLeft.g) - 128) <= 3)
        #expect(bRight.r > 240 && bRight.g < 10 && bRight.a == 255)

        // 2. Multiply mode with pure red (1, 0, 0) over left gray (0.5, 0.5, 0.5) -> (0.5, 0, 0).
        session.brushSettings.blendMode = .multiply
        session.beginBrush(at: CGPoint(x: 8, y: 8))
        session.finishBrushImmediately()
        let mulRaster = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let mLeft = try rgba(mulRaster.image, x: 8, y: 8)
        #expect(abs(Int(mLeft.r) - 128) <= 5 && mLeft.g < 5 && mLeft.b < 5)

        // 3. Clear mode erases pixels to transparent.
        session.brushSettings.blendMode = .clear
        session.beginBrush(at: CGPoint(x: 8, y: 8))
        session.finishBrushImmediately()
        let clrRaster = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let cLeft = try rgba(clrRaster.image, x: 8, y: 8)
        #expect(cLeft.a == 0)
    }

    @Test func ellipticalCalligraphyTipProducesAnisotropicMark() async throws {
        let session = EditorSession()
        session.createDocument(width: 40, height: 40)
        session.addBlankLayer()
        session.selectTool(.brush)
        session.foregroundColor = PaletteColor(red: 0, green: 0, blue: 1)
        session.brushSettings.diameter = 24
        session.brushSettings.hardness = 1
        session.brushSettings.roundness = 0.25 // 24px wide, 6px tall
        session.brushSettings.angle = 0

        session.beginBrush(at: CGPoint(x: 20, y: 20))
        session.finishBrushImmediately()

        let rendered = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        // 8px horizontally from center -> painted; 8px vertically from center -> transparent.
        let horiz = try rgba(rendered.image, x: 28, y: 20)
        let vert = try rgba(rendered.image, x: 20, y: 28)
        #expect(horiz.a == 255 && horiz.b > 240)
        #expect(vert.a == 0)
    }

    @Test func brushPresetsConfigureEngineParameters() throws {
        let session = EditorSession()
        let chisel = try #require(BrushPreset.builtIn.first { $0.id == "chisel" })
        session.applyBrushPreset(chisel)
        #expect(session.brushSettings.roundness < 0.5 && session.brushSettings.angle == 30)
        let airbrush = try #require(BrushPreset.builtIn.first { $0.id == "airbrush-soft" })
        session.applyBrushPreset(airbrush)
        #expect(session.brushSettings.airbrush && session.brushSettings.flow < 0.5)
    }

    @Test func paintBucketFloodFillsContiguousAndRespectsLockTransparent() async throws {
        let session = EditorSession()
        session.createDocument(width: 16, height: 8)
        // Left half black, right half white.
        session.insert(try splitAsset(width: 16, height: 8, left: (0, 0, 0, 1), right: (1, 1, 1, 1)))
        session.selectTool(.gradient)
        session.fillToolMode = .paintBucket
        session.foregroundColor = PaletteColor(red: 0, green: 1, blue: 0)
        session.paintBucketSettings.tolerance = 16
        session.paintBucketSettings.contiguous = true

        session.applyPaintBucket(at: CGPoint(x: 2, y: 4))
        let r1 = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let left1 = try rgba(r1.image, x: 2, y: 4)
        let right1 = try rgba(r1.image, x: 12, y: 4)
        #expect(left1.g > 245 && left1.r < 10)
        #expect(right1.r > 245 && right1.g > 245 && right1.b > 245)

        // Undo restores original black left half.
        session.undo()
        let rUndo = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        #expect(try rgba(rUndo.image, x: 2, y: 4).g < 10)
    }
}
