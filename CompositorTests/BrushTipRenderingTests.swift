import AppKit
import Testing
@testable import Compositor

@MainActor
struct BrushTipRenderingTests {
    private let canvas = CGSize(width: 600, height: 160)

    private func stroke(_ settings: BrushSettings, layer: ImageLayer? = nil, mask: Bool = false,
                        dabSeed: UInt64? = nil) throws -> BrushStroke {
        try BrushStroke(layer: layer ?? ImageLayer(name: "Test", blankSize: canvas),
                        mask: mask, settings: settings, canvas: canvas, dabSeed: dabSeed)
    }

    private func pixel(_ stroke: BrushStroke, x: Int, y: Int) -> Int {
        guard let patch = stroke.patches.first(where: { $0.rect.contains(CGPoint(x: x, y: y)) }) else { return 0 }
        var components = [Int](repeating: 0, count: 4)
        NSBitmapImageRep(cgImage: patch.image).getPixel(&components, atX: x - Int(patch.rect.minX), y: y - Int(patch.rect.minY))
        return components[stroke.isMask ? 0 : 3]
    }

    @Test func sampledShapeFollowsSpacingAndPressure() throws {
        var settings = BrushSettings(diameter: 16, pressureOpacity: true, antialiased: false)
        settings.tip = try #require(BrushTip(width: 2, height: 2, coverage: Data([255, 0, 0, 0])))
        settings.spacing = 2
        let stroke = try stroke(settings)
        #expect(!stroke.usesGPU)
        try stroke.append(CGPoint(x: 24, y: 32), pressure: 0.5)
        try stroke.append(CGPoint(x: 59, y: 32), pressure: 0.5)
        try stroke.flush()
        #expect((126...129).contains(pixel(stroke, x: 20, y: 28)))
        #expect(pixel(stroke, x: 28, y: 28) == 0)
        #expect(pixel(stroke, x: 20, y: 36) == 0)
        #expect(pixel(stroke, x: 36, y: 28) == 0)
        #expect((126...129).contains(pixel(stroke, x: 52, y: 28)))
    }

    @Test func tipAngleAndRoundnessUseDocumentCoordinates() throws {
        var settings = BrushSettings(diameter: 24, antialiased: false)
        settings.tip = try #require(BrushTip(width: 2, height: 2, coverage: Data([255, 0, 0, 0])))
        settings.angle = 90
        let sampled = try stroke(settings)
        let center = CGPoint(x: 64, y: 40)
        try sampled.append(center)
        #expect(pixel(sampled, x: 58, y: 46) == 255)
        #expect(pixel(sampled, x: 58, y: 34) == 0)

        settings.tip = nil
        settings.roundness = 0.25
        let oval = try stroke(settings)
        try oval.append(center)
        #expect(pixel(oval, x: 64, y: 48) == 255)
        #expect(pixel(oval, x: 72, y: 40) == 0)
    }

    @Test func repeatedDabsBuildFlowUnderTheStrokeOpacity() throws {
        var settings = BrushSettings(diameter: 20, opacity: 0.4)
        settings.flow = 0.5
        let center = CGPoint(x: 40, y: 40)
        let oneDab = try stroke(settings)
        try oneDab.append(center)
        #expect((49...53).contains(pixel(oneDab, x: 40, y: 40)))

        settings.scatterCount = 2
        let twoDabs = try stroke(settings)
        try twoDabs.append(center)
        #expect((74...79).contains(pixel(twoDabs, x: 40, y: 40)))
    }

    @Test func jitterAndScatterStayStableWhenReplayedAcrossTiles() throws {
        var settings = BrushSettings(diameter: 24, pressureSize: true)
        settings.tip = try #require(BrushTip(width: 2, height: 2, coverage: Data([0, 127, 255, 0])))
        settings.spacing = 0.8
        settings.flow = 0.7
        settings.scatter = 1.5
        settings.scatterCount = 3
        settings.scatterBothAxes = true
        settings.sizeJitter = 0.5
        settings.angleJitter = 1
        settings.opacityJitter = 0.5
        let inputs: [(point: CGPoint, pressure: CGFloat)] = [
            (CGPoint(x: 30, y: 70), 1), (CGPoint(x: 160, y: 54), 0.8),
            (CGPoint(x: 254, y: 54), 0.65), (CGPoint(x: 380, y: 80), 0.9),
            (CGPoint(x: 520, y: 83), 0.7),
        ]
        let live = try stroke(settings, dabSeed: 42)
        for input in inputs { try live.append(input.point, pressure: input.pressure) }
        try live.flush()
        let replayed = try stroke(settings, dabSeed: live.dabSeed)
        try replayed.replay(inputs)
        try replayed.flush()
        let primary = try patches(live)
        #expect(primary.count == 3)
        #expect(try patches(replayed) == primary)
        let separate = try stroke(settings, dabSeed: live.dabSeed &+ 1)
        try separate.replay(inputs)
        try separate.flush()
        #expect(try patches(separate) != primary)
    }

    @Test func sampledTipErasesAndPaintsMasks() async throws {
        let layer = ImageLayer(name: "Test", blankSize: canvas)
        let base = try stroke(BrushSettings(diameter: 40), layer: layer)
        try base.fill(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        var opaqueLayer = layer
        opaqueLayer.asset = try base.paintSnapshot().asset

        var settings = BrushSettings(diameter: 24, erasing: true, antialiased: false)
        settings.tip = try #require(BrushTip(width: 2, height: 2, coverage: Data([255, 0, 0, 0])))
        let point = CGPoint(x: 40, y: 40)
        let eraser = try stroke(settings, layer: opaqueLayer)
        try eraser.append(point)
        try eraser.flush()
        #expect(pixel(eraser, x: 34, y: 34) == 0)
        #expect(pixel(eraser, x: 46, y: 34) == 255)

        settings.erasing = false
        let mask = try stroke(settings, layer: opaqueLayer, mask: true)
        try mask.append(point)
        try mask.flush()
        #expect(pixel(mask, x: 34, y: 34) == 0)
        #expect(pixel(mask, x: 46, y: 34) == 255)

        let committed = try await BrushCommit.shared.render(mask.commitInput())
        let bitmap = NSBitmapImageRep(cgImage: committed.asset.image)
        var before = [Int](repeating: 0, count: 4), after = before
        bitmap.getPixel(&before, atX: 34, y: 34)
        bitmap.getPixel(&after, atX: 46, y: 34)
        #expect(before[0] == 0 && after[0] == 255)
    }

    private func patches(_ stroke: BrushStroke) throws -> [Data] {
        try stroke.patches.sorted {
            ($0.rect.minX, $0.rect.minY) < ($1.rect.minX, $1.rect.minY)
        }.map { patch in
            let data = try #require(patch.image.dataProvider?.data)
            return data as Data
        }
    }
}
