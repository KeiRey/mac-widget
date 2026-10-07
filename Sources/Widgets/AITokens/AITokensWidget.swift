import SwiftUI
import AppKit

enum AITokensWidget: WidgetDefinition {
    enum Style: String, Codable, CaseIterable, Identifiable {
        case heatmap, line
        var id: String { rawValue }
        var title: String { self == .heatmap ? "Heatmap (seperti GitHub)" : "Line chart" }
    }

    struct ProviderChart: Codable, Hashable, Identifiable {
        var id: String                 // id agent: claude, codex, antigravity, opencode
        var title = ""
        var color: RGB?
        /// Token per hari untuk kecerahan penuh pada heatmap. 0 = otomatis.
        var goalTokens = 0
        var weeks: Int?                // heatmap: nil = ikut widget
        var metric: TokenMetric?
    }

    struct Config: Codable, Hashable {
        var providers: [ProviderChart] = AITokensWidget.suggested()
        var style: Style = .heatmap
        var metric: TokenMetric = .all
        // Heatmap
        var weeks = HeatmapChart.fitWidth
        var shape: HeatmapShape = .rounded
        var gap = 0.18
        var stepped = true
        var labels: AppUsageWidget.LabelPosition = .auto
        var showIcon = true
        var showName = true
        var showTotal = true
        /// Tampilkan biaya (setara harga API) di samping total token.
        var showCost = true
        var showMonths = true
        var showWeekdays = true
        var showLegend = true
        var mondayFirst = true
        // Line chart: 0 = hari ini per jam, N = N hari terakhir
        var lineDays = 30
        var smooth = true
        var fillArea = true
        var showPoints = false
        var showGrid = true
        var showAxes = true
        /// Tiap agent diskalakan ke nilai tertingginya sendiri, supaya agent kecil tetap terlihat di samping yang besar.
        var separateScale = false
        var theme = Look()
    }

    static let id = "ai-tokens"
    static let displayName = "Penggunaan Token AI"
    static let symbol = "sparkles"
    static let minimumSize = CGSize(width: 160, height: 90)
    static let defaultSize = CGSize(width: 560, height: 260)
    static let defaultConfig = Config()
    static let isHoverable = true

    /// Agent yang jejak lognya ditemukan di Mac ini.
    static func suggested() -> [ProviderChart] {
        TokenProviders.all.filter(\.available).map { info in
            var c = ProviderChart(id: info.id)
            c.color = info.color
            return c
        }
    }

    static func makeContent(config: Config, size: CGSize) -> some View {
        AITokensView(config: config, size: size)
    }

    static func makeSettings(config: Binding<Config>) -> some View {
        AITokensSettings(config: config)
    }
}

// MARK: - Tampilan

struct AITokensView: View {
    let config: AITokensWidget.Config
    let size: CGSize
    @ObservedObject private var store = TokenStore.shared
    @Environment(\.widgetActive) private var active

    var body: some View {
        let look = config.theme
        let pad = min(size.width, size.height) * 0.05
        let area = CGSize(width: size.width - pad * 2, height: size.height - pad * 2)

        Group {
            if config.providers.isEmpty {
                LText(text: "Tambah agent di pengaturan", look: look, size: max(10, min(area.width / 18, 18)), weight: .medium)
                    .foregroundStyle(look.secondary)
                    .frame(width: area.width, height: area.height)
            } else if config.style == .line {
                lineView(area)
            } else {
                heatmapView(area)
            }
        }
        .foregroundStyle(look.foreground)
        .padding(pad)
        .frame(width: size.width, height: size.height)
        .themed(look, size: size)
        // Data dibaca dari log agent; segarkan tiap menit selama widget terlihat.
        .task(id: active) {
            guard active else { return }
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private func name(_ p: AITokensWidget.ProviderChart) -> String {
        p.title.isEmpty ? (TokenProviders.info(p.id)?.name ?? p.id) : p.title
    }

    private func color(_ p: AITokensWidget.ProviderChart) -> Color {
        (p.color ?? TokenProviders.info(p.id)?.color)?.color ?? config.theme.accent
    }

    private func todayTotal(_ p: AITokensWidget.ProviderChart) -> Double {
        store.total(p.id, p.metric ?? config.metric, day: DayKey.string(Date()))
    }

    /// Teks ringkas untuk label: total sesuai metrik, plus biaya bila diminta.
    private func todayText(_ p: AITokensWidget.ProviderChart) -> String {
        let metric = p.metric ?? config.metric
        let main = TokenStore.format(todayTotal(p), metric)
        guard config.showCost, metric != .cost else { return main }
        return main + " · " + TokenFormat.money(store.total(p.id, .cost, day: DayKey.string(Date())))
    }

    // MARK: Heatmap

    private func heatmapView(_ area: CGSize) -> some View {
        let n = config.providers.count
        let spacing = max(4, area.height * 0.03)
        let rowH = (area.height - spacing * CGFloat(n - 1)) / CGFloat(n)
        return VStack(spacing: spacing) {
            ForEach(config.providers) { p in row(p, CGSize(width: area.width, height: rowH)) }
        }
        .frame(width: area.width, height: area.height)
    }

    @ViewBuilder
    private func row(_ p: AITokensWidget.ProviderChart, _ box: CGSize) -> some View {
        let look = config.theme
        let hasLabel = config.showIcon || config.showName || config.showTotal
        let position = hasLabel ? resolvedLabel(box) : .hidden
        let labelFont = max(9, min(box.height * (position == .top ? 0.28 : 0.2), 15))
        let textH = (config.showName ? labelFont * 1.2 : 0) + (config.showTotal ? labelFont * 0.85 * 1.2 : 0)
        let labelH = max(textH, config.showIcon ? labelFont * 1.6 : 0)
        let info = TokenProviders.info(p.id)

        let label = HStack(spacing: labelFont * 0.5) {
            if config.showIcon { badge(p, labelFont * 1.6) }
            if config.showName || config.showTotal {
                VStack(alignment: .leading, spacing: 0) {
                    if config.showName {
                        LText(text: name(p) + (info?.estimated == true ? " ~" : ""), look: look, size: labelFont, weight: .semibold)
                    }
                    if config.showTotal {
                        LText(text: todayText(p), look: look, size: labelFont * 0.85, monoDigits: true)
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
                    heat(p, CGSize(width: box.width - w - box.width * 0.02, height: box.height))
                }
            case .top:
                VStack(alignment: .leading, spacing: 3) {
                    label
                    heat(p, CGSize(width: box.width, height: max(1, box.height - labelH - 3)))
                }
            default:
                heat(p, box)
            }
        }
        content
            .frame(width: box.width, height: box.height, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name(p)): \(todayText(p)) hari ini")
    }

    private func heat(_ p: AITokensWidget.ProviderChart, _ box: CGSize) -> some View {
        let metric = p.metric ?? config.metric
        return HeatmapChart(
            box: box, weeks: p.weeks ?? config.weeks, color: color(p),
            goal: p.goalTokens > 0 ? Double(p.goalTokens) : nil, minGoal: metric == .cost ? 0.01 : 1000,
            look: config.theme, shape: config.shape, gap: config.gap, stepped: config.stepped,
            mondayFirst: config.mondayFirst, showMonths: config.showMonths,
            showWeekdays: config.showWeekdays, showLegend: config.showLegend,
            dayValue: { store.total(p.id, metric, day: DayKey.string($0)) },
            hourValues: { store.hourly(p.id, metric, day: DayKey.string(Date())) },
            tooltip: { heatTooltip(p, $0) })
    }

    // MARK: Tooltip

    private static func hourLabel(_ h: Int) -> String { String(format: "%02d.00–%02d.00", h, (h + 1) % 24) }

    /// Baris rincian token + biaya untuk satu agent pada satu hari (atau satu jam).
    private func usageRows(_ b: TokenBreakdown) -> [TooltipContent.Section] {
        let tokens = TooltipContent.Section(rows: [
            .init(label: "Input", value: TokenFormat.short(b.input)),
            .init(label: "Output", value: TokenFormat.short(b.output)),
            .init(label: "Cache read", value: TokenFormat.short(b.cacheRead), dim: true),
            .init(label: "Cache write", value: TokenFormat.short(b.cacheWrite), dim: true),
            .init(label: "Total token", value: TokenFormat.short(b.total), emphasized: true),
        ])
        let allUnpriced = b.cost == 0 && !b.unpriced.isEmpty
        let money = TooltipContent.Section(rows: [
            .init(label: "Biaya (USD)", value: allUnpriced ? "harga belum diatur" : TokenFormat.money(b.cost), emphasized: true),
        ])
        return [tokens, money]
    }

    private func modelSection(_ b: TokenBreakdown) -> TooltipContent.Section? {
        guard !b.perModel.isEmpty else { return nil }
        return .init(heading: "Per model", rows: b.perModel.prefix(6).map {
            .init(label: $0.model, value: TokenFormat.short($0.tokens) + " · " + ($0.priced ? TokenFormat.money($0.cost) : "?"))
        })
    }

    private func heatTooltip(_ p: AITokensWidget.ProviderChart, _ hit: HeatmapChart.HeatHit) -> TooltipContent {
        let dateText = hit.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year())
        let b = store.breakdown(p.id, day: DayKey.string(hit.date), hour: hit.hour)
        let title = hit.hour.map { Self.hourLabel($0) } ?? dateText
        let subtitle = hit.hour != nil ? "\(name(p)) · \(dateText)" : name(p)
        guard b.total > 0 else {
            return TooltipContent(title: title, subtitle: subtitle, sections: [.init(rows: [.init(label: "Aktivitas", value: "tidak ada", dim: true)])])
        }
        var sections = usageRows(b)
        if let m = modelSection(b), b.perModel.count > 1 || !b.unpriced.isEmpty { sections.append(m) }
        var note = "Biaya = perkiraan setara harga API, bukan tagihan langganan."
        if !b.unpriced.isEmpty { note = "Harga belum diatur: \(b.unpriced.joined(separator: ", ")). " + note }
        return TooltipContent(title: title, subtitle: subtitle, sections: sections, footnote: note)
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

    private func badge(_ p: AITokensWidget.ProviderChart, _ s: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.28, style: .continuous).fill(color(p))
            Text(TokenProviders.info(p.id)?.initial ?? "?")
                .font(.system(size: s * 0.58, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: s, height: s)
    }

    // MARK: Line chart

    private func lineTooltip(_ i: Int, hourly: Bool, days: [Date]) -> TooltipContent? {
        let date = hourly ? Date() : days[i]
        let key = DayKey.string(date)
        let dateText = date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year())
        var sections: [TooltipContent.Section] = []
        var sumTokens = 0.0, sumCost = 0.0, unpriced = Set<String>()
        for p in config.providers {
            let b = store.breakdown(p.id, day: key, hour: hourly ? i : nil)
            guard b.total > 0 else { continue }
            sumTokens += b.total; sumCost += b.cost; unpriced.formUnion(b.unpriced)
            let costText = b.cost == 0 && !b.unpriced.isEmpty ? "?" : TokenFormat.money(b.cost)
            sections.append(.init(heading: name(p), color: p.color ?? TokenProviders.info(p.id)?.color, rows: [
                .init(label: "Input", value: TokenFormat.short(b.input)),
                .init(label: "Output", value: TokenFormat.short(b.output)),
                .init(label: "Total token", value: TokenFormat.short(b.total), emphasized: true),
                .init(label: "Biaya (USD)", value: costText, emphasized: true),
            ]))
        }
        let title = hourly ? Self.hourLabel(i) : dateText
        guard !sections.isEmpty else {
            return TooltipContent(title: title, subtitle: hourly ? dateText : nil,
                                  sections: [.init(rows: [.init(label: "Aktivitas", value: "tidak ada", dim: true)])])
        }
        if sections.count > 1 {
            sections.append(.init(heading: "Semua agent", rows: [
                .init(label: "Total token", value: TokenFormat.short(sumTokens), emphasized: true),
                .init(label: "Biaya (USD)", value: TokenFormat.money(sumCost), emphasized: true),
            ]))
        }
        var note = "Biaya = perkiraan setara harga API."
        if !unpriced.isEmpty { note = "Harga belum diatur: \(unpriced.sorted().joined(separator: ", ")). " + note }
        return TooltipContent(title: title, subtitle: hourly ? dateText : nil, sections: sections, footnote: note)
    }

    private func lineView(_ area: CGSize) -> some View {
        let look = config.theme
        let showLegend = area.height >= 80
        let legendFont = max(9, min(area.height * 0.07, 13))
        let legendH = showLegend ? legendFont * 1.6 : 0
        let chartBox = CGSize(width: area.width, height: max(1, area.height - legendH - (showLegend ? 4 : 0)))

        let hourly = config.lineDays == 0
        let today = Date()
        let cal = Calendar.current
        let days: [Date] = hourly ? [] : (0..<config.lineDays).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let currentHour = cal.component(.hour, from: today)

        let series: [LineSeries] = config.providers.map { p in
            let metric = p.metric ?? config.metric
            let values: [Double?] = hourly
                ? store.hourly(p.id, metric, day: DayKey.string(today)).enumerated().map { $0.offset <= currentHour ? $0.element : nil }
                : days.map { store.total(p.id, metric, day: DayKey.string($0)) }
            guard config.separateScale else { return LineSeries(id: p.id, color: color(p), values: values) }
            let peak = max(1, values.compactMap { $0 }.max() ?? 1)
            return LineSeries(id: p.id, color: color(p), values: values.map { $0.map { $0 / peak } })
        }

        let metric = config.metric
        let axisFormat: (Double) -> String = config.separateScale
            ? { String(Int(($0 * 100).rounded())) + "%" }
            : { TokenStore.format($0, metric) }

        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("dMMM")
        let xLabels = hourly ? (0..<24).map { String(format: "%02d", $0) } : days.map { fmt.string(from: $0) }

        return VStack(alignment: .leading, spacing: 4) {
            if showLegend {
                HStack(spacing: legendFont * 1.2) {
                    ForEach(config.providers) { p in
                        HStack(spacing: legendFont * 0.35) {
                            Circle().fill(color(p)).frame(width: legendFont * 0.7, height: legendFont * 0.7)
                            if config.showName { LText(text: name(p), look: look, size: legendFont, weight: .semibold) }
                            if config.showTotal {
                                LText(text: todayText(p), look: look, size: legendFont * 0.9, monoDigits: true)
                                    .foregroundStyle(look.secondary)
                            }
                        }
                    }
                }
                .lineLimit(1)
                .frame(height: legendH, alignment: .leading)
            }
            LineChart(box: chartBox, series: series, xLabels: xLabels, look: look,
                      smooth: config.smooth, fillArea: config.fillArea, showPoints: config.showPoints,
                      showGrid: config.showGrid, showAxes: config.showAxes,
                      format: axisFormat,
                      tooltip: { lineTooltip($0, hourly: hourly, days: days) })
        }
        .frame(width: area.width, height: area.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Penggunaan token AI: " + config.providers.map { "\(name($0)) \(todayText($0)) hari ini" }.joined(separator: ", "))
    }
}

// MARK: - Pengaturan

struct AITokensSettings: View {
    @Binding var config: AITokensWidget.Config
    @ObservedObject private var store = TokenStore.shared

    var body: some View {
        Picker("Bentuk chart", selection: $config.style) {
            ForEach(AITokensWidget.Style.allCases) { Text($0.title).tag($0) }
        }
        Picker("Hitung token", selection: $config.metric) {
            ForEach(TokenMetric.allCases) { Text($0.title).tag($0) }
        }

        if config.style == .heatmap {
            Picker("Rentang", selection: $config.weeks) {
                Text("Isi lebar widget").tag(HeatmapChart.fitWidth)
                Text("Hari ini (per jam)").tag(0)
                ForEach([4, 8, 12, 20, 26, 52], id: \.self) { Text("\($0) minggu").tag($0) }
            }
            Picker("Bentuk sel", selection: $config.shape) {
                ForEach(HeatmapShape.allCases) { Text($0.title).tag($0) }
            }
            HStack {
                Text("Jarak antar sel")
                Slider(value: $config.gap, in: 0...0.5)
            }
            Toggle("Kecerahan bertingkat (seperti GitHub)", isOn: $config.stepped)
            Picker("Posisi label (nama & total)", selection: $config.labels) {
                ForEach(AppUsageWidget.LabelPosition.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Label bulan", isOn: $config.showMonths)
            Toggle("Label hari (Sen, Rab, Jum)", isOn: $config.showWeekdays)
            Toggle("Legend Kurang → Banyak", isOn: $config.showLegend)
            Toggle("Minggu dimulai hari Senin", isOn: $config.mondayFirst)
            Toggle("Tampilkan ikon agent", isOn: $config.showIcon)
        } else {
            Picker("Rentang", selection: $config.lineDays) {
                Text("Hari ini (per jam)").tag(0)
                ForEach([7, 14, 30, 60, 90], id: \.self) { Text("\($0) hari").tag($0) }
            }
            Toggle("Kurva halus", isOn: $config.smooth)
            Toggle("Area berwarna di bawah garis", isOn: $config.fillArea)
            Toggle("Titik di tiap data", isOn: $config.showPoints)
            Toggle("Garis grid", isOn: $config.showGrid)
            Toggle("Label sumbu", isOn: $config.showAxes)
            Toggle("Skala terpisah per agent (0–100%)", isOn: $config.separateScale)
        }
        Toggle("Tampilkan nama agent", isOn: $config.showName)
        Toggle("Tampilkan total hari ini", isOn: $config.showTotal)
        Toggle("Tampilkan biaya (USD) di samping total", isOn: $config.showCost)
        LookSettings(look: $config.theme)

        Section("Agent") {
            ForEach($config.providers) { $p in
                ProviderSettings(provider: $p, heatmap: config.style == .heatmap) {
                    config.providers.removeAll { $0.id == p.id }
                }
            }
            addMenu
            statusRow
            Text("Dibaca dari log lokal tiap agent (Claude Code, Codex, OpenCode, Antigravity CLI); hanya angka token dan waktu yang diambil, isi percakapan tidak disimpan, dan tidak ada yang dikirim ke mana pun. Antigravity (~) berformat internal tidak terdokumentasi, jadi angkanya perkiraan.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Hitung ulang dari awal") { Task { await store.rescanFromScratch() } }
                .disabled(store.scanning)
        }

        PricingSettings()
    }

    private var addMenu: some View {
        let added = Set(config.providers.map(\.id))
        let candidates = TokenProviders.all.filter { !added.contains($0.id) }
        return Menu {
            ForEach(candidates) { info in
                Button(info.name + (info.available ? "" : " (log tidak ditemukan)")) {
                    var c = AITokensWidget.ProviderChart(id: info.id)
                    c.color = info.color
                    config.providers.append(c)
                }
            }
        } label: {
            Label("Tambah agent", systemImage: "plus")
        }
        .disabled(candidates.isEmpty)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            if store.scanning { ProgressView().controlSize(.small); Text("Memindai log…") }
            else if let t = store.lastScan { Text("Terakhir dipindai \(t.formatted(date: .omitted, time: .shortened))") }
            else { Text("Belum dipindai") }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

private struct ProviderSettings: View {
    @Binding var provider: AITokensWidget.ProviderChart
    let heatmap: Bool
    let onDelete: () -> Void

    var body: some View {
        let info = TokenProviders.info(provider.id)
        DisclosureGroup {
            TextField("Nama tampilan", text: $provider.title, prompt: Text(info?.name ?? provider.id))
            HStack {
                ColorPicker("Warna", selection: Binding(
                    get: { (provider.color ?? info?.color)?.color ?? .green },
                    set: { provider.color = RGB($0) }))
                if provider.color != nil { Button("Reset") { provider.color = nil }.buttonStyle(.borderless) }
            }
            if heatmap {
                Stepper(provider.goalTokens == 0 ? "Target harian: otomatis" : "Target harian: \(TokenFormat.short(Double(provider.goalTokens))) token",
                        value: $provider.goalTokens, in: 0...2_000_000_000, step: provider.goalTokens >= 10_000_000 ? 5_000_000 : 500_000)
                Picker("Rentang", selection: Binding(
                    get: { provider.weeks ?? -1 },
                    set: { provider.weeks = $0 < 0 ? nil : $0 })) {
                    Text("Ikut widget").tag(-1)
                    Text("Isi lebar widget").tag(HeatmapChart.fitWidth)
                    Text("Hari ini (per jam)").tag(0)
                    ForEach([4, 8, 12, 20, 26, 52], id: \.self) { Text("\($0) minggu").tag($0) }
                }
            }
            Picker("Hitung token", selection: Binding(
                get: { provider.metric?.rawValue ?? "" },
                set: { provider.metric = TokenMetric(rawValue: $0) })) {
                Text("Ikut widget").tag("")
                ForEach(TokenMetric.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Button("Hapus dari widget", role: .destructive, action: onDelete)
        } label: {
            HStack {
                Text(provider.title.isEmpty ? (info?.name ?? provider.id) : provider.title)
                Spacer()
                Circle().fill((provider.color ?? info?.color)?.color ?? .secondary).frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - Tabel harga

/// Biaya dihitung dari token per model dengan harga ini; model tanpa aturan dianggap belum berharga.
private struct PricingSettings: View {
    @ObservedObject private var pricing = PricingStore.shared
    @ObservedObject private var store = TokenStore.shared

    var body: some View {
        Section("Harga per 1 juta token (USD)") {
            Text("Cocokkan sebagian nama model (mis. “opus-5”); aturan teratas yang cocok dipakai. Nilai bawaan adalah perkiraan dari daftar harga publik. Biaya yang tampil adalah setara harga API, bukan tagihan langganan atau router.")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text("Model").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(["Input", "Output", "C.read", "C.write"], id: \.self) { Text($0).frame(width: 58, alignment: .trailing) }
                Color.clear.frame(width: 20)
            }
            .font(.caption).foregroundStyle(.secondary)

            ForEach($pricing.rules) { $rule in
                HStack(spacing: 6) {
                    TextField("nama model", text: $rule.match).frame(maxWidth: .infinity)
                    priceField($rule.input)
                    priceField($rule.output)
                    priceField($rule.cacheRead)
                    priceField($rule.cacheWrite)
                    Button { pricing.rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).frame(width: 20)
                        .accessibilityLabel("Hapus aturan harga")
                }
            }

            let missing = store.unpricedModels
            if !missing.isEmpty {
                Text("Model tanpa harga: " + missing.joined(separator: ", ")).font(.caption).foregroundStyle(.orange)
                Menu("Tambah aturan untuk model ini…") {
                    ForEach(missing, id: \.self) { m in
                        Button(m) { pricing.rules.append(.init(match: m, input: 0, output: 0, cacheRead: 0, cacheWrite: 0)) }
                    }
                }
            }
            HStack {
                Button("Tambah aturan") { pricing.rules.append(.init(match: "", input: 0, output: 0, cacheRead: 0, cacheWrite: 0)) }
                Button("Kembalikan harga bawaan") { pricing.reset() }
            }
        }
    }

    private func priceField(_ value: Binding<Double>) -> some View {
        TextField("0", value: value, format: .number.precision(.fractionLength(0...3)))
            .multilineTextAlignment(.trailing)
            .frame(width: 58)
    }
}
