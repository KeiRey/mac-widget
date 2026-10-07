import SwiftUI

enum ClockWidget: WidgetDefinition {
    enum Style: String, Codable, CaseIterable, Identifiable {
        case digital, analog
        var id: String { rawValue }
        var title: String { self == .digital ? "Digital" : "Analog" }
    }

    struct Config: Codable, Hashable {
        var style: Style = .digital
        var use24Hour = true
        var showSeconds = true
        var showDate = true
        var timeZoneID = ""   // kosong = zona waktu sistem
        var theme = Look()

        var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    }

    static let id = "clock"
    static let displayName = "Jam"
    static let symbol = "clock"
    static let minimumSize = CGSize(width: 60, height: 40)
    static let defaultSize = CGSize(width: 320, height: 200)
    static let defaultConfig = Config()

    static func makeContent(config: Config, size: CGSize) -> some View {
        ClockView(config: config, size: size)
    }

    static func makeSettings(config: Binding<Config>) -> some View {
        ClockSettings(config: config)
    }
}

// MARK: - Waktu

struct ClockTime {
    let hour: Int, minute: Int, second: Int

    init(_ date: Date, _ tz: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        hour = c.hour ?? 0
        minute = c.minute ?? 0
        second = c.second ?? 0
    }
}

enum ClockFormat {
    private static var dateFormatters: [String: DateFormatter] = [:]

    /// Dipanggil dari main thread saja (render SwiftUI).
    static func dateLine(_ date: Date, tz: TimeZone) -> String {
        let f: DateFormatter
        if let cached = dateFormatters[tz.identifier] {
            f = cached
        } else {
            f = DateFormatter()
            f.timeZone = tz
            f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
            dateFormatters[tz.identifier] = f
        }
        return f.string(from: date)
    }

    static func cityName(_ tz: TimeZone) -> String {
        (tz.identifier.split(separator: "/").last.map(String.init) ?? tz.identifier)
            .replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - Tampilan

struct ClockView: View {
    let config: ClockWidget.Config
    let size: CGSize

    var body: some View {
        Group {
            if config.style == .analog { analog } else { digital }
        }
        .frame(width: size.width, height: size.height)
        .themed(config.theme, size: size)
    }

    // Digital

    private var digital: some View {
        TickView(interval: config.showSeconds ? 1 : 60) { date in
            let look = config.theme
            let t = ClockTime(date, config.timeZone)
            let showDate = config.showDate && size.height >= 90
            let main = mainText(t)
            let suffix = config.use24Hour ? "" : (t.hour < 12 ? "AM" : "PM")
            let pad = min(size.width, size.height) * 0.06
            let availW = size.width - pad * 2, availH = size.height - pad * 2

            // Ukuran font dihitung dari lebar teks sebenarnya agar pas di ruang yang ada.
            let mainW = look.measure(main, 100, .semibold, monoDigits: true).width
            let sufW = suffix.isEmpty ? 0 : look.measure(suffix, 28, .medium).width + 8
            let fs = max(8, min(availH * (showDate ? 0.55 : 0.8), availW * 100 / (mainW + sufW)))

            let dateText = dateLine(date)
            let dateW100 = look.measure(dateText, 100, .medium).width
            let ds = max(8, min(max(9, fs * 0.2), availW * 100 / max(1, dateW100)))

            VStack(spacing: fs * 0.04) {
                HStack(alignment: .lastTextBaseline, spacing: fs * 0.08) {
                    LText(text: main, look: look, size: fs, weight: .semibold, monoDigits: true)
                    if !suffix.isEmpty {
                        LText(text: suffix, look: look, size: fs * 0.28, weight: .medium)
                    }
                }
                if showDate {
                    LText(text: dateText, look: look, size: ds, weight: .medium)
                        .foregroundStyle(look.secondary)
                }
            }
            .foregroundStyle(look.foreground)
            .padding(pad)
            .frame(width: size.width, height: size.height)
        }
    }

    private func mainText(_ t: ClockTime) -> String {
        let h = config.use24Hour ? t.hour : (t.hour % 12 == 0 ? 12 : t.hour % 12)
        let hh = config.use24Hour ? String(format: "%02d", h) : String(h)
        var s = "\(hh):" + String(format: "%02d", t.minute)
        if config.showSeconds { s += ":" + String(format: "%02d", t.second) }
        return s
    }

    private func dateLine(_ date: Date) -> String {
        let base = ClockFormat.dateLine(date, tz: config.timeZone)
        return config.timeZoneID.isEmpty ? base : "\(ClockFormat.cityName(config.timeZone)) · \(base)"
    }

    // Analog

    private var analog: some View {
        TickView(interval: config.showSeconds ? 1 : 60) { date in
            let t = ClockTime(date, config.timeZone)
            if config.theme.isGlass, #available(macOS 26.0, *) {
                glassFace(t)
            } else {
                Canvas { ctx, canvasSize in
                    drawFace(&ctx, canvasSize, t)
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    /// Tick, angka, dan jarum menjadi satu bentuk Liquid Glass; jarum detik tetap solid berwarna aksen.
    @available(macOS 26.0, *)
    private func glassFace(_ t: ClockTime) -> some View {
        let look = config.theme
        let shape = AnalogGlassShape(look: look, time: t, showSeconds: config.showSeconds, size: size)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = max(1, min(size.width, size.height) / 2 - 2)
        return ZStack {
            Color.clear.glassEffect(look.glassStyle, in: shape)
            if config.showSeconds {
                Canvas { ctx, _ in
                    let a = Double(t.second) / 60 * 2 * .pi
                    var p = Path()
                    p.move(to: c)
                    p.addLine(to: CGPoint(x: c.x + CGFloat(sin(a)) * r * 0.85, y: c.y - CGFloat(cos(a)) * r * 0.85))
                    ctx.stroke(p, with: .color(look.accent), style: StrokeStyle(lineWidth: max(1, r * 0.015), lineCap: .round))
                    let dot = max(2, r * 0.04)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2)),
                             with: .color(look.accent))
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func drawFace(_ ctx: inout GraphicsContext, _ canvas: CGSize, _ t: ClockTime) {
        let theme = config.theme
        let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let r = max(1, min(canvas.width, canvas.height) / 2 - 2)

        if let bg = theme.background {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(bg))
        } else {
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(theme.foreground.opacity(0.35)), lineWidth: max(1, r * 0.015))
        }

        func point(_ angle: Double, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: c.x + CGFloat(sin(angle)) * radius, y: c.y - CGFloat(cos(angle)) * radius)
        }

        for i in 0..<60 {
            let major = i % 5 == 0
            let a = Double(i) / 60 * 2 * .pi
            var p = Path()
            p.move(to: point(a, r * 0.95))
            p.addLine(to: point(a, r * (major ? 0.84 : 0.9)))
            ctx.stroke(p, with: .color(theme.foreground.opacity(major ? 0.95 : 0.4)),
                       lineWidth: max(1, r * (major ? 0.025 : 0.01)))
        }

        if r > 70 {
            for n in 1...12 {
                let a = Double(n) / 12 * 2 * .pi
                let text = Text("\(n)").font(config.theme.font(r * 0.14, .medium))
                    .foregroundColor(theme.foreground)
                ctx.draw(text, at: point(a, r * 0.7))
            }
        }

        let sec = Double(t.second), min = Double(t.minute) + (config.showSeconds ? sec / 60 : 0)
        let hour = Double(t.hour % 12) + min / 60

        func hand(_ angle: Double, _ length: CGFloat, _ width: CGFloat, _ color: Color) {
            var p = Path()
            p.move(to: point(angle + .pi, length * 0.12))
            p.addLine(to: point(angle, length))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }

        hand(hour / 12 * 2 * .pi, r * 0.5, max(2, r * 0.045), theme.foreground)
        hand(min / 60 * 2 * .pi, r * 0.75, max(1.5, r * 0.03), theme.foreground)
        if config.showSeconds {
            hand(sec / 60 * 2 * .pi, r * 0.85, max(1, r * 0.015), theme.accent)
        }
        let dot = max(2, r * 0.04)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2)),
                 with: .color(config.showSeconds ? theme.accent : theme.foreground))
    }
}

/// Bentuk gabungan wajah jam analog untuk Liquid Glass.
struct AnalogGlassShape: Shape, @unchecked Sendable {
    let look: Look
    let time: ClockTime
    let showSeconds: Bool
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = max(1, min(size.width, size.height) / 2 - 2)
        let thick = 1 + CGFloat(look.liquid) * 0.8
        var out = Path()

        func point(_ a: Double, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: c.x + CGFloat(sin(a)) * radius, y: c.y - CGFloat(cos(a)) * radius)
        }
        func stroke(_ from: CGPoint, _ to: CGPoint, _ w: CGFloat) {
            var p = Path()
            p.move(to: from)
            p.addLine(to: to)
            out.addPath(p.strokedPath(StrokeStyle(lineWidth: w * thick, lineCap: .round)))
        }

        out.addPath(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            .strokedPath(StrokeStyle(lineWidth: max(1.5, r * 0.02) * thick)))

        for i in 0..<60 {
            let major = i % 5 == 0
            let a = Double(i) / 60 * 2 * .pi
            stroke(point(a, r * 0.94), point(a, r * (major ? 0.84 : 0.9)), r * (major ? 0.03 : 0.015))
        }
        if r > 70 {
            let font = look.nsFont(r * 0.15, .medium)
            for n in 1...12 {
                let a = Double(n) / 12 * 2 * .pi
                out.addPath(Path(TextOutline.path("\(n)", font, center: point(a, r * 0.68))))
            }
        }

        let sec = Double(time.second)
        let min = Double(time.minute) + (showSeconds ? sec / 60 : 0)
        let hour = Double(time.hour % 12) + min / 60
        stroke(c, point(hour / 12 * 2 * .pi, r * 0.5), r * 0.07)
        stroke(c, point(min / 60 * 2 * .pi, r * 0.75), r * 0.05)
        let dot = r * 0.06
        out.addEllipse(in: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2))
        return out
    }
}

struct ClockSettings: View {
    @Binding var config: ClockWidget.Config
    private static let zones = TimeZone.knownTimeZoneIdentifiers.sorted()

    var body: some View {
        Picker("Gaya", selection: $config.style) {
            ForEach(ClockWidget.Style.allCases) { Text($0.title).tag($0) }
        }
        LookSettings(look: $config.theme)
        Picker("Zona waktu", selection: $config.timeZoneID) {
            Text("Sistem").tag("")
            ForEach(Self.zones, id: \.self) { Text($0).tag($0) }
        }
        Toggle("Format 24 jam", isOn: $config.use24Hour)
        Toggle("Tampilkan detik", isOn: $config.showSeconds)
        Toggle("Tampilkan tanggal", isOn: $config.showDate)
    }
}
