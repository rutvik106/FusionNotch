import AppKit
import ApplicationServices

/// Detects when the mouse hovers over the notch region and fires callbacks.
class NotchTracker {
    var onHoverEnter: ((NSRect) -> Void)?
    var onHoverExit:  (() -> Void)?
    /// Called once when accessibility permission is confirmed and monitoring begins.
    var onAccessibilityGranted: (() -> Void)?

    // Panel dimensions must match OverlayWindowController / NotchPanelView
    private let panelWidth:  CGFloat = 500
    private let panelHeight: CGFloat = 130
    private let panelGap:    CGFloat = 0

    private var monitor: Any?
    private var isHovering = false
    private var hideTimer:  Timer?
    private let hideDelay:  TimeInterval = 0.25

    // MARK: - Start / Stop

    func start() {
        guard monitor == nil else { return }

        if AXIsProcessTrusted() {
            beginMonitoring()
        } else {
            // Show the system dialog once on launch, then poll silently
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            schedulePoll()
        }
    }

    /// Re-prompts for accessibility unconditionally — safe to call from the menu.
    func requestAccess() {
        guard monitor == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            beginMonitoring()
        } else {
            schedulePoll()
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        hideTimer?.invalidate()
        hideTimer = nil
    }

    // MARK: - Private helpers

    private func schedulePoll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.monitor == nil else { return }
            if AXIsProcessTrusted() {
                self.beginMonitoring()
            } else {
                self.schedulePoll()   // keep polling silently — no more dialogs
            }
        }
    }

    private func beginMonitoring() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.evaluateMousePosition()
        }
        let notchInfo = currentNotchRect().map { "notch=\($0)" } ?? "NO NOTCH DETECTED"
        print("[FusionNotch] Monitoring started — \(notchInfo)")
        onAccessibilityGranted?()
    }

    // MARK: - Hover Logic

    private func evaluateMousePosition() {
        guard let notchRect = currentNotchRect() else { return }

        let mouse     = NSEvent.mouseLocation
        let hoverZone = buildHoverZone(notchRect: notchRect)

        if hoverZone.contains(mouse) {
            guard !isHovering else { return }
            isHovering = true
            hideTimer?.invalidate()
            hideTimer = nil
            onHoverEnter?(notchRect)
        } else if isHovering {
            scheduleHide()
        }
    }

    private func buildHoverZone(notchRect: NSRect) -> NSRect {
        // Panel now anchors at screen TOP (notchRect.maxY) and grows downward.
        // Hover zone covers from the screen top down to the panel bottom + buffer.
        let midX  = notchRect.midX
        let width = max(notchRect.width, panelWidth) + 24
        let top   = notchRect.maxY                  // screen top
        let bottom = top - panelHeight - 12          // panel bottom + 12 pt buffer
        return NSRect(x: midX - width / 2, y: bottom, width: width, height: top - bottom)
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.isHovering = false
            self.onHoverExit?()
        }
    }

    // MARK: - Notch Geometry

    /// Returns the frame of the hardware notch on the main screen, or nil if no notch.
    func currentNotchRect() -> NSRect? {
        guard let screen = NSScreen.main else { return nil }

        let notchHeight = screen.safeAreaInsets.top
        guard notchHeight > 0 else { return nil }

        let screenFrame = screen.frame
        let notchWidth: CGFloat

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = right.minX - left.maxX
        } else {
            notchWidth = 200
        }

        let notchX = screenFrame.midX - notchWidth / 2
        let notchY = screenFrame.maxY - notchHeight

        return NSRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
    }

    deinit { stop() }
}
