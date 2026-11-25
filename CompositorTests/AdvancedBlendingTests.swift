import AppKit
import CoreGraphics
import Testing
@testable import Compositor

@MainActor
struct AdvancedBlendingTests {
    private func solidAsset(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1, name: String = "Solid") throws -> ImportedImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: width * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(colorSpace: space, components: [r, g, b, a])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(ctx.makeImage())
        return ImportedImage(image: image, thumbnail: image, name: name)
    }

    private func splitAsset(width: Int, height: Int, left: (CGFloat, CGFloat, CGFloat), right: (CGFloat, CGFloat, CGFloat)) throws -> ImportedImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: width * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        ctx.setFillColor(CGColor(colorSpace: space, components: [left.0, left.1, left.2, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        ctx.setFillColor(CGColor(colorSpace: space, components: [right.0, right.1, right.2, 1])!)
        ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        let image = try #require(ctx.makeImage())
        return ImportedImage(image: image, thumbnail: image, name: "Split")
    }

    private func rgba(_ image: CGImage, x: Int = 0, y: Int = 0) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                         bytesPerRow: image.width * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let ptr = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * ctx.bytesPerRow + x * 4
        return (ptr[offset], ptr[offset + 1], ptr[offset + 2], ptr[offset + 3])
    }

    @Test func darkerColorAndLighterColorCompareWholePixelLuminance() async throws {
        let session = EditorSession()
        session.createDocument(width: 4, height: 4)
        // Green (luma ~ 0.53) underneath Red (luma ~ 0.30).
        session.insert(try solidAsset(width: 4, height: 4, r: 0, g: 0.9, b: 0, name: "Green"))
        session.insert(try solidAsset(width: 4, height: 4, r: 1, g: 0, b: 0, name: "Red"))

        session.setLayerBlendMode(.darkerColor)
        let darker = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let dp = try rgba(darker.image, x: 2, y: 2)
        // Darker Color picks the entire Red pixel (unlike Darken which would produce black 0,0,0).
        #expect(dp.r > 245 && dp.g < 10 && dp.b < 10 && dp.a == 255)

        session.setLayerBlendMode(.lighterColor)
        let lighter = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let lp = try rgba(lighter.image, x: 2, y: 2)
        // Lighter Color picks the entire Green pixel (unlike Lighten which would produce yellow 255,230,0).
        #expect(lp.r < 10 && lp.g > 220 && lp.b < 10 && lp.a == 255)
    }

    @Test func dissolveScattersOpaquePixelsByOpacity() async throws {
        let session = EditorSession()
        session.createDocument(width: 32, height: 32)
        session.insert(try solidAsset(width: 32, height: 32, r: 0, g: 0, b: 1, name: "Blue"))
        session.insert(try solidAsset(width: 32, height: 32, r: 1, g: 0, b: 0, name: "Red"))
        session.setLayerBlendMode(.dissolve)
        session.setLayerOpacity(0.5)

        let raster = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        var redCount = 0
        var blueCount = 0
        for y in 0..<32 {
            for x in 0..<32 {
                let p = try rgba(raster.image, x: x, y: y)
                #expect(p.a == 255)
                if p.r > 240 && p.b < 10 { redCount += 1 }
                else if p.b > 240 && p.r < 10 { blueCount += 1 }
            }
        }
        // Every pixel is either pure red or pure blue (no partial blend), roughly 50/50.
        #expect(redCount + blueCount == 32 * 32)
        #expect(redCount > 350 && redCount < 675)
    }

    @Test func blendIfHidesByThisLayerAndUnderlyingLayerWithFeathering() async throws {
        let session = EditorSession()
        session.createDocument(width: 8, height: 4)
        // Bottom: solid blue. Top: left black (0), right white (255).
        session.insert(try solidAsset(width: 8, height: 4, r: 0, g: 0, b: 1, name: "Blue"))
        session.insert(try splitAsset(width: 8, height: 4, left: (0, 0, 0), right: (1, 1, 1)))
        var thisOnly = BlendIfSettings()
        thisOnly.thisLayer = BlendIfRange(blackLow: 100, blackHigh: 100, whiteLow: 255, whiteHigh: 255)
        session.setLayerBlendIf(thisOnly)

        let r1 = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let left1 = try rgba(r1.image, x: 1, y: 2)
        let right1 = try rgba(r1.image, x: 6, y: 2)
        // Dark left half of top layer is hidden -> blue shows through. White right half stays white.
        #expect(left1.b > 240 && left1.r < 10)
        #expect(right1.r > 240 && right1.g > 240 && right1.b > 240)

        // Underlying Layer with split feathering: bottom left dark (0), right mid-gray (150); top solid red.
        let s2 = EditorSession()
        s2.createDocument(width: 8, height: 4)
        s2.insert(try splitAsset(width: 8, height: 4, left: (0, 0, 0), right: (150.0 / 255.0, 150.0 / 255.0, 150.0 / 255.0)))
        s2.insert(try solidAsset(width: 8, height: 4, r: 1, g: 0, b: 0, name: "Red"))
        var underFeathered = BlendIfSettings()
        underFeathered.underlyingLayer = BlendIfRange(blackLow: 0, blackHigh: 0, whiteLow: 100, whiteHigh: 200)
        s2.setLayerBlendIf(underFeathered)

        let r2 = try await ImageExporter.shared.render(try #require(s2.projectSnapshot()))
        let darkSide = try rgba(r2.image, x: 1, y: 2)
        let midSide = try rgba(r2.image, x: 6, y: 2)
        // Dark side (luma 0 <= 100): full red. Mid-gray (150, halfway between 100 and 200): ~50% red over 150 gray.
        #expect(darkSide.r > 245 && darkSide.g < 5)
        #expect(midSide.r > 180 && midSide.r < 225)
        #expect(midSide.g > 60 && midSide.g < 95)
    }

    @Test func isolatedFolderBlendModesIsolateContentsAndApplyFolderBlendMode() async throws {
        let session = EditorSession()
        session.createDocument(width: 8, height: 4)
        // Base canvas: white (1, 1, 1).
        session.insert(try solidAsset(width: 8, height: 4, r: 1, g: 1, b: 1, name: "White"))
        session.addGroup()
        let folderID = try #require(session.activeLayerID)
        // Put a left-half-only gray (0.5) layer + an Invert adjustment inside the folder.
        session.insert(try solidAsset(width: 4, height: 4, r: 0.5, g: 0.5, b: 0.5, name: "LeftHalf"))
        session.addAdjustment(.invert)

        // Default folder is Pass Through: Invert affects the exposed white right half -> becomes black.
        let passThroughRaster = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let ptRight = try rgba(passThroughRaster.image, x: 6, y: 2)
        #expect(ptRight.r < 10 && ptRight.g < 10 && ptRight.b < 10)

        // Switch folder to Normal (isolated): Invert stays inside the folder -> exposed right half stays white!
        session.selectLayer(folderID)
        session.setLayerBlendMode(.normal)
        #expect(session.activeLayer?.isPassThrough == false)
        let isolatedNormal = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let isoRight = try rgba(isolatedNormal.image, x: 6, y: 2)
        #expect(isoRight.r > 245 && isoRight.g > 245 && isoRight.b > 245)

        // Folder with Multiply blend mode: bottom green (0, 1, 0), folder containing white/yellow -> multiplies!
        let s2 = EditorSession()
        s2.createDocument(width: 4, height: 4)
        s2.insert(try solidAsset(width: 4, height: 4, r: 0.5, g: 0.5, b: 0.5, name: "Gray50"))
        s2.addGroup()
        let mulFolder = try #require(s2.activeLayerID)
        s2.insert(try solidAsset(width: 4, height: 4, r: 0.5, g: 0.5, b: 0.5, name: "Inner50"))
        s2.selectLayer(mulFolder)
        s2.setLayerBlendMode(.multiply)
        let mulRaster = try await ImageExporter.shared.render(try #require(s2.projectSnapshot()))
        let mp = try rgba(mulRaster.image, x: 2, y: 2)
        // 0.5 * 0.5 = 0.25 (~64)
        #expect(abs(Int(mp.r) - 64) <= 3)
    }

    @Test func version26PersistsBlendIfIsolatedFoldersAndCustomModesAndRejectsVersion25() async throws {
        let session = EditorSession()
        session.createDocument(width: 4, height: 4)
        session.addGroup()
        let folderID = try #require(session.activeLayerID)
        session.setLayerBlendMode(.multiply)
        session.insert(try solidAsset(width: 4, height: 4, r: 1, g: 0.2, b: 0.2, name: "Top"))
        let topID = try #require(session.activeLayerID)
        session.setLayerBlendMode(.darkerColor)
        let bif = BlendIfSettings(channel: .red,
                                  thisLayer: BlendIfRange(blackLow: 10, blackHigh: 40, whiteLow: 200, whiteHigh: 240),
                                  underlyingLayer: BlendIfRange(blackLow: 20, blackHigh: 60, whiteLow: 210, whiteHigh: 250))
        session.setLayerBlendIf(bif)

        let snapshot = try #require(session.projectSnapshot())
        #expect(snapshot.manifest.version == 26)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AdvancedBlend-\(UUID()).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(snapshot, to: url)

        let loaded = try await ProjectStore.shared.load(from: url)
        let loadedFolder = try #require(loaded.documentLayers.first { $0.id == folderID })
        let loadedTop = try #require(loaded.documentLayers.first { $0.id == topID })
        #expect(loadedFolder.isGroup && !loadedFolder.isPassThrough && loadedFolder.blendMode == .multiply)
        #expect(loadedTop.blendMode == .darkerColor && loadedTop.blendIf == bif)

        // Tamper manifest down to version 25: must be rejected.
        let manifestURL = url.appendingPathComponent("manifest.json")
        var tampered = try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
        tampered.version = 25
        try JSONEncoder().encode(tampered).write(to: manifestURL)
        await #expect(throws: ProjectError.self) {
            _ = try await ProjectStore.shared.load(from: url)
        }
    }

    @Test func psdRoundTripsNewBlendModesAndFolderBlendModes() async throws {
        let session = EditorSession()
        session.createDocument(width: 4, height: 4)
        session.addGroup()
        let folderID = try #require(session.activeLayerID)
        session.setLayerBlendMode(.screen)
        session.insert(try solidAsset(width: 4, height: 4, r: 1, g: 0, b: 0, name: "Dissolved"))
        session.setLayerBlendMode(.dissolve)
        session.insert(try solidAsset(width: 4, height: 4, r: 0, g: 1, b: 0, name: "Darker"))
        session.setLayerBlendMode(.darkerColor)
        session.insert(try solidAsset(width: 4, height: 4, r: 0, g: 0, b: 1, name: "Lighter"))
        session.setLayerBlendMode(.lighterColor)

        let snapshot = try #require(session.projectSnapshot())
        let (psdData, _) = try await ImageExporter.shared.psdData(snapshot)
        let parsed = try PSDReader.read(psdData)
        let imported = try PSDDocumentBuilder.makeImport(parsed)
        #expect(imported.conversions.isEmpty)

        let importedFolder = try #require(imported.layers.first { $0.isGroup })
        #expect(!importedFolder.isPassThrough && importedFolder.blendMode == .screen)
        #expect(imported.layers.first { $0.name == "Dissolved" }?.blendMode == .dissolve)
        #expect(imported.layers.first { $0.name == "Darker" }?.blendMode == .darkerColor)
        #expect(imported.layers.first { $0.name == "Lighter" }?.blendMode == .lighterColor)
        _ = folderID
    }
}
