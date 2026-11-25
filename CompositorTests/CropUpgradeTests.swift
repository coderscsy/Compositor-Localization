import CoreGraphics
import Foundation
import Testing
@testable import Compositor

@MainActor
struct CropUpgradeTests {
    @Test func straightenAngleComputesHorizonAndVerticalTilt() {
        // Horizontal line tilted +10° downward to the right.
        let rad = 10.0 * Double.pi / 180.0
        let deg = CropProcessor.straightenAngle(from: .zero, to: CGPoint(x: cos(rad) * 100, y: sin(rad) * 100))
        #expect(abs(deg - 10.0) < 0.05)

        // Nearly vertical line tilted -6° from vertical -> snaps to vertical axis (-6°).
        let vRad = (90.0 - 6.0) * Double.pi / 180.0
        let vDeg = CropProcessor.straightenAngle(from: .zero, to: CGPoint(x: cos(vRad) * 100, y: sin(vRad) * 100))
        #expect(abs(vDeg - (-6.0)) < 0.05)
    }

    @Test func nonDestructiveVsDeleteCroppedPixelsToggle() async throws {
        // Non-destructive crop keeps full 100x100 layer asset intact while resizing canvas to 40x40.
        let sKeep = EditorSession()
        sKeep.createDocument(width: 100, height: 100)
        sKeep.selectTool(.shape)
        sKeep.foregroundColor = PaletteColor(red: 1, green: 0, blue: 0)
        sKeep.beginShape(at: .zero)
        sKeep.dragShape(to: CGPoint(x: 100, y: 100), square: false, fromCenter: false)
        sKeep.finishShape()

        sKeep.selectTool(.crop)
        sKeep.deleteCroppedPixels = false
        sKeep.cropRect = CGRect(x: 30, y: 30, width: 40, height: 40)
        await sKeep.commitCrop()
        #expect(sKeep.document?.width == 40 && sKeep.document?.height == 40)
        #expect(sKeep.activeLayer?.asset?.image.width == 100)
        #expect(sKeep.activeLayer?.transform.origin == CGPoint(x: -30, y: -30))

        // Delete Cropped Pixels trims the layer's pixel asset strictly to 40x40!
        let sTrim = EditorSession()
        sTrim.createDocument(width: 100, height: 100)
        sTrim.selectTool(.shape)
        sTrim.foregroundColor = PaletteColor(red: 0, green: 1, blue: 0)
        sTrim.beginShape(at: .zero)
        sTrim.dragShape(to: CGPoint(x: 100, y: 100), square: false, fromCenter: false)
        sTrim.finishShape()

        sTrim.selectTool(.crop)
        sTrim.deleteCroppedPixels = true
        sTrim.cropRect = CGRect(x: 30, y: 30, width: 40, height: 40)
        await sTrim.commitCrop()
        #expect(sTrim.document?.width == 40 && sTrim.document?.height == 40)
        #expect(sTrim.activeLayer?.asset?.image.width == 40)
        #expect(sTrim.activeLayer?.asset?.image.height == 40)
    }

    @Test func rotatedCropAppliesAngleAndPerspectiveCropRectifiesQuad() async throws {
        // Rotated crop rotates layer transform cleanly.
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)
        session.selectTool(.shape)
        session.foregroundColor = PaletteColor(red: 0, green: 0, blue: 1)
        session.beginShape(at: .zero)
        session.dragShape(to: CGPoint(x: 100, y: 100), square: false, fromCenter: false)
        session.finishShape()

        session.selectTool(.crop)
        session.cropAngle = 15
        await session.commitCrop()
        let rot = try #require(session.activeLayer?.transform.rotation)
        #expect(abs(rot - (-15 * Double.pi / 180)) < 0.01)

        // Perspective Crop rectifies a trapezoid quad into an upright rectangle.
        let pSession = EditorSession()
        pSession.createDocument(width: 120, height: 100)
        pSession.selectTool(.shape)
        pSession.foregroundColor = PaletteColor(red: 1, green: 0.5, blue: 0)
        pSession.beginShape(at: .zero)
        pSession.dragShape(to: CGPoint(x: 120, y: 100), square: false, fromCenter: false)
        pSession.finishShape()

        pSession.selectTool(.crop)
        pSession.togglePerspectiveCrop()
        pSession.perspectiveCropQuad = CropPerspectiveQuad(corners: [
            CGPoint(x: 20, y: 10),
            CGPoint(x: 100, y: 10),
            CGPoint(x: 110, y: 90),
            CGPoint(x: 10, y: 90),
        ])
        let expectedSize = try #require(pSession.perspectiveCropQuad?.outputSize)
        await pSession.commitCrop()
        #expect(pSession.document?.width == Int(expectedSize.width))
        #expect(pSession.document?.height == Int(expectedSize.height))
        #expect(pSession.activeLayer?.asset?.image.width == Int(expectedSize.width))
    }
}
