import SwiftUI

// Shared animation state — toggled by OverlayWindowController
class PanelAnimationState: ObservableObject {
    @Published var isVisible = false
}

// MARK: - Root Panel View

struct NotchPanelView: View {
    @ObservedObject var metricsEngine: MetricsEngine
    @ObservedObject var animState: PanelAnimationState

    // Panel size must match OverlayWindowController
    // Height includes the notch area (≈24 pt) + visible content below it
    static let width:  CGFloat = 500
    static let height: CGFloat = 130

    // Brand palette
    private let ramColor   = Color(red: 0.38, green: 0.82, blue: 1.00)   // ice blue
    private let netUp      = Color(red: 0.40, green: 0.92, blue: 0.58)   // mint
    private let netDown    = Color(red: 0.42, green: 0.72, blue: 1.00)   // periwinkle
    private let tempColor  = Color(red: 1.00, green: 0.56, blue: 0.22)   // amber

    var body: some View {
        ZStack {
            panelBackground
            contentRow
        }
        .frame(width: Self.width, height: Self.height)
        // Expand from the notch top: scale Y from ~0 → 1
        .scaleEffect(x: 1, y: animState.isVisible ? 1 : 0.02, anchor: .top)
        .opacity(animState.isVisible ? 1 : 0)
        .animation(
            .spring(response: 0.46, dampingFraction: 0.72),
            value: animState.isVisible
        )
    }

    // MARK: - Background

    private var panelBackground: some View {
        // The panel top sits at the physical screen top (covering the notch hardware).
        // Top corners = 0 so our black surface blends seamlessly with the notch cutout.
        // Bottom corners are wide and soft — the "expanded notch" feel.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 26,
            bottomTrailingRadius: 26, topTrailingRadius: 0,
            style: .continuous
        )
        return ZStack {
            // Pure black — matches the physical notch (which is a hardware cutout = no light = black)
            shape.fill(Color.black)

            // Very subtle inner glow at bottom half only — adds depth without breaking the illusion
            shape.fill(
                LinearGradient(
                    colors: [Color.clear, Color.white.opacity(0.04)],
                    startPoint: UnitPoint(x: 0.5, y: 0.5),
                    endPoint: .bottom
                )
            )

            // Hairline border on bottom + sides only (top is hidden against the notch)
            shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
        }
        // Soft drop shadow below the panel
        .shadow(color: Color.black.opacity(0.70), radius: 20, x: 0, y: 8)
    }

    // MARK: - Content row

    private var contentRow: some View {
        HStack(spacing: 0) {
            MetricCell(
                icon: "memorychip",
                iconColor: ramColor,
                value: metricsEngine.ramUsage,
                label: "RAM"
            )
            .revealed(animState.isVisible, delay: 0.12)

            slimDivider

            BatteryCell(status: metricsEngine.batteryStatus)
                .revealed(animState.isVisible, delay: 0.17)

            slimDivider

            NetworkCell(upload: metricsEngine.uploadSpeed,
                        download: metricsEngine.downloadSpeed,
                        upColor: netUp, downColor: netDown)
                .revealed(animState.isVisible, delay: 0.22)

            if metricsEngine.temperature != nil {
                slimDivider
                MetricCell(
                    icon: "thermometer.medium",
                    iconColor: tempColor,
                    value: metricsEngine.temperature ?? "",
                    label: "TEMP"
                )
                .revealed(animState.isVisible, delay: 0.27)
            }
        }
        .padding(.horizontal, 22)
        // Top padding pushes content below the notch hardware area (~24 pt).
        // Bottom padding balances the card visually.
        .padding(.top, 30)
        .padding(.bottom, 14)
    }

    private var slimDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.11), .clear],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 1)
            .padding(.vertical, 8)
    }
}

// MARK: - Generic Metric Cell

struct MetricCell: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 7) {
            // Glowing icon
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor)
                .shadow(color: iconColor.opacity(0.55), radius: 5, x: 0, y: 0)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.30))
                .tracking(1.2)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Battery Cell (dynamic colour + icon)

struct BatteryCell: View {
    let status: String

    private var percent: Int {
        Int(status.prefix(while: { $0.isNumber })) ?? 50
    }
    private var isCharging: Bool { status.contains("⚡") }
    private var isPlugged:  Bool { status.contains("∞") }

    private var iconName: String {
        if isCharging || isPlugged { return "battery.100.bolt" }
        switch percent {
        case 76...: return "battery.100"
        case 51...: return "battery.75"
        case 26...: return "battery.50"
        case 11...: return "battery.25"
        default:    return "battery.0"
        }
    }

    private var iconColor: Color {
        if isCharging || isPlugged { return Color(red: 0.38, green: 0.92, blue: 0.55) }
        switch percent {
        case 31...: return Color(red: 0.38, green: 0.92, blue: 0.55) // green
        case 16...: return Color(red: 1.00, green: 0.82, blue: 0.25) // yellow
        default:    return Color(red: 1.00, green: 0.36, blue: 0.36) // red
        }
    }

    var body: some View {
        MetricCell(icon: iconName, iconColor: iconColor, value: status, label: "BATTERY")
    }
}

// MARK: - Network Cell

struct NetworkCell: View {
    let upload: String
    let download: String
    let upColor: Color
    let downColor: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))

            VStack(alignment: .leading, spacing: 3) {
                speedRow(arrow: "arrow.up",   text: upload,   color: upColor)
                speedRow(arrow: "arrow.down", text: download, color: downColor)
            }

            Text("NETWORK")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.30))
                .tracking(1.2)
        }
        .frame(maxWidth: .infinity)
    }

    private func speedRow(arrow: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: arrow)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.5), radius: 3)
            Text(text)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }
}

// MARK: - Animation helper

private extension View {
    /// Fade + subtle upward slide, triggered when `visible` becomes true, with a per-cell delay.
    func revealed(_ visible: Bool, delay: Double) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : -5)
            .animation(
                .spring(response: 0.4, dampingFraction: 0.74).delay(visible ? delay : 0),
                value: visible
            )
    }
}
