import AppKit
import Testing
@testable import Compositor

@MainActor
struct LayerLockTests {
    /// Creates an 8x8 RGBA asset whose left half is opaque red and right half is fully transparent.
    private func halfTransparentAsset() throws -> ImportedImage {
        let context = try BrushRaster.context(width: 8, height: 8, mask: false)
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 0, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 8))
        let image = try #require(context.makeImage())
        return ImportedImage(image: image, thumbnail: image, name: "Half")
    }

    private func rgba(of image: CGImage, atX x: Int, y: Int) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    @Test func lockAllBlocksPixelsPositionAppearanceAndStructure() throws {
        let session = EditorSession()
        session.createDocument(width: 16, height: 16)
        session.insert(try halfTransparentAsset())
        let id = try #require(session.activeLayerID)
        let originalName = try #require(session.activeLayer?.name)

        session.toggleLayerLock(.all)
        #expect(session.activeLayer?.lock.all == true)
        #expect(!session.canPaint)
        #expect(session.paintRefusal != nil)
        #expect(!session.canAdjustColors)
        #expect(!session.canInvert)
        #expect(!session.canTransform)
        #expect(!session.canAlignLayers)
        #expect(!session.canEditAppearance)
        #expect(!session.canEditOpacity)
        #expect(!session.canEditMask)
        #expect(!session.canEditEffects)
        #expect(session.hasStructureLockedSelection)

        session.renameLayer(id, to: "Renamed")
        #expect(session.activeLayer?.name == originalName)

        session.deleteActiveLayer()
        #expect(session.document?.layers.contains { $0.id == id } == true)

        // Unlocking restores full editability and participates in undo.
        session.toggleLayerLock(.all)
        #expect(session.activeLayer?.lock.isEmpty == true)
        #expect(session.canPaint && session.canTransform && session.canEditAppearance)

        session.undo()
        #expect(session.activeLayer?.lock.all == true)
    }

    @Test func lockPositionAndLockPixelsAreIndependent() throws {
        let session = EditorSession()
        session.createDocument(width: 16, height: 16)
        session.insert(try halfTransparentAsset())

        session.toggleLayerLock(.position)
        #expect(!session.canTransform)
        #expect(!session.canAlignLayers)
        #expect(session.canPaint)
        #expect(session.canAdjustColors)
        #expect(session.canEditAppearance)

        session.toggleLayerLock(.position)
        session.toggleLayerLock(.pixels)
        #expect(session.canTransform)
        #expect(!session.canPaint)
        #expect(!session.canAdjustColors)
        #expect(!session.canInvert)
        #expect(session.canEditAppearance)
        #expect(session.canEditMask)
    }

    @Test func folderLocksPropagateToDescendants() throws {
        let session = EditorSession()
        session.createDocument(width: 16, height: 16)
        session.addGroup()
        let folder = try #require(session.activeLayerID)
        session.insert(try halfTransparentAsset())
        let child = try #require(session.activeLayerID)
        #expect(session.activeLayer?.parentID == folder)

        session.selectLayer(folder)
        #expect(!session.canToggleLayerLock(.transparent))
        session.toggleLayerLock(.position)

        session.selectLayer(child)
        #expect(session.effectiveLock(for: child).blocksPosition)
        #expect(!session.canTransform)
        #expect(session.canPaint)

        session.selectLayer(folder)
        session.toggleLayerLock(.all)
        session.selectLayer(child)
        #expect(session.effectiveLock(for: child).blocksStructure)
        #expect(!session.canPaint)
        #expect(!session.canEditAppearance)
    }

    @Test func lockTransparentPixelsPreservesAlphaOnFillAndBrushAndErase() async throws {
        let session = EditorSession()
        session.createDocument(width: 8, height: 8)
        session.insert(try halfTransparentAsset())
        let id = try #require(session.activeLayerID)

        session.toggleLayerLock(.transparent)
        #expect(session.canPaint)

        // Fill with blue: opaque left half turns blue; transparent right half stays alpha 0.
        session.foregroundColor = PaletteColor(red: 0, green: 0, blue: 1)
        await session.fillSelection(with: .foreground)
        let afterFill = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let opaquePixel = try rgba(of: afterFill, atX: 1, y: 4)
        let transparentPixel = try rgba(of: afterFill, atX: 6, y: 4)
        #expect(opaquePixel.a == 255)
        #expect(opaquePixel.b == 255)
        #expect(opaquePixel.r == 0)
        #expect(transparentPixel.a == 0)

        // Brush stroke across the entire layer: still keeps right half transparent and paints left half green.
        session.selectTool(.brush)
        session.brushMode = .paint
        session.brushSettings.diameter = 12
        session.brushSettings.hardness = 1
        session.brushSettings.opacity = 1
        session.brushSettings.red = 0
        session.brushSettings.green = 1
        session.brushSettings.blue = 0
        session.beginBrush(at: CGPoint(x: 1, y: 4))
        session.continueBrush(at: CGPoint(x: 7, y: 4))
        await session.finishBrush()

        let afterBrush = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let paintedOpaque = try rgba(of: afterBrush, atX: 1, y: 4)
        let paintedTransparent = try rgba(of: afterBrush, atX: 6, y: 4)
        #expect(paintedOpaque.a == 255)
        #expect(paintedOpaque.g == 255)
        #expect(paintedTransparent.a == 0)

        // Eraser on transparent-locked layer paints background color (white) inside existing alpha without erasing alpha.
        session.backgroundColor = PaletteColor(red: 1, green: 1, blue: 1)
        session.brushMode = .erase
        session.beginBrush(at: CGPoint(x: 1, y: 4))
        session.continueBrush(at: CGPoint(x: 7, y: 4))
        await session.finishBrush()

        let afterErase = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let erasedOpaque = try rgba(of: afterErase, atX: 1, y: 4)
        let erasedTransparent = try rgba(of: afterErase, atX: 6, y: 4)
        #expect(erasedOpaque.a == 255)
        #expect(erasedOpaque.r == 255)
        #expect(erasedOpaque.g == 255)
        #expect(erasedOpaque.b == 255)
        #expect(erasedTransparent.a == 0)
    }

    @Test func layerLockRoundTripsAndRejectsOlderFormatVersions() async throws {
        let session = EditorSession()
        session.createDocument(width: 8, height: 8)
        session.insert(try halfTransparentAsset())
        let id = try #require(session.activeLayerID)
        session.toggleLayerLock(.transparent)
        session.toggleLayerLock(.position)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lock-\(UUID().uuidString).comp")
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = try #require(session.projectSnapshot())
        #expect(snapshot.manifest.version == ProjectManifest.current)
        try await ProjectStore.shared.save(snapshot, to: url)

        let loaded = try await ProjectStore.shared.load(from: url)
        let restored = try #require(loaded.documentLayers.first { $0.id == id })
        #expect(restored.lock == LayerLock(transparent: true, pixels: false, position: true, all: false))

        // Downgrading the saved manifest to version 22 with a non-empty lock must be rejected.
        let manifestURL = url.appendingPathComponent("manifest.json")
        let downgraded = try String(contentsOf: manifestURL, encoding: .utf8)
            .replacingOccurrences(of: "\"version\" : \(ProjectManifest.current)", with: "\"version\" : 22")
        try downgraded.write(to: manifestURL, atomically: true, encoding: .utf8)
        await #expect(throws: ProjectError.self) {
            _ = try await ProjectStore.shared.load(from: url)
        }
    }
}
