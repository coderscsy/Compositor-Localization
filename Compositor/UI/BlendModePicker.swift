import SwiftUI
import AppKit

struct BlendModePicker: NSViewRepresentable {
    let session: EditorSession
    private static let passThroughToken = "passThrough"

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        let passItem = NSMenuItem(title: L10n.text("Pass Through"), action: nil, keyEquivalent: "")
        passItem.representedObject = Self.passThroughToken
        passItem.isHidden = true
        button.menu?.addItem(passItem)
        let passSeparator = NSMenuItem.separator()
        passSeparator.tag = 999
        passSeparator.isHidden = true
        button.menu?.addItem(passSeparator)
        // Grouped as Photoshop groups them — normal/dissolve, darkening, lightening, contrast, comparative, component —
        // with a line between, so a long list stays readable.
        for (index, group) in LayerBlendMode.groups.enumerated() {
            if index > 0 { button.menu?.addItem(.separator()) }
            for mode in group {
                let item = NSMenuItem(title: L10n.text(mode.rawValue), action: nil, keyEquivalent: "")
                item.representedObject = mode
                button.menu?.addItem(item)
            }
        }
        button.menu?.delegate = context.coordinator
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        button.setAccessibilityLabel(L10n.text("Blend mode"))
        // A capsule like the SwiftUI buttons and menus (`roundedControls`), which don't reach this AppKit pop-up.
        button.borderShape = .capsule
        return button
    }
    /// As wide as it's offered. Left to itself, the pop-up insists on the width of its longest mode, wider than a
    /// narrow Layers panel has room for, and that pushed the whole panel out past its edges.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView button: NSPopUpButton, context: Context) -> CGSize? {
        let natural = button.intrinsicContentSize
        guard let width = proposal.width, width.isFinite else { return natural }
        return CGSize(width: max(width, 60), height: natural.height)
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        button.isEnabled = session.canEditBlendMode
        let isGroup = session.activeLayer?.isGroup == true
        if let menu = button.menu {
            menu.items.first { ($0.representedObject as? String) == Self.passThroughToken }?.isHidden = !isGroup
            menu.item(withTag: 999)?.isHidden = !isGroup
        }
        if !context.coordinator.tracking {
            if isGroup, session.activeLayer?.isPassThrough == true {
                Self.selectPassThrough(in: button)
            } else {
                Self.select(session.activeLayer?.blendMode ?? .normal, in: button)
            }
        }
    }
    private static func select(_ mode: LayerBlendMode, in button: NSPopUpButton) {
        button.select(button.itemArray.first { $0.representedObject as? LayerBlendMode == mode })
    }
    private static func selectPassThrough(in button: NSPopUpButton) {
        button.select(button.itemArray.first { ($0.representedObject as? String) == passThroughToken })
    }
    static func dismantleNSView(_ button: NSPopUpButton, coordinator: Coordinator) {
        if coordinator.tracking { coordinator.session.previewBlendMode(nil, for: nil) }
        button.menu?.delegate = nil
    }
    final class Coordinator: NSObject, NSMenuDelegate {
        let session: EditorSession
        var tracking = false
        private var layerID: UUID?
        private var highlightedMode: LayerBlendMode?
        private var highlightedPassThrough = false
        init(session: EditorSession) { self.session = session }
        func menuWillOpen(_ menu: NSMenu) {
            tracking = true
            layerID = session.activeLayerID
            highlightedMode = nil
            highlightedPassThrough = false
        }
        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            // AppKit briefly reports no highlighted item while dismissing the menu.
            // Keep the last preview alive until the selection action has committed so
            // the canvas never flashes back to the layer's previous mode.
            if (item?.representedObject as? String) == BlendModePicker.passThroughToken {
                highlightedPassThrough = true
                highlightedMode = nil
                session.previewBlendMode(.normal, for: layerID, passThrough: true)
                return
            }
            guard let mode = item?.representedObject as? LayerBlendMode else { return }
            highlightedPassThrough = false
            highlightedMode = mode
            session.previewBlendMode(mode, for: layerID, passThrough: false)
        }
        func menuDidClose(_ menu: NSMenu) {
            tracking = false
            // A chosen item's action runs as the menu finishes closing. Clearing on the
            // next turn lets that action replace the preview with the committed mode;
            // when the menu was cancelled, this simply restores the original mode.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.tracking else { return }
                self.session.previewBlendMode(nil, for: nil)
            }
        }
        @objc func choose(_ button: NSPopUpButton) {
            guard session.activeLayerID == layerID else { return }
            if highlightedPassThrough || (button.selectedItem?.representedObject as? String) == BlendModePicker.passThroughToken {
                session.setFolderPassThrough()
                BlendModePicker.selectPassThrough(in: button)
                highlightedPassThrough = false
                highlightedMode = nil
                session.refreshCanvasPreview?()
                return
            }
            guard let mode = highlightedMode ?? (button.selectedItem?.representedObject as? LayerBlendMode) else { return }
            session.setLayerBlendMode(mode)
            BlendModePicker.select(mode, in: button)
            highlightedMode = nil
            session.refreshCanvasPreview?()
        }
    }
}
