import AppKit
import Testing
@testable import Compositor

@MainActor
struct FillOpacityTests {
    private func solidAsset(width: Int = 16, height: Int = 16, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> ImportedImage {
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [red, green, blue, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        return ImportedImage(image: image, thumbnail: image, name: "Solid")
    }

    private func rgba(of image: CGImage, atX x: Int, y: Int) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    @Test func plainLayerMultipliesOpacityAndFillOpacity() async throws {
        let session = EditorSession()
        session.createDocument(width: 8, height: 8)
        session.insert(try solidAsset(width: 8, height: 8, red: 0, green: 0, blue: 0))
        session.insert(try solidAsset(width: 8, height: 8, red: 1, green: 1, blue: 1))

        session.setLayerFillOpacity(0.5)
        let half = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let mid = try rgba(of: half, atX: 4, y: 4)
        #expect(abs(Int(mid.r) - 128) <= 3)

        session.setLayerOpacity(0.5)
        let quarter = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let q = try rgba(of: quarter, atX: 4, y: 4)
        #expect(abs(Int(q.r) - 64) <= 3)
    }

    @Test func zeroFillKeepsStrokeAndColorOverlayVisibleWhileHidingInteriorPixels() async throws {
        let session = EditorSession()
        session.createDocument(width: 32, height: 32)
        session.insert(try solidAsset(width: 12, height: 12, red: 1, green: 0, blue: 0))
        let id = try #require(session.activeLayerID)
        // Center the 12x12 square at (10, 10) -> covers x: 10..<22, y: 10..<22.
        if let index = session.document?.layers.firstIndex(where: { $0.id == id }) {
            session.document?.layers[index].transform.origin = CGPoint(x: 10, y: 10)
        }
        // Add an outside blue stroke (size 4) and set Fill = 0%, Opacity = 100%.
        var effects = LayerEffects()
        effects.stroke = StrokeEffect(size: 4, red: 0, green: 0, blue: 1, opacity: 1, inside: false)
        if let index = session.document?.layers.firstIndex(where: { $0.id == id }) {
            session.document?.layers[index].effects = effects
        }
        session.setLayerFillOpacity(0)

        let hollow = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        // Center of the square (16, 16) must be completely transparent (hollow!).
        let center = try rgba(of: hollow, atX: 16, y: 16)
        #expect(center.a == 0)
        // Outside stroke at (8, 16) must still be solid blue at full opacity.
        let strokePixel = try rgba(of: hollow, atX: 8, y: 16)
        #expect(strokePixel.a == 255)
        #expect(strokePixel.b >= 250 && strokePixel.r <= 5)

        // Adding a green Color Overlay at 100% with Fill = 0% must still fill the interior green.
        effects.colorOverlay = ColorOverlayEffect(red: 0, green: 1, blue: 0, opacity: 1)
        if let index = session.document?.layers.firstIndex(where: { $0.id == id }) {
            session.document?.layers[index].effects = effects
        }
        let overlaid = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let overlaidCenter = try rgba(of: overlaid, atX: 16, y: 16)
        #expect(overlaidCenter.a == 255)
        #expect(overlaidCenter.g >= 250 && overlaidCenter.r <= 5)
    }

    @Test func fillDragIsOneUndoAndRespectsGroupsAndLocks() throws {
        let session = EditorSession()
        session.createDocument(width: 8, height: 8)
        session.insert(try solidAsset(width: 8, height: 8, red: 1, green: 0, blue: 0))
        let count = session.history.undoCount

        session.beginFillOpacityEdit()
        for step in [0.8, 0.6, 0.3] { session.setLayerFillOpacity(step) }
        session.finishFillOpacityEdit()
        #expect(session.history.undoCount == count + 1)
        #expect(session.activeLayer?.fillOpacity == 0.3)

        session.undo()
        #expect(session.activeLayer?.fillOpacity == 1)

        session.toggleLayerLock(.all)
        #expect(!session.canEditFillOpacity)
        session.toggleLayerLock(.all)

        session.addGroup()
        #expect(!session.canEditFillOpacity)
    }

    @Test func fillOpacityRoundTripsAndRejectsOlderFormatVersions() async throws {
        let session = EditorSession()
        session.createDocument(width: 8, height: 8)
        session.insert(try solidAsset(width: 8, height: 8, red: 0.5, green: 0.5, blue: 0.5))
        let id = try #require(session.activeLayerID)
        session.setLayerFillOpacity(0.35)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fill-\(UUID().uuidString).comp")
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = try #require(session.projectSnapshot())
        #expect(snapshot.manifest.version == ProjectManifest.current)
        try await ProjectStore.shared.save(snapshot, to: url)

        let loaded = try await ProjectStore.shared.load(from: url)
        let restored = try #require(loaded.documentLayers.first { $0.id == id })
        #expect(abs(restored.fillOpacity - 0.35) < 0.0001)

        // Downgrading the saved manifest to version 23 with fillOpacity present must be rejected.
        let manifestURL = url.appendingPathComponent("manifest.json")
        let downgraded = try String(contentsOf: manifestURL, encoding: .utf8)
            .replacingOccurrences(of: "\"version\" : \(ProjectManifest.current)", with: "\"version\" : 23")
        try downgraded.write(to: manifestURL, atomically: true, encoding: .utf8)
        await #expect(throws: ProjectError.self) {
            _ = try await ProjectStore.shared.load(from: url)
        }
    }
}
