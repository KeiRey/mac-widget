import SwiftUI

struct LineSeries: Identifiable {
    let id: String
    let color: Color
    /// nil = belum ada data (mis. jam yang belum terjadi): garis berhenti di sana.
    let values: [Double?]
}

/// Chart garis multi-seri dengan grid, label sumbu, area berwarna, dan kurva halus.
struct LineChart: View {
    let box: CGSize
    let series: [LineSeries]
    let xLabels: [String]
    let look: Look
    var smooth = true
    var fillArea = true
    var showPoints = false
    var showGrid = true
    var showAxes = true
    var format: (Double) -> String = { String(Int($0)) }
    /// Isi tooltip untuk indeks data yang di-hover.
    var tooltip: ((Int) -> TooltipContent?)? = nil

    var body: some View {
        let fs = min(11, max(6, box.height * 0.07))
        let n = xLabels.count
        let rawMax = series.flatMap { $0.values.compactMap { $0 } }.max() ?? 0
        let top = Self.niceMax(rawMax)
        let labelFont = look.font(fs, .regular)
        let labelColor = look.secondary

        let yLabels = [top, top / 2, 0].map(format)
        let left: CGFloat = showAxes && box.height >= 70 ? (yLabels.map { HeatmapChart.textWidth($0, fs) }.max() ?? 0) + fs * 0.6 : 0
        let bottom: CGFloat = showAxes && box.height >= 70 ? fs * 1.8 : 0
        let topPad = fs * 0.6
        let plot = CGRect(x: left, y: topPad, width: max(1, box.width - left - fs * 0.4),
                          height: max(1, box.height - bottom - topPad))

        func point(_ i: Int, _ v: Double) -> CGPoint {
            let x = n > 1 ? plot.minX + plot.width * CGFloat(i) / CGFloat(n - 1) : plot.midX
            return CGPoint(x: x, y: plot.maxY - plot.height * CGFloat(min(1, v / top)))
        }

        let tooltip = self.tooltip
        let all = series
        let hit: (CGPoint) -> ProbeHit? = { p in
            guard let tooltip, n > 0, p.x >= plot.minX - 6, p.x <= plot.maxX + 6, p.y <= plot.maxY + 6 else { return nil }
            let t = n > 1 ? (p.x - plot.minX) / plot.width : 0
            let i = max(0, min(n - 1, Int((t * CGFloat(n - 1)).rounded())))
            let dots = all.compactMap { s -> (point: CGPoint, color: Color)? in
                guard i < s.values.count, let v = s.values[i] else { return nil }
                return (point(i, v), s.color)
            }
            guard !dots.isEmpty else { return nil }
            return ProbeHit(tooltip: tooltip(i), guideX: point(i, 0).x, guideRange: plot.minY...plot.maxY, dots: dots)
        }

        return Canvas { ctx, _ in

            if showGrid || left > 0 {
                for (k, frac) in [1.0, 0.5, 0.0].enumerated() {
                    let y = plot.maxY - plot.height * CGFloat(frac)
                    if showGrid {
                        var line = Path()
                        line.move(to: CGPoint(x: plot.minX, y: y))
                        line.addLine(to: CGPoint(x: plot.maxX, y: y))
                        ctx.stroke(line, with: .color(look.foreground.opacity(frac == 0 ? 0.25 : 0.1)),
                                   style: StrokeStyle(lineWidth: 1, dash: frac == 0 ? [] : [3, 3]))
                    }
                    if left > 0 {
                        ctx.draw(Text(yLabels[k]).font(labelFont).foregroundColor(labelColor),
                                 at: CGPoint(x: left - fs * 0.4, y: y), anchor: .trailing)
                    }
                }
            }

            if bottom > 0, n > 0 {
                let maxLabels = max(2, Int(plot.width / (fs * 5.5)))
                let step = max(1, Int((Double(n) / Double(maxLabels)).rounded(.up)))
                // Dihitung dari kanan supaya tanggal terbaru selalu berlabel.
                var i = n - 1
                while i >= 0 {
                    let x = n > 1 ? plot.minX + plot.width * CGFloat(i) / CGFloat(n - 1) : plot.midX
                    let anchor: UnitPoint = i == 0 ? .topLeading : (i == n - 1 ? .topTrailing : .top)
                    ctx.draw(Text(xLabels[i]).font(labelFont).foregroundColor(labelColor),
                             at: CGPoint(x: x, y: plot.maxY + fs * 0.4), anchor: anchor)
                    i -= step
                }
            }

            for s in series {
                // Pecah menjadi segmen kontinu (nil memutus garis).
                var segments: [[CGPoint]] = [[]]
                for (i, v) in s.values.enumerated() {
                    if let v { segments[segments.count - 1].append(point(i, v)) }
                    else if !segments[segments.count - 1].isEmpty { segments.append([]) }
                }
                for pts in segments where !pts.isEmpty {
                    let path = Self.curve(pts, smooth: smooth, top: plot.minY, bottom: plot.maxY)
                    if fillArea, pts.count > 1 {
                        var area = path
                        area.addLine(to: CGPoint(x: pts.last!.x, y: plot.maxY))
                        area.addLine(to: CGPoint(x: pts.first!.x, y: plot.maxY))
                        area.closeSubpath()
                        ctx.fill(area, with: .linearGradient(
                            Gradient(colors: [s.color.opacity(0.35), s.color.opacity(0)]),
                            startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
                    }
                    ctx.stroke(path, with: .color(s.color),
                               style: StrokeStyle(lineWidth: max(1.5, min(3, box.height * 0.012)), lineCap: .round, lineJoin: .round))
                    if showPoints { for p in pts { Self.dot(&ctx, p, s.color, fs * 0.35) } }
                    else if let last = pts.last { Self.dot(&ctx, last, s.color, fs * 0.4) }
                }
            }
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
        .overlay { if tooltip != nil { HoverProbe(color: look.foreground, hit: hit) } }
    }

    private static func dot(_ ctx: inout GraphicsContext, _ p: CGPoint, _ color: Color, _ r: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    /// Kurva Catmull-Rom (kontrol Y dijepit agar tidak melewati batas plot) atau garis patah.
    private static func curve(_ p: [CGPoint], smooth: Bool, top: CGFloat, bottom: CGFloat) -> Path {
        var path = Path()
        guard let first = p.first else { return path }
        path.move(to: first)
        guard p.count > 1 else { return path }
        for i in 0..<(p.count - 1) {
            if !smooth { path.addLine(to: p[i + 1]); continue }
            let p0 = i > 0 ? p[i - 1] : p[i], p1 = p[i], p2 = p[i + 1], p3 = i + 2 < p.count ? p[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: min(bottom, max(top, p1.y + (p2.y - p0.y) / 6)))
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: min(bottom, max(top, p2.y - (p3.y - p1.y) / 6)))
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    /// Batas atas sumbu Y yang "bulat": 1, 2, 5 × 10^k.
    static func niceMax(_ v: Double) -> Double {
        guard v > 0 else { return 1 }
        let e = pow(10, floor(log10(v)))
        let f = v / e
        let step = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10].first { f <= $0 } ?? 10
        return step * e
    }
}
