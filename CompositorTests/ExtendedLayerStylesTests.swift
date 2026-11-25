import AppKit
import CoreGraphics
import Testing
@testable import Compositor

@MainActor
struct ExtendedLayerStylesTests {
    private func squareAsset(size: Int = 32, r: CGFloat = 0.5, g: CGFloat = 0.5, b: CGFloat = 0.5) throws -> ImportedImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                         bytesPerRow: size * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(CGColor(colorSpace: space, components: [r, g, b, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let image = try #require(ctx.makeImage())
        return ImportedImage(image: image, thumbnail: image, name: "Square")
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

    @Test func bevelAndEmbossIlluminatesLitEdgeAndDarkensOppositeEdge() throws {
        let asset = try squareAsset(size: 32, r: 0.5, g: 0.5, b: 0.5)
        var bevel = BevelEmbossEffect()
        bevel.style = .innerBevel
        bevel.direction = .up
        bevel.angle = 90 // Light from straight above
        bevel.altitude = 30
        bevel.size = 6
        bevel.depth = 150
        let effects = LayerEffects(bevelEmboss: bevel)
        let rendered = try LayerEffectsRenderer.render(asset.image, mask: nil, effects: effects)
        let inset = Int(rendered.inset)

        let topEdge = try rgba(rendered.image, x: inset + 16, y: inset + 2)
        let center = try rgba(rendered.image, x: inset + 16, y: inset + 16)
        let bottomEdge = try rgba(rendered.image, x: inset + 16, y: inset + 29)
        // Lit top edge is brighter than neutral center; shaded bottom edge is darker.
        #expect(topEdge.r > center.r + 20)
        #expect(bottomEdge.r + 20 < center.r)

        // Flipping direction to Down reverses highlight and shadow.
        var down = bevel
        down.direction = .down
        let renderedDown = try LayerEffectsRenderer.render(asset.image, mask: nil, effects: LayerEffects(bevelEmboss: down))
        let insetD = Int(renderedDown.inset)
        let topD = try rgba(renderedDown.image, x: insetD + 16, y: insetD + 2)
        let botD = try rgba(renderedDown.image, x: insetD + 16, y: insetD + 29)
        #expect(botD.r > topD.r + 30)
    }

    @Test func gradientOverlayRendersLinearAndRadialAndRespectsReverse() throws {
        let asset = try squareAsset(size: 20, r: 0.5, g: 0.5, b: 0.5)
        var grad = GradientOverlayEffect()
        grad.style = .linear
        grad.angle = 0 // Left (black) to right (white)
        grad.stops = [
            GradientOverlayStop(position: 0, red: 0, green: 0, blue: 0),
            GradientOverlayStop(position: 1, red: 1, green: 0, blue: 0),
        ]
        let rendered = try LayerEffectsRenderer.render(asset.image, mask: nil, effects: LayerEffects(gradientOverlay: grad))
        let inset = Int(rendered.inset)
        let left = try rgba(rendered.image, x: inset + 1, y: inset + 10)
        let right = try rgba(rendered.image, x: inset + 18, y: inset + 10)
        #expect(left.r < 30 && right.r > 220)

        grad.reverse = true
        let reversed = try LayerEffectsRenderer.render(asset.image, mask: nil, effects: LayerEffects(gradientOverlay: grad))
        let rInset = Int(reversed.inset)
        let rLeft = try rgba(reversed.image, x: rInset + 1, y: rInset + 10)
        let rRight = try rgba(reversed.image, x: rInset + 18, y: rInset + 10)
        #expect(rLeft.r > 220 && rRight.r < 30)
    }

    @Test func patternOverlayRendersCheckerboardClippedToLayerAlpha() throws {
        let asset = try squareAsset(size: 32, r: 1, g: 1, b: 1)
        var pat = PatternOverlayEffect()
        pat.pattern = .checkerboard
        pat.scale = 100 // 16px period -> 8px tiles
        pat.opacity = 1
        pat.red = 0; pat.green = 0; pat.blue = 0
        let rendered = try LayerEffectsRenderer.render(asset.image, mask: nil, effects: LayerEffects(patternOverlay: pat))
        let inset = Int(rendered.inset)

        // Outside the layer remains transparent.
        let outside = try rgba(rendered.image, x: 0, y: 0)
        #expect(outside.a == 0)

        // Adjacent 8px cells inside checkerboard alternate white and black.
        let c0 = try rgba(rendered.image, x: inset + 2, y: inset + 2)
        let c1 = try rgba(rendered.image, x: inset + 10, y: inset + 2)
        #expect(abs(Int(c0.r) - Int(c1.r)) > 200)
    }

    @Test func centerStrokeStraddlesBoundaryInsideAndOutside() throws {
        let asset = try squareAsset(size: 20, r: 1, g: 1, b: 1)
        var stroke = StrokeEffect(size: 6, red: 1, green: 0, blue: 0, opacity: 1)
        stroke.resolvedPosition = .center
        let rendered = try LayerEffectsRenderer.render(asset.image, mask: nil, effects: LayerEffects(stroke: stroke))
        let inset = Int(rendered.inset)

        // 2px outside left edge -> red stroke.
        let outPx = try rgba(rendered.image, x: inset - 2, y: inset + 10)
        // 1px inside left edge -> red stroke.
        let inPx = try rgba(rendered.image, x: inset + 1, y: inset + 10)
        // Deep center -> original white fill.
        let midPx = try rgba(rendered.image, x: inset + 10, y: inset + 10)
        #expect(outPx.r > 200 && outPx.g < 40 && outPx.a > 200)
        #expect(inPx.r > 200 && inPx.g < 40 && inPx.a == 255)
        #expect(midPx.r > 245 && midPx.g > 245 && midPx.b > 245)
    }

    @Test func spreadThickensDropShadowAndPerEffectBlendModeAppliesMultiply() throws {
        let asset = try squareAsset(size: 16, r: 0.8, g: 0.8, b: 0.8)
        var s0 = ShadowEffect(angle: 90, distance: 0, blur: 12, red: 0, green: 0, blue: 0, opacity: 1)
        s0.spread = nil
        var s80 = s0
        s80.spread = 80
        let r0 = try LayerEffectsRenderer.render(asset.image, mask: nil, effects: LayerEffects(shadow: s0))
        let r80 = try LayerEffectsRenderer.render(asset.image, mask: nil, effects: LayerEffects(shadow: s80))
        let p0 = try rgba(r0.image, x: Int(r0.inset) - 4, y: Int(r0.inset) + 8)
        let p80 = try rgba(r80.image, x: Int(r80.inset) - 4, y: Int(r80.inset) + 8)
        #expect(p80.a > p0.a + 30)

        // Color Overlay with Multiply on white(0.8) with red(1, 0, 0) yields (0.8, 0, 0) instead of (1, 0, 0).
        var overlay = ColorOverlayEffect(red: 1, green: 0, blue: 0, opacity: 1, blendMode: .multiply)
        overlay.enabled = true
        let rm = try LayerEffectsRenderer.render(asset.image, mask: nil, effects: LayerEffects(colorOverlay: overlay))
        let pm = try rgba(rm.image, x: Int(rm.inset) + 8, y: Int(rm.inset) + 8)
        #expect(abs(Int(pm.r) - 204) <= 4 && pm.g < 5 && pm.b < 5)
    }

    @Test func version28RoundTripsAllExtendedLayerStylesAndRejectsVersion27() async throws {
        let session = EditorSession()
        session.createDocument(width: 24, height: 24)
        session.insert(try squareAsset(size: 16))
        let id = try #require(session.activeLayerID)

        var stroke = StrokeEffect(size: 4, red: 0, green: 1, blue: 0, opacity: 0.9)
        stroke.resolvedPosition = .center
        stroke.blendMode = .multiply
        var bevel = BevelEmbossEffect()
        bevel.style = .pillowEmboss
        bevel.depth = 200
        var grad = GradientOverlayEffect()
        grad.style = .diamond
        grad.blendMode = .overlay
        var pat = PatternOverlayEffect()
        pat.pattern = .crosshatch
        pat.scale = 150
        let effects = LayerEffects(stroke: stroke, bevelEmboss: bevel, gradientOverlay: grad, patternOverlay: pat)
        session.setEffects(effects, on: id)

        let snapshot = try #require(session.projectSnapshot())
        #expect(snapshot.manifest.version == 28)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ExtendedStyles-\(UUID()).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(snapshot, to: url)

        let loaded = try await ProjectStore.shared.load(from: url)
        let restored = try #require(loaded.documentLayers.first { $0.id == id }?.effects)
        #expect(restored == effects)

        // Tamper manifest down to version 27: v28 extended layer styles must be rejected.
        let manifestURL = url.appendingPathComponent("manifest.json")
        var tampered = try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
        tampered.version = 27
        try JSONEncoder().encode(tampered).write(to: manifestURL)
        await #expect(throws: ProjectError.self) {
            _ = try await ProjectStore.shared.load(from: url)
        }
    }
}
