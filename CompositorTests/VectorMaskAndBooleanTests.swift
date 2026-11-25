import CoreGraphics
import Foundation
import Testing
@testable import Compositor

@MainActor
struct VectorMaskAndBooleanTests {
    private func alpha(in image: CGImage, x: Int, y: Int) throws -> UInt8 {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                         bytesPerRow: image.width * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let ptr = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        return ptr[y * ctx.bytesPerRow + x * 4 + 3]
    }

    @Test func vectorMaskClipsNonDestructivelyInvertsAndRasterizes() async throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)
        // Fill full canvas red layer.
        session.selectTool(.shape)
        session.shapeKind = .rectangle
        session.foregroundColor = PaletteColor(red: 1, green: 0, blue: 0)
        session.beginShape(at: CGPoint(x: 0, y: 0))
        session.dragShape(to: CGPoint(x: 100, y: 100), square: false, fromCenter: false)
        session.finishShape()

        // Create a vector path covering only [25..75, 25..75].
        let rectPath = VectorPath.fromCGPath(CGPath(rect: CGRect(x: 25, y: 25, width: 50, height: 50), transform: nil), name: "Center")
        _ = session.addNewPath(name: rectPath.name, subpaths: rectPath.subpaths)
        session.addVectorMaskFromActivePath()
        #expect(session.hasActiveLayerVectorMask)

        // Export: inside (50, 50) opaque, outside (10, 10) transparent!
        let clipped = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        #expect(try alpha(in: clipped.image, x: 50, y: 50) == 255)
        #expect(try alpha(in: clipped.image, x: 10, y: 10) == 0)

        // Invert vector mask: inside (50, 50) transparent, outside (10, 10) opaque!
        session.invertVectorMask()
        let inverted = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        #expect(try alpha(in: inverted.image, x: 50, y: 50) == 0)
        #expect(try alpha(in: inverted.image, x: 10, y: 10) == 255)

        // Disable vector mask: both opaque!
        session.toggleVectorMaskEnabled()
        let disabled = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        #expect(try alpha(in: disabled.image, x: 50, y: 50) == 255)
        #expect(try alpha(in: disabled.image, x: 10, y: 10) == 255)

        // Re-enable, invert back, and rasterize -> becomes pixel LayerMask and clears vectorMask.
        session.toggleVectorMaskEnabled()
        session.invertVectorMask()
        session.rasterizeVectorMask()
        #expect(session.activeLayer?.vectorMask == nil)
        #expect(session.activeLayer?.mask != nil)
        let rasterized = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        #expect(try alpha(in: rasterized.image, x: 50, y: 50) == 255)
        #expect(try alpha(in: rasterized.image, x: 10, y: 10) == 0)
    }

    @Test func shapeBooleanOperationsCombineSelectedShapes() async throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)
        session.selectTool(.shape)
        session.shapeKind = .rectangle
        session.foregroundColor = PaletteColor(red: 0, green: 0.5, blue: 1)

        // Base square [10..70, 10..70]
        session.beginShape(at: CGPoint(x: 10, y: 10))
        session.dragShape(to: CGPoint(x: 70, y: 70), square: false, fromCenter: false)
        session.finishShape()
        let firstID = try #require(session.activeLayerID)

        // Front square [40..90, 40..90]
        session.beginShape(at: CGPoint(x: 40, y: 40))
        session.dragShape(to: CGPoint(x: 90, y: 90), square: false, fromCenter: false)
        session.finishShape()
        let secondID = try #require(session.activeLayerID)

        session.selectedLayerIDs = [firstID, secondID]
        #expect(session.canCombineSelectedShapes)

        // Subtract Front: leaves [10..70, 10..70] minus [40..70, 40..70].
        session.combineSelectedShapes(.subtract)
        let rendered = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        #expect(try alpha(in: rendered.image, x: 20, y: 20) == 255) // base kept
        #expect(try alpha(in: rendered.image, x: 55, y: 55) == 0)   // overlap subtracted
        #expect(try alpha(in: rendered.image, x: 80, y: 80) == 0)   // front removed

        // Undo restores both shapes, then test Intersect -> keeps ONLY [40..70, 40..70]!
        session.undo()
        session.selectedLayerIDs = [firstID, secondID]
        session.combineSelectedShapes(.intersect)
        let intersected = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        #expect(try alpha(in: intersected.image, x: 20, y: 20) == 0)
        #expect(try alpha(in: intersected.image, x: 55, y: 55) == 255)
        #expect(try alpha(in: intersected.image, x: 80, y: 80) == 0)
    }

    @Test func v32VectorMaskRoundTripsAndRejectsOlderVersions() async throws {
        let session = EditorSession()
        session.createDocument(width: 80, height: 80)
        session.selectTool(.shape)
        session.beginShape(at: CGPoint(x: 0, y: 0))
        session.dragShape(to: CGPoint(x: 80, y: 80), square: false, fromCenter: false)
        session.finishShape()

        let circle = VectorPath.fromCGPath(CGPath(ellipseIn: CGRect(x: 10, y: 10, width: 60, height: 60), transform: nil), name: "Circle")
        _ = session.addNewPath(name: circle.name, subpaths: circle.subpaths)
        session.addVectorMaskFromActivePath()
        let savedMask = try #require(session.activeLayer?.vectorMask)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vmask-v32-\(UUID().uuidString).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(try #require(session.projectSnapshot()), to: url)

        let loaded = try await ProjectStore.shared.load(from: url)
        #expect(loaded.manifest.layers.last?.vectorMask == savedMask)

        let manifestURL = url.appendingPathComponent("manifest.json")
        var manifest = try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
        #expect(manifest.version == ProjectManifest.current)
        manifest.version = 31
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        await #expect(throws: ProjectError.self) {
            _ = try await ProjectStore.shared.load(from: url)
        }
    }
}
