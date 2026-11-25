import AppKit
import CoreGraphics
import Testing
@testable import Compositor

@MainActor
struct GradientUpgradeTests {
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

    @Test func multiStopCustomGradientRendersThreeDistinctColorBands() async throws {
        let session = EditorSession()
        session.createDocument(width: 40, height: 10)
        session.addBlankLayer()
        session.selectTool(.gradient)
        session.fillToolMode = .gradient
        session.gradientSettings.shape = .linear
        session.gradientSettings.style = .custom
        session.gradientSettings.customStops = [
            GradientOverlayStop(position: 0.0, red: 1, green: 0, blue: 0, alpha: 1),
            GradientOverlayStop(position: 0.5, red: 0, green: 1, blue: 0, alpha: 1),
            GradientOverlayStop(position: 1.0, red: 0, green: 0, blue: 1, alpha: 1),
        ]
        session.beginGradient(at: CGPoint(x: 0, y: 5))
        session.moveGradient(end: CGPoint(x: 40, y: 5))
        await session.commitGradient()

        let raster = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let left = try rgba(raster.image, x: 1, y: 5)
        let mid = try rgba(raster.image, x: 20, y: 5)
        let right = try rgba(raster.image, x: 38, y: 5)
        #expect(left.r > 230 && left.g < 25)
        #expect(mid.g > 230 && mid.r < 25 && mid.b < 25)
        #expect(right.b > 230 && right.g < 25)
    }

    @Test func angleReflectedAndDiamondShapesRenderExpectedGeometry() async throws {
        let stops = [
            GradientOverlayStop(position: 0, red: 1, green: 0, blue: 0, alpha: 1),
            GradientOverlayStop(position: 1, red: 0, green: 0, blue: 1, alpha: 1),
        ]

        // Reflected: symmetric on both sides of start point!
        let s1 = EditorSession()
        s1.createDocument(width: 40, height: 10)
        s1.addBlankLayer()
        s1.selectTool(.gradient)
        s1.gradientSettings.shape = .reflected
        s1.gradientSettings.style = .custom
        s1.gradientSettings.customStops = stops
        s1.beginGradient(at: CGPoint(x: 20, y: 5))
        s1.moveGradient(end: CGPoint(x: 38, y: 5))
        await s1.commitGradient()
        let r1 = try await ImageExporter.shared.render(try #require(s1.projectSnapshot()))
        let leftRef = try rgba(r1.image, x: 2, y: 5)
        let centerRef = try rgba(r1.image, x: 20, y: 5)
        let rightRef = try rgba(r1.image, x: 38, y: 5)
        #expect(centerRef.r > 230 && leftRef.b > 220 && rightRef.b > 220)

        // Diamond: center is red, corners are blue.
        let s2 = EditorSession()
        s2.createDocument(width: 40, height: 40)
        s2.addBlankLayer()
        s2.selectTool(.gradient)
        s2.gradientSettings.shape = .diamond
        s2.gradientSettings.style = .custom
        s2.gradientSettings.customStops = stops
        s2.beginGradient(at: CGPoint(x: 20, y: 20))
        s2.moveGradient(end: CGPoint(x: 38, y: 20))
        await s2.commitGradient()
        let r2 = try await ImageExporter.shared.render(try #require(s2.projectSnapshot()))
        let centerDia = try rgba(r2.image, x: 20, y: 20)
        let cornerDia = try rgba(r2.image, x: 2, y: 2)
        #expect(centerDia.r > 230 && cornerDia.b > 230)

        // Angle: sweeps around the center (0° = red, 180° = mid purple, ~350° = blue).
        let s3 = EditorSession()
        s3.createDocument(width: 40, height: 40)
        s3.addBlankLayer()
        s3.selectTool(.gradient)
        s3.gradientSettings.shape = .angle
        s3.gradientSettings.style = .custom
        s3.gradientSettings.customStops = stops
        s3.beginGradient(at: CGPoint(x: 20, y: 20))
        s3.moveGradient(end: CGPoint(x: 38, y: 20))
        await s3.commitGradient()
        let r3 = try await ImageExporter.shared.render(try #require(s3.projectSnapshot()))
        let belowAxis = try rgba(r3.image, x: 35, y: 22)
        let aboveAxis = try rgba(r3.image, x: 35, y: 18)
        #expect(belowAxis.r > 200 && aboveAxis.b > 200)
    }

    @Test func liveGradientFillLayerCreatesUpdatesAndPersistsInVersion29() async throws {
        let session = EditorSession()
        session.createDocument(width: 32, height: 32)
        let fill = LiveGradientFill(
            shape: .linear, angle: 0, scale: 100, reversed: false,
            stops: [
                GradientOverlayStop(position: 0, red: 0, green: 0, blue: 0, alpha: 1),
                GradientOverlayStop(position: 1, red: 1, green: 1, blue: 1, alpha: 1),
            ]
        )
        session.addGradientFillLayer(fill)
        let id = try #require(session.activeLayerID)
        #expect(session.activeLayer?.gradientFill == fill)

        let r1 = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        #expect(try rgba(r1.image, x: 1, y: 16).r < 25)
        #expect(try rgba(r1.image, x: 30, y: 16).r > 230)

        // Non-destructively reverse it in place.
        var updated = fill
        updated.reversed = true
        session.updateLiveGradientFill(updated, on: id)
        let r2 = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        #expect(try rgba(r2.image, x: 1, y: 16).r > 230)
        #expect(try rgba(r2.image, x: 30, y: 16).r < 25)

        // Persist in format v29 and reject v28.
        let snapshot = try #require(session.projectSnapshot())
        #expect(snapshot.manifest.version >= 29)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LiveGradient-\(UUID()).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(snapshot, to: url)

        let loaded = try await ProjectStore.shared.load(from: url)
        #expect(loaded.documentLayers.first { $0.id == id }?.gradientFill == updated)

        let manifestURL = url.appendingPathComponent("manifest.json")
        var tampered = try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
        tampered.version = 28
        try JSONEncoder().encode(tampered).write(to: manifestURL)
        await #expect(throws: ProjectError.self) {
            _ = try await ProjectStore.shared.load(from: url)
        }
    }
}
