import CoreGraphics
import Foundation
import Testing
@testable import Compositor

@MainActor
struct ShapeUpgradeTests {
    private func pixel(in image: CGImage, x: Int, y: Int) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                         bytesPerRow: image.width * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let ptr = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * ctx.bytesPerRow + x * 4
        return (ptr[offset], ptr[offset + 1], ptr[offset + 2], ptr[offset + 3])
    }

    @Test func trianglePolygonAndStarGeometry() throws {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        // Triangle: top-center is filled, top-left corner is empty, bottom-center is filled.
        let tri = try EditorSession.shapeImage(.triangle, size: rect.size, color: .white)
        #expect(try pixel(in: tri, x: 50, y: 50).a == 255)
        #expect(try pixel(in: tri, x: 5, y: 5).a == 0)
        #expect(try pixel(in: tri, x: 50, y: 95).a == 255)

        // Hexagon (6-sided polygon): center filled, outer corner (2, 2) empty.
        let poly = try EditorSession.shapeImage(.polygon, size: rect.size, color: .white, sides: 6)
        #expect(try pixel(in: poly, x: 50, y: 50).a == 255)
        #expect(try pixel(in: poly, x: 2, y: 2).a == 0)

        // 5-pointed star with narrow inner radius (0.25): center filled, concave notch between top & upper-right points empty.
        let star = try EditorSession.shapeImage(.star, size: rect.size, color: .white, sides: 5, starInnerRatio: 0.25)
        #expect(try pixel(in: star, x: 50, y: 50).a == 255)
        #expect(try pixel(in: star, x: 50, y: 12).a == 255)
        // Angle -pi/2 + pi/5 = -54° at distance 0.45 * 50 = 22.5 -> outside inner radius 0.25 * 50 = 12.5!
        let notchX = Int(50 + cos(-Double.pi / 2 + Double.pi / 5) * 28)
        let notchY = Int(50 + sin(-Double.pi / 2 + Double.pi / 5) * 28)
        #expect(try pixel(in: star, x: notchX, y: notchY).a == 0)
    }

    @Test func strokePositionAndDashedClosedShape() throws {
        let size = CGSize(width: 100, height: 100)
        let fill = PaletteColor(red: 1, green: 0, blue: 0)
        let stroke = PaletteColor(red: 0, green: 0, blue: 1)

        // Dashed inside stroke leaves both blue dashes AND red gaps along the top edge (y = 2).
        let dashed = try EditorSession.shapeImage(.rectangle, size: size, color: fill,
                                                  strokeWidth: 4, strokeColor: stroke,
                                                  strokePosition: .inside, strokeLineStyle: .dashed)
        var sawBlue = false, sawRed = false
        for x in 10..<90 {
            let p = try pixel(in: dashed, x: x, y: 2)
            if p.b > 200 && p.r < 50 { sawBlue = true }
            if p.r > 200 && p.b < 50 { sawRed = true }
        }
        #expect(sawBlue && sawRed)

        // Dashed outside stroke leaves both blue dashes AND transparent gaps along the outer rim (y = 2).
        let outsideDashed = try EditorSession.shapeImage(.rectangle, size: size, color: fill,
                                                         strokeWidth: 6, strokeColor: stroke,
                                                         strokePosition: .outside, strokeLineStyle: .dashed)
        var sawStroke = false, sawClear = false
        for x in 12..<88 {
            let p = try pixel(in: outsideDashed, x: x, y: 2)
            if p.b > 200 && p.a > 200 { sawStroke = true }
            if p.a == 0 { sawClear = true }
        }
        #expect(sawStroke && sawClear)
        // Center is pure red fill.
        let center = try pixel(in: outsideDashed, x: 50, y: 50)
        #expect(center.r > 240 && center.b < 10)
    }

    @Test func v30ShapeRoundTripsAndRejectsOlderVersions() async throws {
        let session = EditorSession()
        session.createDocument(width: 120, height: 120)
        session.selectTool(.shape)
        session.shapeKind = .star
        session.shapeStarPoints = 7
        session.shapeStarInnerRatio = 0.35
        session.shapeStrokeWidth = 4
        session.shapeStrokeColor = PaletteColor(red: 0, green: 1, blue: 0)
        session.shapeStrokePosition = .center
        session.shapeStrokeLineStyle = .dashed

        session.beginShape(at: CGPoint(x: 10, y: 10))
        session.dragShape(to: CGPoint(x: 110, y: 110), square: true, fromCenter: false)
        session.finishShape()

        let style = try #require(session.activeLayer?.liveShape?.style)
        #expect(style.kind == .star)
        #expect(style.sides == 7)
        #expect(style.starInnerRatio == 0.35)
        #expect(style.strokePosition == .center)
        #expect(style.strokeLineStyle == .dashed)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shape-v30-\(UUID().uuidString).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(try #require(session.projectSnapshot()), to: url)

        let loaded = try await ProjectStore.shared.load(from: url)
        let loadedStyle = try #require(loaded.manifest.layers.last?.shape)
        #expect(loadedStyle == style)

        // Mutate manifest version to 29 -> must throw ProjectError.invalid.
        let manifestURL = url.appendingPathComponent("manifest.json")
        var manifest = try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
        #expect(manifest.version == ProjectManifest.current)
        manifest.version = 29
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        await #expect(throws: ProjectError.self) {
            _ = try await ProjectStore.shared.load(from: url)
        }
    }
}
