import Foundation
import IOKit.ps
import Darwin

// MARK: - IOHIDEventSystem private API
// Sourced from mac-temperature — works on Apple Silicon without sudo

@_silgen_name("IOHIDEventSystemClientCreate")
func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> OpaquePointer?

@_silgen_name("IOHIDEventSystemClientSetMatching")
func IOHIDEventSystemClientSetMatching(_ client: OpaquePointer, _ matching: CFDictionary)

@_silgen_name("IOHIDEventSystemClientCopyServices")
func IOHIDEventSystemClientCopyServices(_ client: OpaquePointer) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyProperty")
func IOHIDServiceClientCopyProperty(_ service: OpaquePointer, _ key: CFString) -> CFTypeRef?

@_silgen_name("IOHIDServiceClientCopyEvent")
func IOHIDServiceClientCopyEvent(
    _ service: OpaquePointer, _ type: Int64, _ options: Int32, _ timeout: Double
) -> OpaquePointer?

@_silgen_name("IOHIDEventGetFloatValue")
func IOHIDEventGetFloatValue(_ event: OpaquePointer, _ field: Int32) -> Double

private let kIOHIDEventTypeTemperature: Int64 = 15
private let kIOHIDEventFieldTemperatureLevel: Int32 = Int32(kIOHIDEventTypeTemperature << 16)

// MARK: - HIDTemperatureReader
// Directly from mac-temperature/Sources/main.swift

private struct SensorReading {
    let name: String
    let celsius: Double
}

private class HIDTemperatureReader {
    private var client: OpaquePointer?
    private var services: [OpaquePointer] = []

    init() { open() }
    deinit { client = nil }

    private func open() {
        guard let c = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return }
        client = c
        let matching: [String: Any] = ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 0x0005]
        IOHIDEventSystemClientSetMatching(c, matching as CFDictionary)
        guard let cfArray = IOHIDEventSystemClientCopyServices(c) else { return }
        var result: [OpaquePointer] = []
        for i in 0..<CFArrayGetCount(cfArray) {
            if let ptr = CFArrayGetValueAtIndex(cfArray, i) {
                result.append(OpaquePointer(ptr))
            }
        }
        services = result
    }

    func readAll() -> [SensorReading] {
        guard client != nil else { return [] }
        var byName: [String: Double] = [:]
        for svc in services {
            guard let event = IOHIDServiceClientCopyEvent(svc, kIOHIDEventTypeTemperature, 0, 0) else { continue }
            let celsius = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel)
            guard celsius > 0 && celsius < 150 else { continue }
            let name = (IOHIDServiceClientCopyProperty(svc, "Product" as CFString) as? String) ?? "sensor"
            byName[name] = max(byName[name] ?? celsius, celsius)
        }
        return byName.map { SensorReading(name: $0.key, celsius: $0.value) }
    }

    /// Returns the hottest die temperature, or nil if no sensors found.
    func hottestCelsius() -> Double? {
        let all = readAll()
        guard !all.isEmpty else { return nil }
        let die = all.filter { $0.name.contains("tdie") }
        let pool = die.isEmpty ? all : die
        return pool.max(by: { $0.celsius < $1.celsius })?.celsius
    }
}

// MARK: - MetricsEngine

class MetricsEngine: ObservableObject {
    @Published var ramUsage: String = "--"
    @Published var batteryStatus: String = "--"
    @Published var uploadSpeed: String = "--"
    @Published var downloadSpeed: String = "--"
    /// nil means no sensors found — tile is hidden in the UI
    @Published var temperature: String? = nil

    private var timer: Timer?
    private let hidReader = HIDTemperatureReader()

    // Network tracking — from fusion-net-stat
    private var prevNetBytes: (tx: Int64, rx: Int64) = (0, 0)
    private var prevNetTime: Date = .distantPast
    private var activeInterface: String = "en0"

    // MARK: - Lifecycle

    func start() {
        activeInterface = currentNetworkInterface()
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func update() {
        updateRAM()
        updateBattery()
        updateNetwork()
        updateTemperature()
    }

    // MARK: - RAM (Mach host statistics)

    private func updateRAM() {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            publish { self.ramUsage = "N/A" }
            return
        }
        let page = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count)) * page
        let gb = Double(used) / 1_073_741_824
        publish { self.ramUsage = String(format: "%.1f GB", gb) }
    }

    // MARK: - Battery (IOKit power sources)

    private func updateBattery() {
        let snap = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snap).takeRetainedValue() as [CFTypeRef]

        guard let src = list.first,
              let desc = IOPSGetPowerSourceDescription(snap, src)
                .takeUnretainedValue() as? [String: Any]
        else {
            publish { self.batteryStatus = "N/A" }
            return
        }

        let pct        = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
        let onAC       = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

        var label = "\(pct)%"
        if isCharging { label += " ⚡" } else if onAC { label += " ∞" }
        publish { self.batteryStatus = label }
    }

    // MARK: - Network (fusion-net-stat approach — active interface only)

    private func updateNetwork() {
        // Refresh active interface periodically in case it changes
        let iface = currentNetworkInterface()
        if iface != "unknown" { activeInterface = iface }

        guard let (rx, tx) = byteCounts(for: activeInterface) else {
            publish { self.uploadSpeed = "N/A"; self.downloadSpeed = "N/A" }
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(prevNetTime)

        if elapsed > 0 && prevNetTime != .distantPast {
            let txDelta = max(0, tx - prevNetBytes.tx)
            let rxDelta = max(0, rx - prevNetBytes.rx)
            let up = Double(txDelta) / elapsed
            let dn = Double(rxDelta) / elapsed
            publish {
                self.uploadSpeed   = formatSpeed(up)
                self.downloadSpeed = formatSpeed(dn)
            }
        }

        prevNetBytes = (tx, rx)
        prevNetTime = now
    }

    /// Reads byte counters for a named interface — from fusion-net-stat/SpeedTestMonitor.swift
    private func byteCounts(for interfaceName: String) -> (rx: Int64, tx: Int64)? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let head = ifap else { return nil }
        defer { freeifaddrs(ifap) }

        var rx: Int64 = 0
        var tx: Int64 = 0
        var found = false

        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let ifa = cursor {
            let name = String(cString: ifa.pointee.ifa_name)
            if name == interfaceName,
               ifa.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let data = ifa.pointee.ifa_data {
                let stats = data.load(as: if_data.self)
                rx = Int64(stats.ifi_ibytes)
                tx = Int64(stats.ifi_obytes)
                found = true
            }
            cursor = ifa.pointee.ifa_next
        }
        return found ? (rx, tx) : nil
    }

    /// Detects the active network interface via `route get default` — from fusion-net-stat/SpeedTestMonitor.swift
    private func currentNetworkInterface() -> String {
        let task = Process()
        task.launchPath = "/sbin/route"
        task.arguments = ["get", "default"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return "en0"
        }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in output.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("interface:") {
                let iface = t.replacingOccurrences(of: "interface:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !iface.isEmpty { return iface }
            }
        }
        return "en0"
    }

    // MARK: - Temperature (mac-temperature HID reader)

    private func updateTemperature() {
        if let celsius = hidReader.hottestCelsius() {
            let s = String(format: "%.0f°C", celsius)
            publish { self.temperature = s }
        } else {
            publish { self.temperature = nil }
        }
    }

    // MARK: - Helpers

    private func publish(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    deinit { stop() }
}

/// Network speed formatter — matches fusion-net-stat style (1024-based, compact suffixes)
private func formatSpeed(_ bps: Double) -> String {
    switch bps {
    case 1_048_576...: return String(format: "%.1f MB/s", bps / 1_048_576)
    case 1_024...:     return String(format: "%.1f KB/s", bps / 1_024)
    default:           return String(format: "%.0f B/s",  bps)
    }
}
