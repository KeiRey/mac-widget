import AppKit
import SwiftUI
import Combine

/// State yang dibaca konten widget. Frame sengaja tidak di sini agar drag tidak memicu render ulang konten.
final class WidgetViewModel: ObservableObject {
    @Published var config: JSONValue
    @Published var opacity: Double
    @Published var active = true
    let definition: AnyWidgetDefinition
    /// Ada hanya untuk widget yang mendukung tooltip hover.
    let hover: HoverState?

    init(definition: AnyWidgetDefinition, config: JSONValue, opacity: Double) {
        self.definition = definition
        self.hover = definition.isHoverable ? HoverState() : nil
        self.config = config
        self.opacity = opacity
    }
}

struct WidgetRootView: View {
    @ObservedObject var model: WidgetViewModel

    var body: some View {
        GeometryReader { geo in
            model.definition.content(model.config, geo.size)
                .frame(width: geo.size.width, height: geo.size.height)
                .opacity(model.opacity)
                .environment(\.widgetActive, model.active)
                .environment(\.hoverState, model.hover)
                .coordinateSpace(name: WidgetSpace.name)
        }
    }
}

/// Jendela transparan tanpa border untuk satu instance widget.
final class WidgetPanel: NSPanel {
    let model: WidgetViewModel
    let overlay = EditOverlayView()
    var onUserFrameChange: (() -> Void)?
    var menuProvider: (() -> NSMenu)?
    private var tooltipWindow: TooltipWindow?
    private var tooltipObserver: AnyCancellable?
    var onFinishEditing: (() -> Void)?
    var onRestoreSize: (() -> Void)?
    var isFullScreen = false { didSet { overlay.needsDisplay = true } }
    var awake = true { didSet { refreshActive() } }
    /// Dipanggil saat status aktif (terlihat/tidak) berubah, supaya host bisa menghentikan polling hover.
    var onActiveChange: (() -> Void)?

    var minimumWidgetSize: CGSize { model.definition.minimumSize }

    init(model: WidgetViewModel) {
        self.model = model
        super.init(contentRect: CGRect(x: 0, y: 0, width: 300, height: 300),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let container = NSView()
        container.wantsLayer = true
        let hosting = NSHostingView(rootView: WidgetRootView(model: model))
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        overlay.frame = container.bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true
        container.addSubview(hosting)
        if let hover = model.hover {
            tooltipObserver = hover.$tooltip.receive(on: DispatchQueue.main).sink { [weak self] t in self?.showTooltip(t) }
        }
        container.addSubview(overlay)
        contentView = container

        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification, object: self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func showTooltip(_ content: TooltipContent?) {
        guard let content else { tooltipWindow?.hide(); return }
        if tooltipWindow == nil { tooltipWindow = TooltipWindow() }
        tooltipWindow?.show(content)
    }

    /// Posisi kursor dilaporkan oleh `WidgetHost` (polling), karena jendela level desktop tidak menerima event hover.
    func hoverMoved(to mouse: NSPoint) {
        guard let hover = model.hover else { return }
        let p = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)   // kiri-atas
        if hover.point != p { hover.point = p }
        tooltipWindow?.reposition()
    }

    func hoverExited() {
        guard let hover = model.hover, hover.point != nil || hover.tooltip != nil else { return }
        hover.point = nil; hover.tooltip = nil; hover.owner = nil
    }

    var isHovered: Bool { model.hover?.point != nil }

    @objc private func occlusionChanged() { refreshActive() }

    func refreshActive() {
        let visible = occlusionState.contains(.visible)
        let active = awake && visible
        if model.active != active {
            model.active = active
            onActiveChange?()
        }
    }
}

/// Lapisan mode edit: geser badan widget, tarik tepi/sudut untuk mengubah ukuran.
final class EditOverlayView: NSView {
    private struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1), right = Edges(rawValue: 2)
        static let bottom = Edges(rawValue: 4), top = Edges(rawValue: 8)
    }

    private let grip: CGFloat = 12
    private var edges: Edges = []
    private var startMouse = CGPoint.zero
    private var startFrame = CGRect.zero

    private var ignoreDrag = false
    private var panel: WidgetPanel? { window as? WidgetPanel }

    private struct PillButton { let title: String; let rect: CGRect; let action: () -> Void }

    /// Tombol di tengah atas widget, supaya mode edit selalu bisa diakhiri, termasuk saat Layar Penuh.
    private func pillButtons() -> [PillButton] {
        guard let panel, bounds.width >= 220, bounds.height >= 90 || panel.isFullScreen else { return [] }
        var specs: [(String, () -> Void)] = []
        if panel.isFullScreen { specs.append(("Kembalikan ukuran", { panel.onRestoreSize?() })) }
        specs.append(("Selesai mengedit", { panel.onFinishEditing?() }))

        let attrs = pillAttributes
        let widths = specs.map { ($0.0 as NSString).size(withAttributes: attrs).width + 28 }
        let total = widths.reduce(0, +) + CGFloat(specs.count - 1) * 8
        guard total <= bounds.width - 24 else { return [] }
        let top = panel.isFullScreen ? bounds.maxY - 70 : bounds.maxY - 38
        var x = bounds.midX - total / 2
        var out: [PillButton] = []
        for (i, spec) in specs.enumerated() {
            out.append(PillButton(title: spec.0, rect: CGRect(x: x, y: top, width: widths[i], height: 26), action: spec.1))
            x += widths[i] + 8
        }
        return out
    }

    private var pillAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 8, yRadius: 8)
        accent.withAlphaComponent(0.10).setFill()
        path.fill()
        accent.setStroke()
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()

        accent.setFill()
        let s: CGFloat = 10
        for x in [bounds.minX + 2, bounds.maxX - s - 2] {
            for y in [bounds.minY + 2, bounds.maxY - s - 2] {
                NSBezierPath(roundedRect: CGRect(x: x, y: y, width: s, height: s), xRadius: 2, yRadius: 2).fill()
            }
        }

        for b in pillButtons() {
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: b.rect, xRadius: 13, yRadius: 13).fill()
            (b.title as NSString).draw(at: CGPoint(x: b.rect.minX + 14, y: b.rect.minY + 5), withAttributes: pillAttributes)
        }

        let label = "\(Int(bounds.width)) × \(Int(bounds.height))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attrs)
        let pill = CGRect(x: bounds.midX - size.width / 2 - 6, y: bounds.minY + 6,
                          width: size.width + 12, height: size.height + 4)
        if pill.width < bounds.width - 40, pill.height < bounds.height - 40 {
            accent.setFill()
            NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
            label.draw(at: CGPoint(x: pill.minX + 6, y: pill.minY + 2), withAttributes: attrs)
        }
    }

    private func edges(at p: CGPoint) -> Edges {
        var e: Edges = []
        if p.x < grip { e.insert(.left) }
        if p.x > bounds.width - grip { e.insert(.right) }
        if p.y < grip { e.insert(.bottom) }
        if p.y > bounds.height - grip { e.insert(.top) }
        return e
    }

    private func cursor(for e: Edges) -> NSCursor {
        if e.isEmpty { return .openHand }
        let horizontal = e.contains(.left) || e.contains(.right)
        let vertical = e.contains(.top) || e.contains(.bottom)
        if horizontal && vertical { return .crosshair }
        return horizontal ? .resizeLeftRight : .resizeUpDown
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if pillButtons().contains(where: { $0.rect.contains(p) }) { NSCursor.pointingHand.set(); return }
        cursor(for: edges(at: convert(event.locationInWindow, from: nil))).set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let w = window else { return }
        let p = convert(event.locationInWindow, from: nil)
        if let b = pillButtons().first(where: { $0.rect.contains(p) }) {
            ignoreDrag = true
            b.action()
            return
        }
        ignoreDrag = false
        edges = edges(at: convert(event.locationInWindow, from: nil))
        startMouse = NSEvent.mouseLocation
        startFrame = w.frame
        if edges.isEmpty { NSCursor.closedHand.set() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !ignoreDrag, let panel else { return }
        let screenFrame = (panel.screen ?? DisplayManager.primary).frame
        let m = NSEvent.mouseLocation
        let dx = m.x - startMouse.x, dy = m.y - startMouse.y
        let minS = panel.minimumWidgetSize
        let maxS = screenFrame.size
        var f = startFrame

        if edges.isEmpty {
            f.origin.x += dx
            f.origin.y += dy
            f = snapped(f, to: screenFrame)
        } else {
            if edges.contains(.right) { f.size.width = (startFrame.width + dx).clamped(minS.width, maxS.width) }
            if edges.contains(.left) {
                f.size.width = (startFrame.width - dx).clamped(minS.width, maxS.width)
                f.origin.x = startFrame.maxX - f.size.width
            }
            if edges.contains(.top) { f.size.height = (startFrame.height + dy).clamped(minS.height, maxS.height) }
            if edges.contains(.bottom) {
                f.size.height = (startFrame.height - dy).clamped(minS.height, maxS.height)
                f.origin.y = startFrame.maxY - f.size.height
            }
        }
        panel.setFrame(f, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.arrow.set()
        if ignoreDrag { ignoreDrag = false; return }
        panel?.onUserFrameChange?()
    }

    override func menu(for event: NSEvent) -> NSMenu? { panel?.menuProvider?() }

    /// Tempel ke tepi dan tengah layar bila dekat (F-08).
    private func snapped(_ f: CGRect, to s: CGRect) -> CGRect {
        let t: CGFloat = 12
        var r = f
        func snap(_ value: CGFloat, _ targets: [CGFloat]) -> CGFloat? {
            targets.first { abs($0 - value) < t }
        }
        if let x = snap(r.minX, [s.minX]) { r.origin.x = x }
        else if let x = snap(r.maxX, [s.maxX]) { r.origin.x = x - r.width }
        else if let x = snap(r.midX, [s.midX]) { r.origin.x = x - r.width / 2 }
        if let y = snap(r.minY, [s.minY]) { r.origin.y = y }
        else if let y = snap(r.maxY, [s.maxY]) { r.origin.y = y - r.height }
        else if let y = snap(r.midY, [s.midY]) { r.origin.y = y - r.height / 2 }
        return r
    }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), Swift.max(lo, hi)) }
}
