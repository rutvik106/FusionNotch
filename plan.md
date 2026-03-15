# fusion-notch Plan

## Overview
fusion-notch is a lightweight macOS utility for MacBook devices with a notch. It runs continuously in the background and reveals a compact utility panel when the user hovers over the notch area. The app focuses on quick system insights without interrupting the user’s workflow.

## Core Goals
- Always run in the background after launch.
- Open the UI when the user hovers over the notch area.
- Show useful live system information:
  - Laptop temperature
  - RAM usage
  - Network speed
  - Battery status
- Start automatically when macOS starts.
- Stay lightweight, fast, and stable.

## Key Features

### 1. Background-first architecture
- App should behave like a menubar/background utility rather than a traditional dock app.
- It should remain active even when no visible window is open.
- Closing the UI must not quit the app.
- Optional menu bar icon can be included for settings, quit, and health status.

### 2. Notch hover interaction
- Detect the notch region precisely based on screen geometry.
- When the cursor enters the notch hover zone, reveal the floating UI.
- When the cursor leaves the panel and hover zone, hide the UI after a short delay.
- Add safeguards to prevent flicker when the mouse moves near the notch edges.

### 3. Utility dashboard
The notch UI should display:
- **Temperature**: CPU/system thermal reading if accessible through approved macOS APIs or safe system methods.
- **RAM usage**: used, free, pressure, and/or percentage.
- **Network speed**: current upload/download speed.
- **Battery**: battery percentage, charging status, and optionally time remaining.

### 4. Auto-start on login
- Register the app to launch automatically at user login.
- Ensure the startup flow is reliable across fresh installs and updates.

### 5. Persistent background behavior
- The app must keep running unless the user explicitly quits it.
- Sleep/wake transitions should be handled gracefully.
- System metrics should refresh in the background at a safe interval.

## Suggested Tech Stack
- **Language**: Swift
- **UI**: SwiftUI
- **App lifecycle / system integration**: AppKit + SwiftUI hybrid
- **Background behavior**: NSApplication activation policy accessory or agent-style behavior depending on desired visibility
- **Startup at login**: ServiceManagement framework
- **System metrics**:
  - RAM: host statistics / system APIs
  - Battery: IOKit or ProcessInfo / supported power APIs
  - Network speed: interface byte counters sampled over time
  - Temperature: investigate safe and supported macOS-accessible sources; fall back cleanly if exact thermal sensor data is unavailable

## Functional Requirements

### App lifecycle
- App launches manually or at login.
- App remains running in the background at all times.
- App does not terminate when the UI is dismissed.
- User can quit from a menu/settings entry.

### Hover UI
- Hovering over the notch opens the dashboard.
- UI appears smoothly and quickly.
- UI stays open while the cursor is over the panel.
- UI hides automatically when no longer in use.

### Metrics display
- Data should update live with low overhead.
- Values should be readable at a glance.
- Handle unavailable metrics gracefully with placeholders like “Not available”.

### Startup behavior
- User can enable or disable “Launch at Login”.
- Default can be enabled if product direction supports it.

## Non-Functional Requirements
- Low CPU and memory usage.
- No noticeable battery drain.
- Smooth animations and no UI flicker.
- Reliable across sleep/wake, display change, and multiple desktop transitions.
- Safe permissions model with minimal intrusive prompts.

## Architecture Plan

### Module 1: App shell
Responsible for:
- app lifecycle
- background execution
- launch-at-login setup
- settings and quit actions

### Module 2: Notch tracker
Responsible for:
- screen geometry detection
- hover zone tracking
- enter/exit debounce logic
- multi-display handling where relevant

### Module 3: Overlay UI
Responsible for:
- floating notch panel
- animations
- compact widget layout
- dark/light mode support

### Module 4: Metrics engine
Responsible for:
- polling system stats
- caching latest values
- formatting values for UI
- fault tolerance when some sensors are inaccessible

## UX Notes
- UI should feel native to macOS.
- Dashboard should be compact, elegant, and fast.
- Prefer glanceable numbers over dense technical detail.
- Consider expandable secondary view later for more advanced stats.

## Edge Cases
- Mac without a notch: either disable notch hover mode or provide fallback trigger.
- External monitor active: ensure overlay appears on the correct display.
- Fullscreen apps: verify overlay behavior does not conflict.
- Temperature access limitations: show fallback status if exact values cannot be retrieved.

## Development Phases

### Phase 1: Foundation
- Create app shell.
- Make app run in background.
- Add launch at login.
- Add menu/settings entry.

### Phase 2: Notch interaction
- Detect notch hover area.
- Show/hide overlay panel.
- Add animation and debounce handling.

### Phase 3: Metrics
- Implement RAM, battery, and network speed.
- Investigate and implement temperature source.
- Build refresh loop and formatting.

### Phase 4: Hardening
- Test on login, sleep/wake, fullscreen apps, and multiple displays.
- Optimize for low resource usage.
- Handle failures and unavailable metrics cleanly.

## MVP Definition
The first usable version should include:
- background app behavior
- hover-over-notch trigger
- dashboard UI
- RAM usage
- network speed
- battery status
- launch at login

Temperature can be included in MVP only if a stable and acceptable implementation is confirmed during development.

## Future Enhancements
- CPU usage
- storage usage
- fan speed
- calendar or reminders widget
- music controls
- quick actions from the notch panel
- customizable widgets
- keyboard shortcut to open the panel

## Risks
- Precise temperature data may not be officially exposed in a clean way on macOS.
- Notch hover detection may require careful tuning for reliability.
- Background overlays can behave differently across macOS versions.

## Success Criteria
- App launches on startup.
- App stays alive in the background.
- Hovering over the notch reliably opens the panel.
- Panel shows RAM, battery, and network speed accurately.
- App feels lightweight and stable in daily use.

