import CoreGraphics
import Foundation
import Testing
@testable import Compositor

@MainActor
struct SelectionRefinementTests {
    @Test func quickMaskPaintConvertsBackToSelection() throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)

        // Enter Quick Mask with no selection -> starts fully masked (0).
        session.toggleQuickMask()
        #expect(session.isInQuickMaskMode)
        session.foregroundColor = .white
        session.brushMode = .paint
        session.brushSettings.diameter = 30
        session.brushSettings.hardness = 1
        session.brushSettings.opacity = 1

        // Paint white circle at (50, 50) -> selects center!
        session.quickMaskBrushDown(at: CGPoint(x: 50, y: 50))
        session.quickMaskBrushUp()

        // Exit Quick Mask -> converts painted area into DocumentSelection.
        session.toggleQuickMask()
        #expect(!session.isInQuickMaskMode)
        let sel = try #require(session.selection)
        #expect(sel.path.contains(CGPoint(x: 50, y: 50)))
        #expect(!sel.path.contains(CGPoint(x: 5, y: 5)))
    }

    @Test func borderSmoothAndSelectSimilarModifySelection() async throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)

        // Start with square [20..80, 20..80].
        session.setSelection(DocumentSelection(path: CGPath(rect: CGRect(x: 20, y: 20, width: 60, height: 60), transform: nil)), name: "Square")
        // Border 10 px -> ring around boundary: (20, 50) selected, center (50, 50) NOT selected!
        session.borderSelection(by: 10)
        let borderSel = try #require(session.selection)
        #expect(borderSel.path.contains(CGPoint(x: 20, y: 50)))
        #expect(!borderSel.path.contains(CGPoint(x: 50, y: 50)))

        // Smooth 8 px rounds the sharp square corner at (20, 20).
        session.setSelection(DocumentSelection(path: CGPath(rect: CGRect(x: 20, y: 20, width: 60, height: 60), transform: nil)), name: "Square")
        session.smoothSelection(by: 8)
        let smoothSel = try #require(session.selection)
        #expect(smoothSel.path.contains(CGPoint(x: 50, y: 50)))
        #expect(!smoothSel.path.contains(CGPoint(x: 20.5, y: 20.5)))

        // Select Similar: draw two separated red squares on a blue canvas, select only the left red square -> Similar selects BOTH!
        let sim = EditorSession()
        sim.createDocument(width: 100, height: 60)
        sim.selectTool(.shape)
        sim.foregroundColor = PaletteColor(red: 0, green: 0, blue: 1)
        sim.beginShape(at: .zero); sim.dragShape(to: CGPoint(x: 100, y: 60), square: false, fromCenter: false); sim.finishShape()
        sim.foregroundColor = PaletteColor(red: 1, green: 0, blue: 0)
        sim.beginShape(at: CGPoint(x: 10, y: 15)); sim.dragShape(to: CGPoint(x: 35, y: 45), square: false, fromCenter: false); sim.finishShape()
        sim.beginShape(at: CGPoint(x: 65, y: 15)); sim.dragShape(to: CGPoint(x: 90, y: 45), square: false, fromCenter: false); sim.finishShape()

        sim.setSelection(DocumentSelection(path: CGPath(rect: CGRect(x: 15, y: 20, width: 15, height: 15), transform: nil)), name: "Left Red")
        await sim.selectSimilar(tolerance: 25)
        let simSel = try #require(sim.selection)
        #expect(simSel.path.contains(CGPoint(x: 22, y: 30)))
        #expect(simSel.path.contains(CGPoint(x: 75, y: 30)))
        #expect(!simSel.path.contains(CGPoint(x: 50, y: 30)))
    }

    @Test func selectAndMaskRefinesAndOutputsNewLayerWithMask() async throws {
        let session = EditorSession()
        session.createDocument(width: 80, height: 80)
        session.selectTool(.shape)
        session.foregroundColor = PaletteColor(red: 0.2, green: 0.8, blue: 0.3)
        session.beginShape(at: .zero); session.dragShape(to: CGPoint(x: 80, y: 80), square: false, fromCenter: false); session.finishShape()
        session.setSelection(DocumentSelection(path: CGPath(rect: CGRect(x: 20, y: 20, width: 40, height: 40), transform: nil)), name: "Box")

        await session.openSelectAndMask()
        #expect(session.selectAndMask != nil)
        session.selectAndMask?.settings.smooth = 4
        session.selectAndMask?.settings.feather = 3
        session.selectAndMask?.settings.contrast = 20
        session.selectAndMask?.settings.shiftEdge = 15
        session.selectAndMask?.settings.decontaminateColors = true
        session.selectAndMask?.settings.outputMode = .newLayerWithMask
        #expect(session.selectAndMask?.previewImage() != nil)

        let countBefore = session.document?.layers.count ?? 0
        session.applySelectAndMask()
        #expect(session.selectAndMask == nil)
        #expect((session.document?.layers.count ?? 0) == countBefore + 1)
        #expect(session.activeLayer?.mask != nil)
    }
}
