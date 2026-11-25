import CoreGraphics
import Foundation
import Testing
@testable import Compositor

@MainActor
struct AdvancedTransformTests {
    @Test func pivotKeepsAnchorFixedDuringRotationAndScaling() {
        let base = LayerTransform(origin: CGPoint(x: 20, y: 30), size: CGSize(width: 100, height: 60))
        let topLeft = CGPoint(x: 0, y: 0)
        let fixedBefore = base.point(topLeft)

        let rotated = base.rotated(toDegrees: 45, aroundUnitPivot: topLeft)
        let fixedAfterRot = rotated.point(topLeft)
        #expect(hypot(fixedAfterRot.x - fixedBefore.x, fixedAfterRot.y - fixedBefore.y) < 0.001)
        #expect(abs(rotated.rotation - 45) < 0.001)

        let scaled = base.scaled(toPercent: 200, pixelSize: base.size, aroundUnitPivot: topLeft)
        let fixedAfterScale = scaled.point(topLeft)
        #expect(hypot(fixedAfterScale.x - fixedBefore.x, fixedAfterScale.y - fixedBefore.y) < 0.001)
        #expect(abs(scaled.size.width - 200) < 0.01 && abs(scaled.size.height - 120) < 0.01)
    }

    @Test func independentSkewShearsLayerCornersAndCommits() throws {
        let session = EditorSession()
        session.createDocument(width: 160, height: 160)
        session.selectTool(.shape)
        session.foregroundColor = PaletteColor(red: 1, green: 0, blue: 0)
        session.beginShape(at: CGPoint(x: 40, y: 40))
        session.dragShape(to: CGPoint(x: 100, y: 100), square: false, fromCenter: false)
        session.finishShape()

        session.selectTool(.move)
        session.applyTransformSkew(skewX: 30, skewY: 0)
        let corners = try #require(session.transformEdit?.corners)
        #expect(corners.count == 4)
        // Top corners shifted left, bottom corners shifted right for positive horizontal skew around center.
        #expect(corners[0].x < corners[3].x - 10)
        #expect(corners[1].x < corners[2].x - 10)
        session.commitTransform()
        #expect(session.transformEdit == nil)
        #expect(session.transformSkewX == 0)
        // Resampled skewed bounding box is wider than original 60 px!
        #expect((session.activeLayer?.transform.size.width ?? 0) > 75)
    }

    @Test func meshWarpArchPresetAndCustomPointCommit() throws {
        let session = EditorSession()
        session.createDocument(width: 160, height: 160)
        session.selectTool(.shape)
        session.foregroundColor = PaletteColor(red: 0, green: 0.6, blue: 1)
        session.beginShape(at: CGPoint(x: 30, y: 50))
        session.dragShape(to: CGPoint(x: 130, y: 110), square: false, fromCenter: false)
        session.finishShape()

        session.beginMeshWarp(preset: .arch)
        #expect(session.meshWarpEdit != nil)
        let activeLayer = try #require(session.activeLayer)
        let preview = try #require(session.meshWarpPreview(for: activeLayer))
        #expect(preview.transform.size.height > 65) // Arch bends upward, expanding vertical bounds!

        // Manually pull control point 5 (interior) upward further.
        let beforePt = try #require(session.meshWarpEdit?.mesh.points[5])
        session.moveMeshWarpPoint(at: 5, to: CGPoint(x: beforePt.x, y: beforePt.y - 15))
        #expect(session.meshWarpEdit?.preset == .custom)

        session.commitMeshWarp()
        #expect(session.meshWarpEdit == nil)
        #expect((session.activeLayer?.transform.size.height ?? 0) > 65)
        #expect(session.history.undoCount >= 2)
    }
}
