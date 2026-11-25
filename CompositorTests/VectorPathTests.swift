import CoreGraphics
import Foundation
import Testing
@testable import Compositor

@MainActor
struct VectorPathTests {
    @Test func penToolDrawsCurvesClosesAndConvertsToSelectionAndLayers() async throws {
        let session = EditorSession()
        session.createDocument(width: 120, height: 120)
        session.selectTool(.pen)
        session.foregroundColor = PaletteColor(red: 1, green: 0, blue: 0)

        // Draw a curved 3-anchor closed shape around (60, 60).
        session.penMouseDown(at: CGPoint(x: 60, y: 20), option: false, shift: false)
        session.penMouseDragged(to: CGPoint(x: 85, y: 20), option: false, shift: false)
        session.penMouseUp()

        session.penMouseDown(at: CGPoint(x: 100, y: 95), option: false, shift: false)
        session.penMouseUp()

        session.penMouseDown(at: CGPoint(x: 20, y: 95), option: false, shift: false)
        session.penMouseUp()

        // Click near the starting anchor to close the path.
        session.penMouseDown(at: CGPoint(x: 61, y: 21), option: false, shift: false)
        session.penMouseUp()

        let path = try #require(session.activePath)
        #expect(path.subpaths.count == 1)
        #expect(path.subpaths[0].isClosed)
        #expect(path.subpaths[0].anchors.count == 3)
        #expect(path.subpaths[0].anchors[0].handleOut != nil)
        #expect(path.subpaths[0].anchors[0].handleIn != nil)

        // Convert to Selection -> center is selected, corner is not.
        session.pathToSelection()
        let sel = try #require(session.selection)
        #expect(sel.path.contains(CGPoint(x: 60, y: 60)))
        #expect(!sel.path.contains(CGPoint(x: 5, y: 5)))

        // Fill Path & Stroke Path create new raster layers.
        let beforeCount = session.document?.layers.count ?? 0
        session.fillPath()
        #expect((session.document?.layers.count ?? 0) == beforeCount + 1)
        session.penStrokeWidth = 6
        session.strokePath()
        #expect((session.document?.layers.count ?? 0) == beforeCount + 2)

        // Selection -> Path round-trip.
        let pathCountBefore = session.document?.paths.count ?? 0
        let convertedID = session.selectionToPath()
        #expect(convertedID != nil)
        #expect((session.document?.paths.count ?? 0) == pathCountBefore + 1)
    }

    @Test func directSelectMovesAnchorAndBreaksTangentWithOption() throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)
        session.selectTool(.pen)
        session.penMouseDown(at: CGPoint(x: 50, y: 50), option: false, shift: false)
        session.penMouseDragged(to: CGPoint(x: 70, y: 50), option: false, shift: false)
        session.penMouseUp()

        let anchor0 = try #require(session.activePath?.subpaths.first?.anchors.first)
        #expect(anchor0.handleOut == CGPoint(x: 70, y: 50))
        #expect(anchor0.handleIn == CGPoint(x: 30, y: 50))

        // Switch to Direct Select and move handleOut with Option (broken tangent: handleIn stays at (30, 50)).
        session.penMode = .edit
        session.penMouseDown(at: CGPoint(x: 70, y: 50), option: true, shift: false)
        session.penMouseDragged(to: CGPoint(x: 70, y: 30), option: true, shift: false)
        session.penMouseUp()

        let updated = try #require(session.activePath?.subpaths.first?.anchors.first)
        #expect(updated.handleOut == CGPoint(x: 70, y: 30))
        #expect(updated.handleIn == CGPoint(x: 30, y: 50))
    }

    @Test func v31PathsRoundTripAndRejectOlderVersions() async throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)
        let sub = VectorSubpath(anchors: [
            PathAnchor(point: CGPoint(x: 10, y: 10), handleIn: CGPoint(x: 5, y: 10), handleOut: CGPoint(x: 20, y: 10)),
            PathAnchor(point: CGPoint(x: 80, y: 50)),
            PathAnchor(point: CGPoint(x: 10, y: 90)),
        ], isClosed: true)
        let id = try #require(session.addNewPath(name: "Hero Curve", subpaths: [sub]))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paths-v31-\(UUID().uuidString).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(try #require(session.projectSnapshot()), to: url)

        let loaded = try await ProjectStore.shared.load(from: url)
        let loadedPaths = try #require(loaded.manifest.paths)
        #expect(loadedPaths.count == 1)
        #expect(loadedPaths[0].id == id)
        #expect(loadedPaths[0].name == "Hero Curve")
        #expect(loadedPaths[0].subpaths == [sub])

        // Mutate manifest version to 30 -> must throw ProjectError.invalid.
        let manifestURL = url.appendingPathComponent("manifest.json")
        var manifest = try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
        #expect(manifest.version == ProjectManifest.current)
        manifest.version = 30
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        await #expect(throws: ProjectError.self) {
            _ = try await ProjectStore.shared.load(from: url)
        }
    }
}
