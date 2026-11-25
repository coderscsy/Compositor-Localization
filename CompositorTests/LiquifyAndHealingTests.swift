import AppKit
import CoreGraphics
import Testing
@testable import Compositor

@MainActor
struct LiquifyAndHealingTests {
    private func dotAsset(size: Int = 64, dotRadius: CGFloat = 10) throws -> ImportedImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                         bytesPerRow: size * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        ctx.setFillColor(CGColor(colorSpace: space, components: [0, 0, 0, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
        let c = CGFloat(size) / 2
        ctx.fillEllipse(in: CGRect(x: c - dotRadius, y: c - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        let image = try #require(ctx.makeImage())
        return ImportedImage(image: image, thumbnail: image, name: "Dot")
    }

    private func whiteCount(_ image: CGImage) throws -> Int {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                         bytesPerRow: image.width * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let ptr = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        var count = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                if ptr[y * ctx.bytesPerRow + x * 4] > 128 { count += 1 }
            }
        }
        return count
    }

    @Test func bloatExpandsAndPuckerContractsCenterCircle() async throws {
        let base = try dotAsset(size: 64, dotRadius: 10)
        let baseCount = try whiteCount(base.image)

        // Bloat expands the white circle.
        let sBloat = EditorSession()
        sBloat.createDocument(width: 64, height: 64)
        sBloat.insert(base)
        sBloat.selectTool(.blur)
        sBloat.blurMode = .liquify
        sBloat.liquifyMode = .bloat
        sBloat.brushSettings.diameter = 48
        sBloat.brushSettings.hardness = 0.2
        sBloat.brushSettings.opacity = 1
        sBloat.beginBrush(at: CGPoint(x: 32, y: 32))
        for _ in 0..<4 { sBloat.continueBrush(at: CGPoint(x: 34, y: 32)); sBloat.continueBrush(at: CGPoint(x: 32, y: 32)) }
        sBloat.finishBrushImmediately()
        let bloated = try await ImageExporter.shared.render(try #require(sBloat.projectSnapshot()))
        #expect(try whiteCount(bloated.image) > baseCount + 40)

        // Pucker contracts the white circle.
        let sPucker = EditorSession()
        sPucker.createDocument(width: 64, height: 64)
        sPucker.insert(base)
        sPucker.selectTool(.blur)
        sPucker.blurMode = .liquify
        sPucker.liquifyMode = .pucker
        sPucker.brushSettings.diameter = 48
        sPucker.brushSettings.hardness = 0.2
        sPucker.brushSettings.opacity = 1
        sPucker.beginBrush(at: CGPoint(x: 32, y: 32))
        for _ in 0..<4 { sPucker.continueBrush(at: CGPoint(x: 34, y: 32)); sPucker.continueBrush(at: CGPoint(x: 32, y: 32)) }
        sPucker.finishBrushImmediately()
        let puckered = try await ImageExporter.shared.render(try #require(sPucker.projectSnapshot()))
        #expect(try whiteCount(puckered.image) + 40 < baseCount)
    }

    @Test func freezeMaskProtectsRegionFromLiquify() async throws {
        let base = try dotAsset(size: 64, dotRadius: 10)
        let baseCount = try whiteCount(base.image)
        let session = EditorSession()
        session.createDocument(width: 64, height: 64)
        session.insert(base)
        session.selectTool(.blur)
        session.blurMode = .liquify
        session.brushSettings.diameter = 50
        session.brushSettings.hardness = 0.9
        session.brushSettings.opacity = 1

        // Freeze the center area.
        session.liquifyMode = .freeze
        session.beginBrush(at: CGPoint(x: 32, y: 32))
        session.finishBrushImmediately()
        #expect(session.hasLiquifyFreezeMask)

        // Bloat over the frozen area: pixel count stays virtually unchanged!
        session.liquifyMode = .bloat
        session.beginBrush(at: CGPoint(x: 32, y: 32))
        for _ in 0..<4 { session.continueBrush(at: CGPoint(x: 34, y: 32)); session.continueBrush(at: CGPoint(x: 32, y: 32)) }
        session.finishBrushImmediately()
        let frozenRaster = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let frozenCount = try whiteCount(frozenRaster.image)
        #expect(abs(frozenCount - baseCount) <= 10)

        // Clear freeze mask -> Bloat now expands normally.
        session.clearLiquifyFreezeMask()
        #expect(!session.hasLiquifyFreezeMask)
    }

    @Test func manualHealingBrushTransfersTextureWhileMatchingDestinationTone() async throws {
        // 64x32 image: left half is dark uniform gray (60,60,60) with a bright blemish at (16,16);
        // right half is bright uniform gray (200,200,200).
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8,
                                         bytesPerRow: 64 * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        ctx.setFillColor(CGColor(colorSpace: space, components: [60.0 / 255.0, 60.0 / 255.0, 60.0 / 255.0, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        ctx.setFillColor(CGColor(colorSpace: space, components: [200.0 / 255.0, 200.0 / 255.0, 200.0 / 255.0, 1])!)
        ctx.fill(CGRect(x: 32, y: 0, width: 32, height: 32))
        // Put a bright white spot on the dark side.
        ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
        ctx.fill(CGRect(x: 14, y: 14, width: 4, height: 4))
        let image = try #require(ctx.makeImage())
        let asset = ImportedImage(image: image, thumbnail: image, name: "HealTest")

        let session = EditorSession()
        session.createDocument(width: 64, height: 32)
        session.insert(asset)
        session.selectTool(.spotHealing)
        session.healingToolMode = .manual
        session.brushSettings.diameter = 10
        session.brushSettings.hardness = 1
        session.brushSettings.opacity = 1

        // Without Option-click source, Healing Brush refuses with a helpful message.
        session.beginBrush(at: CGPoint(x: 16, y: 16))
        #expect(session.brushStroke == nil && session.brushError != nil)
        session.brushError = nil

        // Sample from bright right side (48, 16) and heal the white blemish on dark left side (16, 16).
        session.setCloneSource(CGPoint(x: 48, y: 16))
        session.beginBrush(at: CGPoint(x: 16, y: 16))
        session.finishBrushImmediately()

        let healed = try await ImageExporter.shared.render(try #require(session.projectSnapshot()))
        let outCtx = try #require(CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8,
                                            bytesPerRow: 64 * 4, space: space,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        outCtx.draw(healed.image, in: CGRect(x: 0, y: 0, width: 64, height: 32))
        let ptr = try #require(outCtx.data).assumingMemoryBound(to: UInt8.self)
        let centerVal = ptr[16 * outCtx.bytesPerRow + 16 * 4]
        // Even though source was 200, Poisson membrane matches destination tone (~60) instead of stamping 200!
        #expect(abs(Int(centerVal) - 60) <= 18)
    }
}
