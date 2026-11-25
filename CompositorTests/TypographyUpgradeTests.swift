import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Compositor

@MainActor
struct TypographyUpgradeTests {
    private func nonTransparentCount(_ image: CGImage) throws -> Int {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                         bytesPerRow: image.width * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let ptr = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        var count = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                if ptr[y * ctx.bytesPerRow + x * 4 + 3] > 20 { count += 1 }
            }
        }
        return count
    }

    @Test func verticalTextProducesTallLayoutAndDrawsCharacters() throws {
        var style = LayerTextStyle()
        style.content = "HELLO"
        style.fontSize = 32
        style.vertical = true
        let image = try EditorSession.textImage(style)
        #expect(image.height > image.width)
        #expect(try nonTransparentCount(image) > 100)
    }

    @Test func underlineStrikethroughAllCapsAndBaselineShiftApply() throws {
        var plain = LayerTextStyle()
        plain.content = "abc"
        plain.fontSize = 36
        plain.allCaps = false

        var styled = plain
        styled.underline = true
        styled.strikethrough = true
        styled.allCaps = true
        styled.baselineShift = 8
        styled.alignment = .justified

        let attr = EditorSession.attributedText(styled)
        #expect(attr.string == "ABC")
        #expect(attr.attribute(.underlineStyle, at: 0, effectiveRange: nil) != nil)
        #expect(attr.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) != nil)
        #expect((attr.attribute(.baselineOffset, at: 0, effectiveRange: nil) as? CGFloat) == 8)

        let imgPlain = try EditorSession.textImage(plain)
        let imgStyled = try EditorSession.textImage(styled)
        #expect(try nonTransparentCount(imgStyled) > nonTransparentCount(imgPlain))
    }

    @Test func warpTextDeformsRasterAndExpandsBounds() throws {
        var style = LayerTextStyle()
        style.content = "WARP"
        style.fontSize = 40
        let flat = try EditorSession.textImage(style)

        style.warp = TextWarpSettings(style: .arc, bend: 0.65, horizontalDistortion: 0.1, verticalDistortion: 0)
        let warped = try EditorSession.textImage(style)
        #expect(warped.height > flat.height)
        #expect(try nonTransparentCount(warped) > 100)

        style.warp = TextWarpSettings(style: .flag, bend: 0.5)
        let flagged = try EditorSession.textImage(style)
        #expect(try nonTransparentCount(flagged) > 100)
    }

    @Test func textOnPathLaysGlyphsAlongCurvedVectorPath() throws {
        let curve = VectorPath(name: "Arc", subpaths: [
            VectorSubpath(anchors: [
                PathAnchor(point: CGPoint(x: 20, y: 120), handleOut: CGPoint(x: 80, y: 20)),
                PathAnchor(point: CGPoint(x: 220, y: 120), handleIn: CGPoint(x: 160, y: 20)),
            ], isClosed: false)
        ])
        var style = LayerTextStyle()
        style.content = "CURVED PATH"
        style.fontSize = 24
        style.path = curve
        let image = try EditorSession.textImage(style)
        #expect(image.width >= 200)
        #expect(try nonTransparentCount(image) > 150)
    }

    @Test func v33TypographyRoundTripsAndRejectsOlderVersions() async throws {
        let session = EditorSession()
        session.createDocument(width: 240, height: 160)
        var style = LayerTextStyle()
        style.content = "Hello Warp"
        style.fontSize = 32
        style.underline = true
        style.allCaps = true
        style.alignment = .justified
        style.warp = TextWarpSettings(style: .arch, bend: 0.4)
        let draft = TextDraft(documentID: try #require(session.document?.id), layerID: nil,
                              origin: CGPoint(x: 10, y: 10), style: style)
        #expect(session.applyText(draft))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("type-v33-\(UUID().uuidString).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(try #require(session.projectSnapshot()), to: url)

        let loaded = try await ProjectStore.shared.load(from: url)
        #expect(loaded.manifest.layers.last?.text == style)

        let manifestURL = url.appendingPathComponent("manifest.json")
        var manifest = try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
        #expect(manifest.version == ProjectManifest.current)
        manifest.version = 32
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        await #expect(throws: ProjectError.self) {
            _ = try await ProjectStore.shared.load(from: url)
        }
    }
}
