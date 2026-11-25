import CoreGraphics
import Foundation
import Testing
@testable import Compositor

@MainActor
struct WorkflowPanelsTests {
    @Test func historyJumpAndSnapshotsRestoreCleanly() throws {
        let session = EditorSession()
        session.createDocument(width: 80, height: 80)
        #expect(session.history.currentStepIndex == 0)

        // Step 1: Add blank layer A
        session.addBlankLayer()
        let countAfter1 = session.document?.layers.count ?? 0
        // Step 2: Add blank layer B
        session.addBlankLayer()
        let countAfter2 = session.document?.layers.count ?? 0
        // Capture Snapshot at step 2
        let snapID = try #require(session.createHistorySnapshot(name: "Midpoint"))
        // Step 3: Add blank layer C
        session.addBlankLayer()
        let countAfter3 = session.document?.layers.count ?? 0
        #expect(countAfter3 == countAfter2 + 1 && countAfter2 == countAfter1 + 1)
        #expect(session.history.currentStepIndex == 3)

        // Jump straight back to step 1 in one call!
        session.jumpToHistoryStep(1)
        #expect(session.history.currentStepIndex == 1)
        #expect(session.document?.layers.count == countAfter1)
        #expect(session.history.futureNames.count == 2)

        // Jump straight forward to step 3!
        session.jumpToHistoryStep(3)
        #expect(session.history.currentStepIndex == 3)
        #expect(session.document?.layers.count == countAfter3)

        // Restore Snapshot -> returns layer count to step 2 as a new undoable edit!
        session.restoreHistorySnapshot(snapID)
        #expect(session.document?.layers.count == countAfter2)
        session.undo()
        #expect(session.document?.layers.count == countAfter3)

        session.deleteHistorySnapshot(snapID)
        #expect(session.historySnapshots.isEmpty)
    }

    @Test func pointerColorInfoComputesExactHexHSBAndCMYK() {
        // Pure red (255, 0, 0)
        let red = PointerColorInfo(point: CGPoint(x: 10, y: 20), r: 255, g: 0, b: 0, a: 255)
        #expect(red.hex == "#FF0000")
        #expect(red.hsb.h == 0 && red.hsb.s == 100 && red.hsb.b == 100)
        #expect(red.cmyk == (0, 100, 100, 0))

        // Pure black (0, 0, 0)
        let black = PointerColorInfo(point: .zero, r: 0, g: 0, b: 0, a: 255)
        #expect(black.hex == "#000000")
        #expect(black.cmyk == (0, 0, 0, 100))

        // Cyan (0, 255, 255)
        let cyan = PointerColorInfo(point: .zero, r: 0, g: 255, b: 255, a: 255)
        #expect(cyan.hex == "#00FFFF")
        #expect(cyan.hsb.h == 180 && cyan.hsb.s == 100 && cyan.hsb.b == 100)
        #expect(cyan.cmyk == (100, 0, 0, 0))
    }

    @Test func histogramComputesExactChannelStatistics() async throws {
        let session = EditorSession()
        session.createDocument(width: 64, height: 64)
        session.selectTool(.shape)
        // Half black (0,0,0), half white (255,255,255) -> Mean ≈ 127.5, StdDev ≈ 127.5!
        session.foregroundColor = .black
        session.beginShape(at: .zero); session.dragShape(to: CGPoint(x: 32, y: 64), square: false, fromCenter: false); session.finishShape()
        session.foregroundColor = .white
        session.beginShape(at: CGPoint(x: 32, y: 0)); session.dragShape(to: CGPoint(x: 64, y: 64), square: false, fromCenter: false); session.finishShape()

        await session.refreshHistogram()
        let stats = try #require(session.histogramStats)
        #expect(stats.pixelCount == 64 * 64)
        let summary = stats.summary(for: .luminosity)
        #expect(abs(summary.mean - 127.5) < 1.5)
        #expect(abs(summary.stdDev - 127.5) < 1.5)
    }
}
