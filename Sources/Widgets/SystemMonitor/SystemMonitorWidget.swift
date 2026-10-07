import SwiftUI
import IOKit.ps

enum SystemMonitorWidget: WidgetDefinition {
    struct Config: Codable, Hashable {
        var showCPU = true
        var showRAM = true
        var showBattery = true
        var showDisk = true
        var intervalSeconds = 2
        var theme = Look()
    }

    static let id = "system-monitor"
    static let displayName = "Monitor Sistem"
    static let symbol = "cpu"
    static let minimumSize = CGSize(width: 100, height: 80)
    static let defaultSize = CGSize(width: 420, height: 220)
    static let defaultConfig = Config()

    static func makeContent(config: Config, size: CGSize) -> some View {
        SystemMonitorView(config: config, size: size)
    }

    static func makeSettings(config: Binding<Config>) -> some View {
        SystemMonitorSettings(config: config)
    }
}

// MARK: - Sampler

struct Metric: Identifiable {
    let id: String
    let label: String
    let fraction: Double
    let detail: String
}

@MainActor
final class SystemSampler: ObservableObject {
    @Published private(set) var cpu = 0.0
    @Published private(set) var ramUsed = 0.0
    @Published private(set) var ramText = ""
    @Published private(set) var battery: (level: Double, charging: Bool)?
    @Published private(set) var diskUsed = 0.0
    @Published private(set) var diskText = ""

    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    func sample() {
        sampleCPU()
        sampleRAM()
        sampleDisk()
        battery = Self.readBattery()
    }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let now = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { previousTicks = now }
        guard let p = previousTicks else { return }
        let busy = Double(now.user &- p.user) + Double(now.system &- p.system) + Double(now.nice &- p.nice)
        let total = busy + Double(now.idle &- p.idle)
        if total > 0 { cpu = busy / total }
    }

    private func sampleRAM() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Double(sysconf(_SC_PAGESIZE))
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        ramUsed = min(1, used / total)
        ramText = "\(Self.gb(used)) / \(Self.gb(total)) GB"
    }

    private func sampleDisk() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage,
              total > 0 else { return }
        let used = Double(total) - Double(free)
        diskUsed = used / Double(total)
        diskText = "\(Self.gb(Double(free), digits: 0)) GB bebas"
    }

    private static func readBattery() -> (Double, Bool)? {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Double,
                  let max = d[kIOPSMaxCapacityKey] as? Double, max > 0 else { continue }
            return (cur / max, (d[kIOPSIsChargingKey] as? Bool) ?? false)
        }
        return nil
    }

    private static func gb(_ bytes: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", bytes / 1_073_741_824)
    }
}

// MARK: - Tampilan

struct SystemMonitorView: View {
    let config: SystemMonitorWidget.Config
    let size: CGSize
    @StateObject private var sampler = SystemSampler()
    @Environment(\.widgetActive) private var active

    private struct TaskKey: Hashable { let active: Bool; let interval: Int }

    private var metrics: [Metric] {
        var m: [Metric] = []
        if config.showCPU { m.append(Metric(id: "cpu", label: "CPU", fraction: sampler.cpu, detail: "")) }
        if config.showRAM { m.append(Metric(id: "ram", label: "RAM", fraction: sampler.ramUsed, detail: sampler.ramText)) }
        if config.showBattery, let b = sampler.battery {
            m.append(Metric(id: "bat", label: b.charging ? "Baterai ⚡︎" : "Baterai", fraction: b.level, detail: ""))
        }
        if config.showDisk { m.append(Metric(id: "disk", label: "Disk", fraction: sampler.diskUsed, detail: sampler.diskText)) }
        return m
    }

    var body: some View {
        let items = metrics
        let pad = min(size.width, size.height) * 0.05
        let area = CGSize(width: size.width - pad * 2, height: size.height - pad * 2)
        let n = max(1, items.count)
        let cols = max(1, min(n, Int((Double(n) * area.width / max(area.height, 1)).squareRoot().rounded(.up))))
        let rows = Int((Double(n) / Double(cols)).rounded(.up))
        let cell = CGSize(width: area.width / CGFloat(cols), height: area.height / CGFloat(rows))

        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { c in
                        let i = r * cols + c
                        if i < items.count {
                            gauge(items[i], cell)
                        } else {
                            Color.clear.frame(width: cell.width, height: cell.height)
                        }
                    }
                }
            }
        }
        .foregroundStyle(config.theme.foreground)
        .padding(pad)
        .frame(width: size.width, height: size.height)
        .themed(config.theme, size: size)
        .task(id: TaskKey(active: active, interval: config.intervalSeconds)) {
            guard active else { return }
            while !Task.isCancelled {
                sampler.sample()
                try? await Task.sleep(nanoseconds: UInt64(max(1, config.intervalSeconds)) * 1_000_000_000)
            }
        }
    }

    private func gauge(_ m: Metric, _ cell: CGSize) -> some View {
        let showDetail = !m.detail.isEmpty && cell.height > 110
        let showLabel = cell.height > 70
        let textH = (showLabel ? 1.0 : 0) + (showDetail ? 0.8 : 0)
        let d = max(10, min(cell.width * 0.85, cell.height * 0.9 - textH * 14))
        let line = max(2, d * 0.1)
        let tint = m.fraction > 0.9 ? Color.red : (m.fraction > 0.75 ? config.theme.accent : config.theme.foreground)

        return VStack(spacing: 2) {
            ZStack {
                Circle().stroke(config.theme.foreground.opacity(0.18), lineWidth: line)
                Circle().trim(from: 0, to: max(0.005, m.fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                LText(text: "\(Int((m.fraction * 100).rounded()))%", look: config.theme,
                      size: d * 0.26, weight: .semibold, monoDigits: true)
            }
            .frame(width: d, height: d)
            if showLabel {
                LText(text: m.label, look: config.theme, size: max(9, d * 0.14), weight: .medium)
                    .foregroundStyle(config.theme.secondary)
            }
            if showDetail {
                LText(text: m.detail, look: config.theme, size: max(8, d * 0.11))
                    .foregroundStyle(config.theme.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(width: cell.width, height: cell.height)
        .accessibilityElement(children: .combine)
    }
}

struct SystemMonitorSettings: View {
    @Binding var config: SystemMonitorWidget.Config

    var body: some View {
        LookSettings(look: $config.theme)
        Toggle("CPU", isOn: $config.showCPU)
        Toggle("RAM", isOn: $config.showRAM)
        Toggle("Baterai", isOn: $config.showBattery)
        Toggle("Penyimpanan", isOn: $config.showDisk)
        Picker("Interval pembaruan", selection: $config.intervalSeconds) {
            ForEach([1, 2, 5, 10, 30], id: \.self) { Text("\($0) detik").tag($0) }
        }
    }
}
