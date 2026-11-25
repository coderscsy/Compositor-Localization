import AppKit
import Testing
@testable import Compositor

@MainActor
struct ToneAndSharpenBrushTests {
    private func solidAsset(width: Int = 16, height: Int = 16, r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) throws -> ImportedImage {
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        return ImportedImage(image: image, thumbnail: image, name: "Tone")
    }

    /// A 16x16 asset with a soft vertical edge (left dark gray, right light gray) for verifying Sharpen Brush.
    private func edgeAsset() throws -> ImportedImage {
        let context = try BrushRaster.context(width: 16, height: 16, mask: false)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        for x in 0..<16 {
            let v: CGFloat = x < 7 ? 0.30 : x == 7 ? 0.45 : x == 8 ? 0.55 : 0.70
            context.setFillColor(CGColor(colorSpace: space, components: [v, v, v, 1])!)
            context.fill(CGRect(x: x, y: 0, width: 1, height: 16))
        }
        let image = try #require(context.makeImage())
        return ImportedImage(image: image, thumbnail: image, name: "Edge")
    }

    private func rgba(of image: CGImage, atX x: Int, y: Int) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    @Test func dodgeLightensAndBurnDarkensMidtonesWhilePreservingAlpha() async throws {
        let session = EditorSession()
        session.createDocument(width: 16, height: 16)
        session.insert(try solidAsset(r: 0.5, g: 0.5, b: 0.5, a: 0.5))

        session.selectTool(.tone)
        session.toneSettings.mode = .dodge
        session.toneSettings.range = .midtones
        session.toneSettings.protectTones = true
        session.brushSettings.diameter = 12
        session.brushSettings.hardness = 1
        session.brushSettings.opacity = 0.6

        let before = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let beforePixel = try rgba(of: before, atX: 8, y: 8)

        session.beginBrush(at: CGPoint(x: 8, y: 8))
        await session.finishBrush()
        let dodged = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let dodgedPixel = try rgba(of: dodged, atX: 8, y: 8)
        #expect(dodgedPixel.r > beforePixel.r + 10)
        // Alpha on a semi-transparent layer must remain unchanged (no thickening).
        #expect(abs(Int(dodgedPixel.a) - Int(beforePixel.a)) <= 1)

        // Undo returns to original.
        session.undo()
        let undone = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        #expect(try rgba(of: undone, atX: 8, y: 8).r == beforePixel.r)

        // Burn darkens midtones.
        session.toneSettings.mode = .burn
        session.beginBrush(at: CGPoint(x: 8, y: 8))
        await session.finishBrush()
        let burned = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let burnedPixel = try rgba(of: burned, atX: 8, y: 8)
        #expect(burnedPixel.r < beforePixel.r - 10)
        #expect(abs(Int(burnedPixel.a) - Int(beforePixel.a)) <= 1)
    }

    @Test func spongeSaturatesAndDesaturatesColor() async throws {
        let session = EditorSession()
        session.createDocument(width: 16, height: 16)
        // Muted warm color: R=0.7, G=0.5, B=0.4
        session.insert(try solidAsset(r: 0.7, g: 0.5, b: 0.4))

        session.selectTool(.tone)
        session.toneSettings.mode = .sponge
        session.toneSettings.spongeMode = .desaturate
        session.brushSettings.diameter = 14
        session.brushSettings.hardness = 1
        session.brushSettings.opacity = 1.0

        session.beginBrush(at: CGPoint(x: 8, y: 8))
        await session.finishBrush()
        let gray = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let gPixel = try rgba(of: gray, atX: 8, y: 8)
        // At 100% flow desaturate, RGB channels collapse to luminance.
        #expect(abs(Int(gPixel.r) - Int(gPixel.b)) <= 2)

        session.undo()
        session.toneSettings.spongeMode = .saturate
        session.brushSettings.opacity = 0.8
        session.beginBrush(at: CGPoint(x: 8, y: 8))
        await session.finishBrush()
        let vivid = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let vPixel = try rgba(of: vivid, atX: 8, y: 8)
        // Saturating increases R-B spread beyond original (0.3 * 255 ≈ 76).
        #expect(Int(vPixel.r) - Int(vPixel.b) > 100)
    }

    @Test func sharpenBrushIncreasesLocalEdgeContrast() async throws {
        let session = EditorSession()
        session.createDocument(width: 16, height: 16)
        session.insert(try edgeAsset())

        let before = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let beforeDiff = Int(try rgba(of: before, atX: 8, y: 8).r) - Int(try rgba(of: before, atX: 7, y: 8).r)

        session.selectTool(.blur)
        session.blurMode = .sharpen
        session.brushSettings.diameter = 14
        session.brushSettings.hardness = 1
        session.brushSettings.opacity = 1
        session.brushSettings.blurRadius = 2
        session.beginBrush(at: CGPoint(x: 8, y: 8))
        await session.finishBrush()

        let after = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let afterDiff = Int(try rgba(of: after, atX: 8, y: 8).r) - Int(try rgba(of: after, atX: 7, y: 8).r)
        #expect(afterDiff > beforeDiff + 8)
    }

    @Test func cycleToolModeStepsThroughToneAndSharpenModes() {
        let session = EditorSession()
        session.createDocument(width: 16, height: 16)
        session.selectTool(.tone)
        #expect(session.toneSettings.mode == .dodge)
        session.cycleToolMode()
        #expect(session.toneSettings.mode == .burn)
        session.cycleToolMode()
        #expect(session.toneSettings.mode == .sponge)
        session.cycleToolMode()
        #expect(session.toneSettings.mode == .dodge)
    }
}
