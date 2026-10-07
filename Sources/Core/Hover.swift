import SwiftUI
import AppKit
import Combine

/// Nama ruang koordinat akar widget; semua koordinat hover dinyatakan di ruang ini (kiri-atas = 0,0).
enum WidgetSpace { static let name = "widgetRoot" }

struct TooltipContent: Equatable {
    struct Row: Equatable {
        var label: String
        var value: String
        var emphasized = false
        var dim = false
    }
    struct Section: Equatable {
        var heading: String? = nil
        var color: RGB? = nil
        var rows: [Row]
    }

    var title: String
    var subtitle: String? = nil
    var sections: [Section]
    var footnote: String? = nil
}

/// Posisi mouse di dalam widget dan tooltip yang sedang aktif. Satu per jendela widget.
final class HoverState: ObservableObject {
    @Published var point: CGPoint?
    @Published var tooltip: TooltipContent?
    /// Probe yang memiliki tooltip saat ini, supaya beberapa chart dalam satu widget tidak saling menimpa.
    var owner: UUID?
}

private struct HoverStateKey: EnvironmentKey { static let defaultValue: HoverState? = nil }

extension EnvironmentValues {
    var hoverState: HoverState? {
        get { self[HoverStateKey.self] }
        set { self[HoverStateKey.self] = newValue }
    }
}

/// Hasil hit-test chart: isi tooltip dan penanda visual (sel yang disorot, garis vertikal, titik).
struct ProbeHit {
    var tooltip: TooltipContent?
    var rect: CGRect?
    var corner: CGFloat = 2
    var guideX: CGFloat?
    var guideRange: ClosedRange<CGFloat> = 0...0
    var dots: [(point: CGPoint, color: Color)] = []
}

/// Lapisan transparan di atas chart: menerjemahkan posisi mouse ke koordinat lokal chart,
/// meminta hit-test, lalu mengisi tooltip dan menggambar sorotan.
struct HoverProbe: View {
    let color: Color
    let hit: (CGPoint) -> ProbeHit?
    @Environment(\.hoverState) private var state

    var body: some View {
        if let state { Inner(state: state, color: color, hit: hit) }
    }

    private struct Inner: View {
        @ObservedObject var state: HoverState
        let color: Color
        let hit: (CGPoint) -> ProbeHit?
        @State private var id = UUID()
        @State private var current: ProbeHit?

        var body: some View {
            GeometryReader { g in
                let origin = g.frame(in: .named(WidgetSpace.name)).origin
                ZStack(alignment: .topLeading) {
                    if let h = current {
                        if let x = h.guideX {
                            Path { p in
                                p.move(to: CGPoint(x: x, y: h.guideRange.lowerBound))
                                p.addLine(to: CGPoint(x: x, y: h.guideRange.upperBound))
                            }
                            .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                        ForEach(Array(h.dots.enumerated()), id: \.offset) { _, d in
                            Circle().fill(d.color).overlay(Circle().stroke(color, lineWidth: 1.5))
                                .frame(width: 8, height: 8).position(d.point)
                        }
                        if let r = h.rect {
                            RoundedRectangle(cornerRadius: h.corner)
                                .stroke(color, lineWidth: 1.5)
                                .frame(width: r.width + 2, height: r.height + 2)
                                .position(x: r.midX, y: r.midY)
                        }
                    }
                }
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
                .onChange(of: state.point) { p in update(p, origin: origin, size: g.size) }
            }
            .allowsHitTesting(false)
        }

        private func update(_ p: CGPoint?, origin: CGPoint, size: CGSize) {
            if let p {
                let local = CGPoint(x: p.x - origin.x, y: p.y - origin.y)
                if local.x >= 0, local.y >= 0, local.x <= size.width, local.y <= size.height, let h = hit(local) {
                    current = h
                    state.owner = id
                    state.tooltip = h.tooltip
                    return
                }
            }
            current = nil
            if state.owner == id {
                state.owner = nil
                state.tooltip = nil
            }
        }
    }
}

// MARK: - Tampilan tooltip

struct TooltipView: View {
    let content: TooltipContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(content.title).font(.system(size: 12, weight: .semibold))
                if let sub = content.subtitle {
                    Text(sub).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                }
            }
            ForEach(Array(content.sections.enumerated()), id: \.offset) { _, section in
                Divider().overlay(Color.white.opacity(0.15))
                VStack(alignment: .leading, spacing: 3) {
                    if let heading = section.heading {
                        HStack(spacing: 5) {
                            if let c = section.color { Circle().fill(c.color).frame(width: 7, height: 7) }
                            Text(heading).font(.system(size: 11, weight: .semibold))
                        }
                    }
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 18) {
                            Text(row.label).foregroundStyle(.white.opacity(row.dim ? 0.4 : 0.65))
                            Spacer(minLength: 0)
                            Text(row.value)
                                .fontWeight(row.emphasized ? .semibold : .regular)
                                .foregroundStyle(.white.opacity(row.dim ? 0.5 : 1))
                        }
                        .font(.system(size: 11).monospacedDigit())
                    }
                }
            }
            if let note = content.footnote {
                Text(note).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(minWidth: 190, maxWidth: 320, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(white: 0.09).opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

/// Jendela kecil terpisah supaya tooltip tidak terpotong oleh batas widget dan tampil di atas semua jendela.
final class TooltipWindow: NSPanel {
    private let hosting = NSHostingView(rootView: AnyView(EmptyView()))

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }

    func show(_ content: TooltipContent) {
        hosting.rootView = AnyView(TooltipView(content: content).fixedSize())
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        size.width = ceil(size.width); size.height = ceil(size.height)
        hosting.frame = CGRect(origin: .zero, size: size)
        setContentSize(size)
        reposition()
        orderFrontRegardless()
    }

    /// Di kanan-bawah kursor; berpindah sisi bila tidak muat di layar.
    func reposition() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let size = frame.size
        var x = mouse.x + 16, y = mouse.y - size.height - 16
        if x + size.width > area.maxX { x = mouse.x - size.width - 16 }
        if y < area.minY { y = mouse.y + 16 }
        x = min(max(x, area.minX), area.maxX - size.width)
        y = min(max(y, area.minY), area.maxY - size.height)
        setFrameOrigin(CGPoint(x: x, y: y))
    }

    func hide() { orderOut(nil) }
}
