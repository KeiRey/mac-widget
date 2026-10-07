import SwiftUI
import AppKit

enum HeatmapShape: String, Codable, CaseIterable, Identifiable {
    case square, rounded, circle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .square: return "Kotak"
        case .rounded: return "Sudut membulat"
        case .circle: return "Lingkaran"
        }
    }
}

/// Chart ala kontribusi GitHub yang dipakai bersama oleh widget Penggunaan Aplikasi dan Token AI.
/// Pemanggil hanya menyediakan nilai per hari dan per jam; susunan grid, label, dan legend diurus di sini.
struct HeatmapChart: View {
    /// Nilai khusus `weeks`: jumlah minggu mengikuti lebar.
    static let fitWidth = 100

    let box: CGSize
    /// 0 = hari ini per jam. N = N minggu. `fitWidth` = isi lebar.
    let weeks: Int
    let color: Color
    /// nil = otomatis dari nilai tertinggi yang terlihat.
    let goal: Double?
    /// Batas bawah target otomatis, supaya satu nilai kecil tidak langsung jadi paling terang.
    var minGoal: Double = 60
    let look: Look
    let shape: HeatmapShape
    let gap: Double
    let stepped: Bool
    let mondayFirst: Bool
    let showMonths: Bool
    let showWeekdays: Bool
    let showLegend: Bool
    let dayValue: (Date) -> Double
    let hourValues: () -> [Double]
    /// Dipanggil saat sel di-hover; mengembalikan isi tooltip.
    var tooltip: ((HeatHit) -> TooltipContent?)? = nil

    struct HeatHit {
        /// Tanggal sel (mode mingguan) atau hari ini (mode per jam).
        let date: Date
        /// Jam 0...23 pada mode per jam; nil pada mode mingguan.
        let hour: Int?
        let value: Double
        /// Nilai dibanding target (1 = kecerahan penuh).
        let fraction: Double
    }

    private struct Cell { let col: Int, row: Int, value: Double?; var date: Date? = nil }
    private struct Grid { let cols: Int, rows: Int, cells: [Cell] }
    /// Ruang untuk label bulan (atas), label hari (kiri), dan legend (bawah).
    private struct Margins { let fs: CGFloat, left: CGFloat, top: CGFloat, bottom: CGFloat }

    private func margins(weekly: Bool) -> Margins {
        let fs = min(11, max(6, box.height * 0.075))
        let roomy = box.height >= 70
        return Margins(
            fs: fs,
            left: weekly && roomy && showWeekdays ? fs * 2.6 : 0,
            top: weekly && roomy && showMonths ? fs * 1.7 : 0,
            bottom: box.height >= 90 && showLegend ? fs * 1.9 : 0)
    }

    var body: some View {
        let weekly = weeks != 0
        let m = margins(weekly: weekly)
        let grid = makeGrid(m)
        let values = grid.cells.compactMap { $0.value }
        let target = goal ?? max(minGoal, values.max() ?? 0)
        let empty = look.foreground.opacity(0.12)
        let calendar = Self.calendar(mondayFirst: mondayFirst)

        let pitch = max(1, min((box.width - m.left) / CGFloat(grid.cols), (box.height - m.top - m.bottom) / CGFloat(grid.rows)))
        let cell = max(1, pitch - pitch * gap)
        let labelColor = look.secondary
        let labelFont = look.font(m.fs, .regular)
        let shape = self.shape
        let stepped = self.stepped
        let color = self.color

        func path(_ rect: CGRect) -> Path {
            switch shape {
            case .square: return Path(rect)
            case .rounded: return Path(roundedRect: rect, cornerRadius: rect.width * 0.22)
            case .circle: return Path(ellipseIn: rect)
            }
        }

        let tooltip = self.tooltip
        let isHourly = !weekly
        let hit: (CGPoint) -> ProbeHit? = { p in
            guard let tooltip, p.x >= m.left, p.y >= m.top else { return nil }
            let col = Int(((p.x - m.left) / pitch).rounded(.down)), row = Int(((p.y - m.top) / pitch).rounded(.down))
            guard let c = grid.cells.first(where: { $0.col == col && $0.row == row }), let v = c.value else { return nil }
            let rect = CGRect(x: m.left + CGFloat(col) * pitch, y: m.top + CGFloat(row) * pitch, width: cell, height: cell)
            let h = HeatHit(date: c.date ?? Date(), hour: isHourly ? row * grid.cols + col : nil, value: v, fraction: v / target)
            return ProbeHit(tooltip: tooltip(h), rect: rect, corner: shape == .circle ? cell / 2 : (shape == .rounded ? cell * 0.22 : 0))
        }

        return Canvas { ctx, canvas in
            for c in grid.cells {
                guard let v = c.value else { continue }
                let rect = CGRect(x: m.left + CGFloat(c.col) * pitch, y: m.top + CGFloat(c.row) * pitch, width: cell, height: cell)
                ctx.fill(path(rect), with: .color(v <= 0 ? empty : color.opacity(Self.intensity(v / target, stepped: stepped))))
            }

            // Label bulan: muncul di kolom pertama tiap bulan baru.
            if m.top > 0 {
                var lastMonth = -1
                var lastCol = -10
                for c in grid.cells where c.row == 0 {
                    guard let day = c.date else { continue }
                    let month = calendar.component(.month, from: day)
                    defer { lastMonth = month }
                    guard month != lastMonth, c.col - lastCol >= 3 || lastCol < 0 else { continue }
                    let name = calendar.shortMonthSymbols[month - 1]
                    let x = m.left + CGFloat(c.col) * pitch
                    guard x + Self.textWidth(name, m.fs) <= canvas.width else { continue }
                    lastCol = c.col
                    ctx.draw(Text(name).font(labelFont).foregroundColor(labelColor),
                             at: CGPoint(x: x, y: 0), anchor: .topLeading)
                }
            }

            // Label hari: Sen/Rab/Jum bila minggu mulai Senin, selain itu baris ke-2, 4, 6.
            if m.left > 0 {
                for r in (mondayFirst ? [0, 2, 4] : [1, 3, 5]) {
                    let idx = (calendar.firstWeekday - 1 + r) % 7
                    ctx.draw(Text(calendar.shortWeekdaySymbols[idx]).font(labelFont).foregroundColor(labelColor),
                             at: CGPoint(x: 0, y: m.top + CGFloat(r) * pitch + cell / 2), anchor: .leading)
                }
            }

            // Legend: Kurang ■■■■■ Banyak, rata kanan.
            if m.bottom > 0 {
                let sq = m.fs * 0.9
                let levels = 5
                let y = canvas.height - m.bottom / 2
                var x = canvas.width
                ctx.draw(Text("Banyak").font(labelFont).foregroundColor(labelColor), at: CGPoint(x: x, y: y), anchor: .trailing)
                x -= Self.textWidth("Banyak", m.fs) + m.fs * 0.5
                for i in (0..<levels).reversed() {
                    let rect = CGRect(x: x - sq, y: y - sq / 2, width: sq, height: sq)
                    let fill: Color = i == 0 ? empty : color.opacity(Self.intensity(Double(i) / Double(levels - 1), stepped: stepped))
                    ctx.fill(path(rect), with: .color(fill))
                    x -= sq + m.fs * 0.25
                }
                x -= m.fs * 0.25
                ctx.draw(Text("Kurang").font(labelFont).foregroundColor(labelColor), at: CGPoint(x: x, y: y), anchor: .trailing)
            }
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
        .overlay { if tooltip != nil { HoverProbe(color: look.foreground, hit: hit) } }
    }

    // MARK: Grid

    private func makeGrid(_ m: Margins) -> Grid {
        if weeks == 0 { return hourGrid(CGSize(width: box.width, height: box.height - m.bottom)) }
        let weeks = self.weeks == Self.fitWidth
            ? max(4, min(53, Int((box.width - m.left) / max(1, (box.height - m.top - m.bottom) / 7))))
            : self.weeks

        let cal = Self.calendar(mondayFirst: mondayFirst)
        let now = Date()
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        let first = cal.date(byAdding: .day, value: -(weeks - 1) * 7, to: weekStart) ?? weekStart
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now

        var cells: [Cell] = []
        cells.reserveCapacity(weeks * 7)
        for col in 0..<weeks {
            for row in 0..<7 {
                guard let d = cal.date(byAdding: .day, value: col * 7 + row, to: first) else { continue }
                cells.append(Cell(col: col, row: row, value: d < endOfToday ? dayValue(d) : nil, date: d))
            }
        }
        return Grid(cols: weeks, rows: 7, cells: cells)
    }

    /// Hari ini per jam: 24 sel, disusun dalam kolom yang paling pas dengan ruang.
    private func hourGrid(_ area: CGSize) -> Grid {
        let hours = hourValues()
        let current = Calendar.current.component(.hour, from: Date())
        let cols = [1, 2, 3, 4, 6, 8, 12, 24].max { Self.pitch($0, area) < Self.pitch($1, area) } ?? 24
        let cells = (0..<24).map { i in
            Cell(col: i % cols, row: i / cols, value: i <= current ? hours[i] : nil)
        }
        return Grid(cols: cols, rows: 24 / cols, cells: cells)
    }

    private static func pitch(_ cols: Int, _ box: CGSize) -> CGFloat {
        min(box.width / CGFloat(cols), box.height / CGFloat(24 / cols))
    }

    // MARK: Pembantu

    static func textWidth(_ text: String, _ size: CGFloat) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width
    }

    static func calendar(mondayFirst: Bool) -> Calendar {
        var cal = Calendar.current
        cal.firstWeekday = mondayFirst ? 2 : 1
        return cal
    }

    /// 4 tingkat ala GitHub (atau halus); sel kosong ditangani terpisah.
    static func intensity(_ fraction: Double, stepped: Bool) -> Double {
        let f = min(1, max(0, fraction))
        if stepped {
            let level = max(0, min(3, Int((f * 4).rounded(.up)) - 1))
            return [0.30, 0.50, 0.75, 1.0][level]
        }
        return 0.25 + 0.75 * f
    }
}
