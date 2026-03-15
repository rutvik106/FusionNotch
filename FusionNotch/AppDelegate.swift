import AppKit
import ApplicationServices
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notchTracker: NotchTracker?
    private var overlayController: OverlayWindowController?
    let metricsEngine = MetricsEngine()

    // Menu items we need to update dynamically
    private var accessibilityMenuItem: NSMenuItem?
    private var notchStatusMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupNotchTracker()
        metricsEngine.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusButton(accessibilityGranted: AXIsProcessTrusted())

        let menu = NSMenu()

        // Accessibility status / action row
        let axItem = NSMenuItem(title: "⚠️  Enable Notch Detection…",
                                action: #selector(requestAccessibilityAccess),
                                keyEquivalent: "")
        axItem.target = self
        menu.addItem(axItem)
        accessibilityMenuItem = axItem

        // Notch info row
        let notchItem = NSMenuItem(title: "Notch: detecting…", action: nil, keyEquivalent: "")
        notchItem.isEnabled = false
        menu.addItem(notchItem)
        notchStatusMenuItem = notchItem

        menu.addItem(.separator())

        // Debug / test item — shows panel directly without needing to hover
        let testItem = NSMenuItem(title: "Show Panel Now (Test)",
                                  action: #selector(testShowPanel),
                                  keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLaunchAtLogin),
                                   keyEquivalent: "")
        loginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit FusionNotch",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        statusItem?.menu = menu

        // Refresh accessibility/notch status every time the menu opens
        menu.delegate = self
    }

    private func updateStatusButton(accessibilityGranted: Bool) {
        guard let btn = statusItem?.button else { return }
        // Use a simple SF symbol that reliably renders on all macOS versions
        let name = accessibilityGranted ? "circle.fill" : "exclamationmark.circle.fill"
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: "FusionNotch") {
            img.isTemplate = true
            btn.image = img
            btn.title = ""
        } else {
            // Ultimate fallback: text label
            btn.image = nil
            btn.title = accessibilityGranted ? "◉" : "⚠"
        }
    }

    @objc private func requestAccessibilityAccess() {
        notchTracker?.requestAccess()
    }

    @objc private func testShowPanel() {
        let rect = notchTracker?.currentNotchRect()
            ?? NSRect(x: (NSScreen.main?.frame.midX ?? 756) - 100,
                      y: (NSScreen.main?.frame.maxY ?? 900) - 38,
                      width: 200, height: 38)
        print("[FusionNotch] testShowPanel — notchRect=\(rect)")
        // Small delay so the menu fully dismisses before we show the panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showPanel(near: rect)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            self?.hidePanel()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let nowEnabled = isLaunchAtLoginEnabled()
        setLaunchAtLogin(!nowEnabled)
        if let item = statusItem?.menu?.items.first(where: { $0.action == #selector(toggleLaunchAtLogin) }) {
            item.state = !nowEnabled ? .on : .off
        }
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                try enable ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            } catch {
                print("[FusionNotch] Launch-at-login: \(error)")
            }
        }
    }

    // MARK: - Notch Tracker

    private func setupNotchTracker() {
        notchTracker = NotchTracker()

        notchTracker?.onAccessibilityGranted = { [weak self] in
            DispatchQueue.main.async { self?.handleAccessibilityGranted() }
        }
        notchTracker?.onHoverEnter = { [weak self] notchRect in
            self?.showPanel(near: notchRect)
        }
        notchTracker?.onHoverExit = { [weak self] in
            self?.hidePanel()
        }

        notchTracker?.start()
    }

    private func handleAccessibilityGranted() {
        updateStatusButton(accessibilityGranted: true)
        accessibilityMenuItem?.title   = "✓  Notch Detection Active"
        accessibilityMenuItem?.action  = nil   // no longer tappable
        accessibilityMenuItem?.isEnabled = false

        // Show detected notch geometry
        if let r = notchTracker?.currentNotchRect() {
            notchStatusMenuItem?.title = String(format: "Notch: %.0f × %.0f pt @ (%.0f, %.0f)",
                                                r.width, r.height, r.minX, r.minY)
        } else {
            notchStatusMenuItem?.title = "Notch: not detected on this display"
        }
    }

    private func showPanel(near notchRect: NSRect) {
        if overlayController == nil {
            overlayController = OverlayWindowController(metricsEngine: metricsEngine)
        }
        overlayController?.show(near: notchRect)
    }

    private func hidePanel() {
        overlayController?.hide()
    }
}

// MARK: - NSMenuDelegate — refresh status on open

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        let granted = AXIsProcessTrusted()
        updateStatusButton(accessibilityGranted: granted)

        if !granted {
            accessibilityMenuItem?.title    = "⚠️  Enable Notch Detection…"
            accessibilityMenuItem?.action   = #selector(requestAccessibilityAccess)
            accessibilityMenuItem?.isEnabled = true
        }
    }
}
