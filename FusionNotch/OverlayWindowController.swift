import AppKit
import SwiftUI

class OverlayWindowController: NSObject {
    private var panel: NSPanel?
    private let metricsEngine: MetricsEngine
    let animState = PanelAnimationState()

    private let panelWidth  = NotchPanelView.width
    private let panelHeight = NotchPanelView.height
    private let panelGap: CGFloat = 0  // flush with notch bottom

    private var pendingHide: DispatchWorkItem?

    init(metricsEngine: MetricsEngine) {
        self.metricsEngine = metricsEngine
        super.init()
        buildPanel()
    }

    // MARK: - Show

    func show(near notchRect: NSRect) {
        guard let panel else { return }

        // Cancel any in-flight hide
        pendingHide?.cancel()
        pendingHide = nil

        // Snap to collapsed before revealing so the expand always plays fresh
        animState.isVisible = false
        positionPanel(notchRect: notchRect)
        panel.orderFrontRegardless()

        // One run-loop tick lets SwiftUI render the collapsed state first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
            self.animState.isVisible = true
        }
    }

    // MARK: - Hide

    func hide() {
        animState.isVisible = false

        // Wait for the collapse spring to finish before pulling the window off-screen
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: work)
    }

    // MARK: - Panel construction

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        // Must sit above the menu bar so the dark background merges with the notch
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.alphaValue = 1
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isMovable = false
        p.acceptsMouseMovedEvents = true

        let rootView = NotchPanelView(metricsEngine: metricsEngine, animState: animState)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = p.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        p.contentView = hostingView

        self.panel = p
    }

    private func positionPanel(notchRect: NSRect) {
        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - panelWidth / 2
        // Anchor the panel TOP at the screen top so it covers the notch
        // and appears to grow downward out of it — no menu-bar gap possible
        let y = screen.frame.maxY - panelHeight
        panel?.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
