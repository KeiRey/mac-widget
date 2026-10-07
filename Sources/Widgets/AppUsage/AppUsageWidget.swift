import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum AppUsageWidget: WidgetDefinition {
    typealias CellShape = HeatmapShape

    enum LabelPosition: String, Codable, CaseIterable, Identifiable {
        case auto, leading, top, hidden
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Otomatis"
            case .leading: return "Di kiri"
            case .top: return "Di atas"
            case .hidden: return "Sembunyikan"
            }
        }
    }

    /// Satu chart untuk satu aplikasi. Semua field bisa diatur per aplikasi.
    struct AppChart: Codable, Hashable, Identifiable {
        var id: String                 // bundle identifier
        var title = ""                 // kosong = nama aplikasi
        var color: RGB?
        /// Menit per hari untuk kecerahan penuh. 0 = otomatis (nilai tertinggi yang terlihat).
        var goalMinutes = 0
        /// nil = ikut pengaturan widget. 0 = hari ini per jam. N = N minggu. 100 = isi lebar.
        var weeks: Int?
        var metric: UsageMetric?
    }

    struct Config: Codable, Hashable {
        var apps: [AppChart] = AppUsageWidget.suggestedApps()
        var metric: UsageMetric = .active
        /// 0 = hari ini (per jam). N = jumlah minggu ala chart kontribusi GitHub.
        var weeks = AppUsageWidget.fitWidth
        var shape: CellShape = .rounded
        var gap = 0.18
        var stepped = true
        var labels: LabelPosition = .auto
        var showIcon = true
        var showName = true
        var showTotal = true
        var showMonths = true
        var showWeekdays = true
        var showLegend = true
        var mondayFirst = true
        var theme = Look()
    }

    /// Nilai khusus `weeks`: jumlah minggu mengikuti lebar widget.
    static let fitWidth = HeatmapChart.fitWidth

    static let id = "app-usage"
    static let displayName = "Penggunaan Aplikasi"
    static let symbol = "square.grid.3x3.fill"
    static let minimumSize = CGSize(width: 140, height: 80)
    static let defaultSize = CGSize(width: 560, height: 260)
    static let defaultConfig = Config()
    static let isHoverable = true

    static let palette: [RGB] = [
        RGB(Color(red: 0.22, green: 0.78, blue: 0.40)),
        RGB(Color(red: 0.25, green: 0.55, blue: 1.00)),
        RGB(Color(red: 1.00, green: 0.62, blue: 0.20)),
        RGB(Color(red: 0.70, green: 0.40, blue: 0.95)),
        RGB(Color(red: 1.00, green: 0.38, blue: 0.55)),
        RGB(Color(red: 0.20, green: 0.75, blue: 0.80)),
    ]

    /// Aplikasi umum yang terpasang, sebagai isi awal chart.
    static func suggestedApps() -> [AppChart] {
        let candidates = ["com.microsoft.VSCode", "dev.warp.Warp-Stable", "com.google.Chrome"]
        let installed = candidates.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        return installed.enumerated().map { i, id in
            var c = AppChart(id: id)
            c.color = palette[i % palette.count]
            return c
        }
    }

    static func makeContent(config: Config, size: CGSize) -> some View {
        AppUsageView(config: config, size: size)
    }

    static func makeSettings(config: Binding<Config>) -> some View {
        AppUsageSettings(config: config)
    }
}

// MARK: - Info aplikasi

enum AppInfo {
    private static var icons: [String: NSImage] = [:]

    static func url(_ bundle: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) }

    static func icon(_ bundle: String) -> NSImage? {
        if let i = icons[bundle] { return i }
        guard let url = url(bundle) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundle] = img
        return img
    }

    @MainActor
    static func name(_ bundle: String) -> String {
        if let n = UsageStore.shared.data.names[bundle] { return n }
        if let url = url(bundle), let b = Bundle(url: url),
           let n = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") ?? b.object(forInfoDictionaryKey: "CFBundleName")) as? String {
            return n
        }
        return bundle
    }

    static func duration(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        if seconds > 0 && m == 0 { return "<1m" }
        return m >= 60 ? "\(m / 60)j \(m % 60)m" : "\(m)m"
    }
}

// MARK: - Tampilan

struct AppUsageView: View {
    let config: AppUsageWidget.Config
    let size: CGSize
    @ObservedObject private var store = UsageStore.shared


    var body: some View {
        let look = config.theme
        let pad = min(size.width, size.height) * 0.05
        let area = CGSize(width: size.width - pad * 2, height: size.height - pad * 2)
        let n = config.apps.count

        Group {
            if n == 0 {
                LText(text: "Tambah aplikasi di pengaturan", look: look, size: max(10, min(area.width / 18, 18)), weight: .medium)
                    .foregroundStyle(look.secondary)
                    .frame(width: area.width, height: area.height)
            } else {
                let spacing = max(4, area.height * 0.03)
                let rowH = (area.height - spacing * CGFloat(n - 1)) / CGFloat(n)
                VStack(spacing: spacing) {
                    ForEach(config.apps) { app in
                        row(app, CGSize(width: area.width, height: rowH))
                    }
                }
                .frame(width: area.width, height: area.height)
            }
        }
        .foregroundStyle(look.foreground)
        .padding(pad)
        .frame(width: size.width, height: size.height)
        .themed(look, size: size)
    }

    // MARK: Baris per aplikasi

    @ViewBuilder
    private func row(_ app: AppUsageWidget.AppChart, _ box: CGSize) -> some View {
        let look = config.theme
        let metric = app.metric ?? config.metric
        let weeks = app.weeks ?? config.weeks
        let today = UsageStore.key(Date())
        let total = store.seconds(app.id, metric, day: today)
        let color = app.color?.color ?? look.accent
        let name = app.title.isEmpty ? AppInfo.name(app.id) : app.title

        let hasLabel = config.showIcon || config.showName || config.showTotal
        let position = hasLabel ? resolvedLabel(box) : .hidden
        let labelFont = max(9, min(box.height * (position == .top ? 0.28 : 0.2), 15))
        let textH = (config.showName ? labelFont * 1.2 : 0) + (config.showTotal ? labelFont * 0.85 * 1.2 : 0)
        let labelH = max(textH, config.showIcon ? labelFont * 1.6 : 0)

        let label = HStack(spacing: labelFont * 0.5) {
            if config.showIcon, let icon = AppInfo.icon(app.id) {
                Image(nsImage: icon).resizable().interpolation(.high)
                    .frame(width: labelFont * 1.6, height: labelFont * 1.6)
            }
            if config.showName || config.showTotal {
                VStack(alignment: .leading, spacing: 0) {
                    if config.showName {
                        LText(text: name, look: look, size: labelFont, weight: .semibold)
                    }
                    if config.showTotal {
                        LText(text: AppInfo.duration(total), look: look, size: labelFont * 0.85, weight: .regular, monoDigits: true)
                            .foregroundStyle(config.showName ? look.secondary : look.foreground)
                    }
                }
            }
        }
        .lineLimit(1)

        let content = Group {
            switch position {
            case .leading:
                let w = min(box.width * 0.28, 190)
                HStack(spacing: box.width * 0.02) {
                    label.frame(width: w, alignment: .leading)
                    chart(app, weeks: weeks, metric: metric, color: color,
                          CGSize(width: box.width - w - box.width * 0.02, height: box.height))
                }
            case .top:
                VStack(alignment: .leading, spacing: 3) {
                    label
                    chart(app, weeks: weeks, metric: metric, color: color,
                          CGSize(width: box.width, height: max(1, box.height - labelH - 3)))
                }
            default:
                chart(app, weeks: weeks, metric: metric, color: color, box)
            }
        }
        content
            .frame(width: box.width, height: box.height, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name): \(AppInfo.duration(total)) hari ini")
    }

    private func resolvedLabel(_ box: CGSize) -> AppUsageWidget.LabelPosition {
        switch config.labels {
        case .hidden: return .hidden
        case .leading: return .leading
        case .top: return box.height >= 44 ? .top : .hidden
        case .auto:
            if box.width >= 420 && box.height >= 34 { return .leading }
            return box.height >= 56 ? .top : .hidden
        }
    }

    // MARK: Chart

    private func chart(_ app: AppUsageWidget.AppChart, weeks: Int, metric: UsageMetric,
                       color: Color, _ box: CGSize) -> some View {
        HeatmapChart(
            box: box, weeks: weeks, color: color,
            goal: app.goalMinutes > 0 ? Double(app.goalMinutes * 60) : nil, minGoal: 60,
            look: config.theme, shape: config.shape, gap: config.gap, stepped: config.stepped,
            mondayFirst: config.mondayFirst, showMonths: config.showMonths,
            showWeekdays: config.showWeekdays, showLegend: config.showLegend,
            dayValue: { store.seconds(app.id, metric, day: UsageStore.key($0)) },
            hourValues: { store.hourly(app.id, metric, day: UsageStore.key(Date())) },
            tooltip: { tooltip(app, metric: metric, $0) })
    }

    // MARK: Tooltip

    private func tooltip(_ app: AppUsageWidget.AppChart, metric: UsageMetric, _ hit: HeatmapChart.HeatHit) -> TooltipContent {
        let name = app.title.isEmpty ? AppInfo.name(app.id) : app.title
        let key = UsageStore.key(hit.date)
        let active = store.hourly(app.id, .active, day: key)
        let running = store.hourly(app.id, .running, day: key)
        let dateText = hit.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year())
        let chosen = metric == .active ? active : running

        func hourLabel(_ h: Int) -> String { String(format: "%02d.00–%02d.00", h, (h + 1) % 24) }

        if let h = hit.hour {
            return TooltipContent(
                title: hourLabel(h), subtitle: "\(name) · \(dateText)",
                sections: [.init(rows: [
                    .init(label: "Aktif di depan", value: AppInfo.duration(active[h]), emphasized: metric == .active),
                    .init(label: "Aplikasi berjalan", value: AppInfo.duration(running[h]), emphasized: metric == .running),
                ])])
        }

        let peak = chosen.enumerated().max { $0.element < $1.element }
        var rows: [TooltipContent.Row] = [
            .init(label: "Aktif di depan", value: AppInfo.duration(active.reduce(0, +)), emphasized: metric == .active),
            .init(label: "Aplikasi berjalan", value: AppInfo.duration(running.reduce(0, +)), emphasized: metric == .running),
        ]
        var sections = [TooltipContent.Section(rows: rows)]
        rows = []
        if let peak, peak.element > 0 {
            rows.append(.init(label: "Jam tersibuk", value: "\(hourLabel(peak.offset)) (\(AppInfo.duration(peak.element)))"))
        }
        rows.append(.init(label: "Dari target", value: "\(Int((hit.fraction * 100).rounded()))%"))
        sections.append(.init(rows: rows))
        return TooltipContent(title: dateText, subtitle: name, sections: sections)
    }
}

// MARK: - Pengaturan

struct AppUsageSettings: View {
    @Binding var config: AppUsageWidget.Config
    @ObservedObject private var store = UsageStore.shared

    private static let rangeOptions: [(Int, String)] = [
        (AppUsageWidget.fitWidth, "Isi lebar widget"), (0, "Hari ini (per jam)"), (4, "4 minggu"), (8, "8 minggu"), (12, "12 minggu"),
        (20, "20 minggu"), (26, "26 minggu"), (52, "52 minggu (1 tahun)"),
    ]

    var body: some View {
        Picker("Hitung waktu", selection: $config.metric) {
            ForEach(UsageMetric.allCases) { Text($0.title).tag($0) }
        }
        Picker("Rentang", selection: $config.weeks) {
            ForEach(Self.rangeOptions, id: \.0) { Text($0.1).tag($0.0) }
        }
        Picker("Bentuk sel", selection: $config.shape) {
            ForEach(AppUsageWidget.CellShape.allCases) { Text($0.title).tag($0) }
        }
        HStack {
            Text("Jarak antar sel")
            Slider(value: $config.gap, in: 0...0.5)
        }
        Toggle("Kecerahan bertingkat (seperti GitHub)", isOn: $config.stepped)
        Picker("Posisi label (nama & total)", selection: $config.labels) {
            ForEach(AppUsageWidget.LabelPosition.allCases) { Text($0.title).tag($0) }
        }
        Toggle("Tampilkan ikon aplikasi", isOn: $config.showIcon)
        Toggle("Tampilkan nama aplikasi", isOn: $config.showName)
        Toggle("Tampilkan total hari ini", isOn: $config.showTotal)
        Toggle("Label bulan", isOn: $config.showMonths)
        Toggle("Label hari (Sen, Rab, Jum)", isOn: $config.showWeekdays)
        Toggle("Legend Kurang → Banyak", isOn: $config.showLegend)
        Toggle("Minggu dimulai hari Senin", isOn: $config.mondayFirst)
        LookSettings(look: $config.theme)

        Section("Aplikasi") {
            ForEach($config.apps) { $app in
                AppChartSettings(app: $app, defaultWeeks: config.weeks) {
                    config.apps.removeAll { $0.id == app.id }
                }
            }
            addMenu
            Text("Waktu dicatat selama DeskWidgets berjalan. Data hanya tersimpan di Mac ini (usage.json) dan tidak dikirim ke mana pun. Waktu “aktif” berhenti setelah 3 menit tanpa input.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Hapus seluruh riwayat penggunaan", role: .destructive) { store.clear() }
        }
    }

    private var addMenu: some View {
        let added = Set(config.apps.map(\.id))
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier && !added.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        let runningIDs = Set(running.compactMap(\.bundleIdentifier))
        let known = store.knownApps.filter { !added.contains($0.id) && !runningIDs.contains($0.id) }.prefix(15)

        return Menu {
            Section("Sedang terbuka") {
                ForEach(running, id: \.bundleIdentifier) { app in
                    Button(app.localizedName ?? app.bundleIdentifier ?? "?") { add(app.bundleIdentifier!) }
                }
            }
            if !known.isEmpty {
                Section("Pernah terdeteksi") {
                    ForEach(Array(known), id: \.id) { k in Button(k.name) { add(k.id) } }
                }
            }
            Divider()
            Button("Pilih dari Finder…") { pickFromDisk() }
        } label: {
            Label("Tambah aplikasi", systemImage: "plus")
        }
    }

    private func add(_ bundle: String) {
        guard !config.apps.contains(where: { $0.id == bundle }) else { return }
        var chart = AppUsageWidget.AppChart(id: bundle)
        chart.color = AppUsageWidget.palette[config.apps.count % AppUsageWidget.palette.count]
        config.apps.append(chart)
    }

    private func pickFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.message = "Pilih aplikasi yang ingin dipantau"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        add(id)
    }
}

private struct AppChartSettings: View {
    @Binding var app: AppUsageWidget.AppChart
    let defaultWeeks: Int
    let onDelete: () -> Void

    var body: some View {
        DisclosureGroup {
            TextField("Nama tampilan", text: $app.title, prompt: Text(AppInfo.name(app.id)))
            HStack {
                ColorPicker("Warna", selection: Binding(
                    get: { app.color?.color ?? .green },
                    set: { app.color = RGB($0) }))
                if app.color != nil { Button("Reset") { app.color = nil }.buttonStyle(.borderless) }
            }
            Stepper(app.goalMinutes == 0 ? "Target harian: otomatis" : "Target harian: \(app.goalMinutes) menit",
                    value: $app.goalMinutes, in: 0...1440, step: 15)
            Picker("Rentang", selection: Binding(
                get: { app.weeks ?? -1 },
                set: { app.weeks = $0 < 0 ? nil : $0 })) {
                Text("Ikut widget").tag(-1)
                Text("Isi lebar widget").tag(AppUsageWidget.fitWidth)
                Text("Hari ini (per jam)").tag(0)
                ForEach([4, 8, 12, 20, 26, 52], id: \.self) { Text("\($0) minggu").tag($0) }
            }
            Picker("Hitung waktu", selection: Binding(
                get: { app.metric?.rawValue ?? "" },
                set: { app.metric = UsageMetric(rawValue: $0) })) {
                Text("Ikut widget").tag("")
                ForEach(UsageMetric.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Button("Hapus dari widget", role: .destructive, action: onDelete)
        } label: {
            HStack {
                if let icon = AppInfo.icon(app.id) {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                Text(app.title.isEmpty ? AppInfo.name(app.id) : app.title)
                Spacer()
                Circle().fill(app.color?.color ?? .secondary).frame(width: 10, height: 10)
            }
        }
    }
}
