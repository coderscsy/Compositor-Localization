import AppKit
import Testing
@testable import Compositor

@MainActor
struct RetouchFiltersTests {
    private func makeImage(width: Int, height: Int, pixel: (Int, Int) -> (CGFloat, CGFloat, CGFloat, CGFloat)) throws -> CGImage {
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b, a) = pixel(x, y)
                let i = y * context.bytesPerRow + x * 4
                bytes[i] = UInt8((r * a * 255).rounded())
                bytes[i + 1] = UInt8((g * a * 255).rounded())
                bytes[i + 2] = UInt8((b * a * 255).rounded())
                bytes[i + 3] = UInt8((a * 255).rounded())
            }
        }
        return try #require(context.makeImage())
    }

    private func rgba(of image: CGImage, atX x: Int, y: Int) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    @Test func brightnessContrastAndVibranceAdjustExpectedly() throws {
        let midGray = try makeImage(width: 4, height: 4) { _, _ in (0.5, 0.5, 0.5, 1) }
        let brighter = try BrightnessContrastSettings(brightness: 80, contrast: 0).apply(midGray)
        #expect(try rgba(of: brighter, atX: 2, y: 2).r > 160)
        let darker = try BrightnessContrastSettings(brightness: -80, contrast: 0).apply(midGray)
        #expect(try rgba(of: darker, atX: 2, y: 2).r < 95)

        // Vibrance boosts muted blue more strongly than already saturated blue.
        let muted = try makeImage(width: 4, height: 4) { _, _ in (0.4, 0.4, 0.6, 1) }
        let boosted = try VibranceSettings(vibrance: 80, saturation: 0).apply(muted)
        let bp = try rgba(of: boosted, atX: 2, y: 2)
        #expect(Int(bp.b) - Int(bp.r) > 70)
    }

    @Test func thresholdAndPosterizeQuantizeCleanly() throws {
        let ramp = try makeImage(width: 256, height: 2) { x, _ in
            let v = CGFloat(x) / 255
            return (v, v, v, 1)
        }
        let cut = try ThresholdSettings(level: 128).apply(ramp)
        #expect(try rgba(of: cut, atX: 127, y: 0).r == 0)
        #expect(try rgba(of: cut, atX: 128, y: 0).r == 255)

        let post = try PosterizeSettings(levels: 4).apply(ramp)
        var distinct = Set<UInt8>()
        for x in 0..<256 { distinct.insert(try rgba(of: post, atX: x, y: 0).r) }
        #expect(distinct.count == 4)
        #expect(distinct.contains(0) && distinct.contains(255))
    }

    @Test func selectiveColorTargetsSpecificFamiliesOnly() throws {
        // Left half pure red, right half pure blue.
        let split = try makeImage(width: 8, height: 4) { x, _ in
            x < 4 ? (1, 0, 0, 1) : (0, 0, 1, 1)
        }
        var settings = SelectiveColorSettings()
        settings.reds.cyan = 100 // Removing red from Reds family (adds cyan)
        settings.relative = false
        let out = try settings.apply(split)
        let left = try rgba(of: out, atX: 1, y: 2)
        let right = try rgba(of: out, atX: 6, y: 2)
        #expect(left.r < 20)
        // Pure blue pixel must stay untouched.
        #expect(right.b == 255 && right.r == 0 && right.g == 0)
    }

    @Test func colorLookupParsesCubeAndApplies3DLUT() throws {
        // Minimal 2x2x2 cube that swaps Red and Blue channels!
        let cubeText = """
        # Test swap R <-> B
        TITLE "Swap RB"
        LUT_3D_SIZE 2
        0.0 0.0 0.0
        0.0 0.0 1.0
        0.0 1.0 0.0
        0.0 1.0 1.0
        1.0 0.0 0.0
        1.0 0.0 1.0
        1.0 1.0 0.0
        1.0 1.0 1.0
        """
        let parsed = try ColorLookupParser.parse(cubeText)
        #expect(parsed.title == "Swap RB")
        #expect(parsed.dimension == 2)
        #expect(parsed.table.count == 2 * 2 * 2 * 3)

        var lut = ColorLookupSettings()
        lut.setCustomLUT(title: parsed.title, dimension: parsed.dimension, table: parsed.table)
        lut.intensity = 100

        let red = try makeImage(width: 4, height: 4) { _, _ in (1, 0, 0, 1) }
        let swapped = try lut.apply(red)
        let px = try rgba(of: swapped, atX: 2, y: 2)
        #expect(px.r == 0 && px.g == 0 && px.b == 255 && px.a == 255)
    }

    @Test func highPassCentersFlatAreasOnMidGrayAndPreservesEdges() throws {
        // Uniform color must become exact 50% gray (128); a sharp edge produces light/dark halo around 128.
        let flat = try makeImage(width: 16, height: 16) { _, _ in (0.8, 0.2, 0.4, 1) }
        var settings = FilterSettings()
        settings.highPassRadius = 3
        let flatHP = try PixelFilter.run(FilterJob(kind: .highPass, image: flat, settings: settings, scale: 1, selection: nil, mapping: .identity))
        let mid = try rgba(of: flatHP, atX: 8, y: 8)
        #expect(abs(Int(mid.r) - 128) <= 2 && abs(Int(mid.g) - 128) <= 2 && abs(Int(mid.b) - 128) <= 2)

        let step = try makeImage(width: 16, height: 16) { x, _ in x < 8 ? (0.2, 0.2, 0.2, 1) : (0.8, 0.8, 0.8, 1) }
        let edgeHP = try PixelFilter.run(FilterJob(kind: .highPass, image: step, settings: settings, scale: 1, selection: nil, mapping: .identity))
        let darkSide = try rgba(of: edgeHP, atX: 7, y: 8)
        let brightSide = try rgba(of: edgeHP, atX: 8, y: 8)
        #expect(darkSide.r < 100)
        #expect(brightSide.r > 155)
    }

    @Test func offsetWrapsAndSupportsTransparentMode() throws {
        let marker = try makeImage(width: 8, height: 8) { x, y in
            (x == 1 && y == 1) ? (1, 0, 0, 1) : (0, 0, 1, 1)
        }
        let wrapped = try OffsetSettings(horizontal: 3, vertical: 2, edgeMode: .wrapAround).apply(marker)
        #expect(try rgba(of: wrapped, atX: 4, y: 3).r == 255)
        #expect(try rgba(of: wrapped, atX: 0, y: 0).b == 255)

        let transparent = try OffsetSettings(horizontal: 3, vertical: 2, edgeMode: .transparent).apply(marker)
        #expect(try rgba(of: transparent, atX: 4, y: 3).r == 255)
        #expect(try rgba(of: transparent, atX: 0, y: 0).a == 0)
    }

    @Test func version25AdjustmentsRoundTripAndRejectVersion24() async throws {
        let session = EditorSession()
        session.createDocument(width: 16, height: 16)
        let base = try makeImage(width: 16, height: 16) { _, _ in (0.6, 0.4, 0.3, 1) }
        session.insert(ImportedImage(image: base, thumbnail: base, name: "Base"))

        session.addAdjustment(.vibrance)
        let vibID = try #require(session.activeLayerID)
        if let idx = session.document?.layers.firstIndex(where: { $0.id == vibID }) {
            session.document?.layers[idx].adjustment?.vibrance = VibranceSettings(vibrance: 45, saturation: -10)
        }
        session.addAdjustment(.highPass)
        let hpID = try #require(session.activeLayerID)
        if let idx = session.document?.layers.firstIndex(where: { $0.id == hpID }) {
            session.document?.layers[idx].adjustment?.filterLayer.highPass = HighPassLayerSettings(radius: 4.5)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("retouch-\(UUID().uuidString).comp")
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = try #require(session.projectSnapshot())
        #expect(snapshot.manifest.version == ProjectManifest.current)
        try await ProjectStore.shared.save(snapshot, to: url)

        let loaded = try await ProjectStore.shared.load(from: url)
        let restoredVib = try #require(loaded.documentLayers.first { $0.id == vibID }?.adjustment)
        #expect(restoredVib.vibrance == VibranceSettings(vibrance: 45, saturation: -10))
        let restoredHP = try #require(loaded.documentLayers.first { $0.id == hpID }?.adjustment)
        #expect(restoredHP.filterLayer.resolvedHighPass.radius == 4.5)

        // Exporting with the adjustment layers active must succeed cleanly.
        let exported = try await ImageExporter.shared.render(loaded)
        #expect(exported.image.width == 16 && exported.image.height == 16)

        // Downgrading the saved manifest to version 24 must be rejected.
        let manifestURL = url.appendingPathComponent("manifest.json")
        let downgraded = try String(contentsOf: manifestURL, encoding: .utf8)
            .replacingOccurrences(of: "\"version\" : \(ProjectManifest.current)", with: "\"version\" : 24")
        try downgraded.write(to: manifestURL, atomically: true, encoding: .utf8)
        await #expect(throws: ProjectError.self) {
            _ = try await ProjectStore.shared.load(from: url)
        }
    }
}
