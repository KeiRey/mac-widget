import SwiftUI

enum DateCalendarWidget: WidgetDefinition {
    struct Config: Codable, Hashable {
        var showCalendar = true
        var mondayFirst = true
        var theme = Look()
    }

    static let id = "date-calendar"
    static let displayName = "Tanggal & Kalender"
    static let symbol = "calendar"
    static let minimumSize = CGSize(width: 80, height: 60)
    static let defaultSize = CGSize(width: 420, height: 300)
    static let defaultConfig = Config()

    static func makeContent(config: Config, size: CGSize) -> some View {
        DateCalendarView(config: config, size: size)
    }

    static func makeSettings(config: Binding<Config>) -> some View {
        DateCalendarSettings(config: config)
    }
}

struct DateCalendarView: View {
    let config: DateCalendarWidget.Config
    let size: CGSize

    var body: some View {
        TickView(interval: 60) { now in
            content(now)
        }
        .frame(width: size.width, height: size.height)
        .themed(config.theme, size: size)
    }

    @ViewBuilder
    private func content(_ now: Date) -> some View {
        let pad = min(size.width, size.height) * 0.06
        let inner = CGSize(width: size.width - pad * 2, height: size.height - pad * 2)
        let showGrid = config.showCalendar && min(inner.width, inner.height) >= 150
        let wide = inner.width > inner.height * 1.25

        Group {
            if showGrid && wide {
                HStack(spacing: pad) {
                    header(now, CGSize(width: inner.width * 0.4, height: inner.height))
                    grid(now, CGSize(width: inner.width * 0.6 - pad, height: inner.height))
                }
            } else if showGrid {
                VStack(spacing: pad) {
                    header(now, CGSize(width: inner.width, height: inner.height * 0.34))
                    grid(now, CGSize(width: inner.width, height: inner.height * 0.66 - pad))
                }
            } else {
                header(now, inner)
            }
        }
        .foregroundStyle(config.theme.foreground)
        .padding(pad)
    }

    private func header(_ now: Date, _ area: CGSize) -> some View {
        let look = config.theme
        let cal = Calendar.current
        let day = "\(cal.component(.day, from: now))"
        let weekday = now.formatted(.dateTime.weekday(.wide))
        let month = now.formatted(.dateTime.month(.wide).year())
        let fs = max(10, min(area.height * 0.5, area.width * 0.45))
        // Batasi agar teks terpanjang tidak keluar dari area.
        let fit: (String, CGFloat, Font.Weight) -> CGFloat = { text, size, weight in
            min(size, area.width * 0.95 * size / max(1, look.measure(text, size, weight).width))
        }
        return VStack(spacing: fs * 0.04) {
            LText(text: weekday, look: look, size: fit(weekday, fs * 0.3, .medium), weight: .medium)
                .foregroundStyle(look.accent)
            LText(text: day, look: look, size: fs, weight: .bold, monoDigits: true)
            LText(text: month, look: look, size: fit(month, fs * 0.28, .medium), weight: .medium)
                .foregroundStyle(look.secondary)
        }
        .frame(width: area.width, height: area.height)
    }

    private func grid(_ now: Date, _ area: CGSize) -> some View {
        var cal = Calendar.current
        cal.firstWeekday = config.mondayFirst ? 2 : 1
        let today = cal.component(.day, from: now)
        let first = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let ordered = (0..<7).map { symbols[(cal.firstWeekday - 1 + $0) % 7] }

        let cw = area.width / 7, ch = area.height / 7
        let fs = max(6, min(cw, ch) * 0.5)

        if config.theme.isGlass, #available(macOS 26.0, *) {
            return AnyView(glassGrid(area: area, cw: cw, ch: ch, fs: fs, ordered: ordered,
                                     lead: lead, days: days, today: today))
        }

        return AnyView(VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(ordered[i]).frame(width: cw, height: ch)
                }
            }
            .font(config.theme.font(fs * 0.85, .semibold))
            .foregroundStyle(config.theme.secondary)

            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let day = row * 7 + col - lead + 1
                        ZStack {
                            if day == today {
                                Circle().fill(config.theme.accent).frame(width: min(cw, ch) * 0.9, height: min(cw, ch) * 0.9)
                            }
                            if day >= 1 && day <= days {
                                Text("\(day)")
                                    .font(config.theme.font(fs, day == today ? .bold : .regular).monospacedDigit())
                                    .foregroundStyle(day == today ? Color.white : config.theme.foreground)
                            }
                        }
                        .frame(width: cw, height: ch)
                    }
                }
            }
        }
        .frame(width: area.width, height: area.height))
    }

    /// Seluruh angka kalender menjadi satu bentuk Liquid Glass; tanggal hari ini tetap solid di lingkaran aksen.
    @available(macOS 26.0, *)
    private func glassGrid(area: CGSize, cw: CGFloat, ch: CGFloat, fs: CGFloat, ordered: [String],
                           lead: Int, days: Int, today: Int) -> some View {
        let look = config.theme
        let headFont = look.nsFont(fs * 0.85, .semibold)
        let dayFont = look.nsFont(fs, .regular, monoDigits: true)
        var runs: [GlyphRunsShape.Run] = []
        for i in 0..<7 {
            runs.append(.init(text: ordered[i], font: headFont, center: CGPoint(x: (CGFloat(i) + 0.5) * cw, y: ch / 2)))
        }
        var todayCenter: CGPoint?
        for row in 0..<6 {
            for col in 0..<7 {
                let day = row * 7 + col - lead + 1
                guard day >= 1 && day <= days else { continue }
                let center = CGPoint(x: (CGFloat(col) + 0.5) * cw, y: (CGFloat(row) + 1.5) * ch)
                if day == today { todayCenter = center; continue }
                runs.append(.init(text: "\(day)", font: dayFont, center: center))
            }
        }
        let shape = GlyphRunsShape(runs: runs, outset: CGFloat(look.liquid) * fs * 0.04)
        return ZStack {
            if let c = todayCenter {
                Circle().fill(look.accent).frame(width: min(cw, ch) * 0.9, height: min(cw, ch) * 0.9)
                    .position(c)
                Text("\(today)").font(look.font(fs, .bold).monospacedDigit()).foregroundStyle(.white).position(c)
            }
            Color.clear.glassEffect(look.glassStyle, in: shape)
        }
        .frame(width: area.width, height: area.height)
    }
}

struct DateCalendarSettings: View {
    @Binding var config: DateCalendarWidget.Config

    var body: some View {
        LookSettings(look: $config.theme)
        Toggle("Tampilkan kalender bulanan", isOn: $config.showCalendar)
        Toggle("Minggu dimulai hari Senin", isOn: $config.mondayFirst)
    }
}
