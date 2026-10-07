import AppKit
import SwiftUI

enum SizePreset: String, CaseIterable, Identifiable {
    case small, medium, large, fullScreen
    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Kecil"
        case .medium: return "Sedang"
        case .large: return "Besar"
        case .fullScreen: return "Layar Penuh"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.6
        case .medium: return 1
        case .large: return 1.8
        case .fullScreen: return 1
        }
    }
}

/// Mengelola seluruh instance widget: model data, jendela, mode edit, dan penyimpanan.
@MainActor
final class WidgetHost: ObservableObject {
    @Published private(set) var instances: [WidgetInstance] = []
    @Published var editMode = false { didSet { applyAll() } }
    @Published var selectedID: UUID?

    /// Dipasang oleh AppDelegate; dipanggil saat widget meminta pengaturannya dibuka.
    var showManager: (() -> Void)?

    private let store = LayoutStore()
    private var layout: Layout
    private var panels: [UUID: WidgetPanel] = [:]
    private var saveWork: DispatchWorkItem?
    private var hoverTimer: Timer?
    private var hoverFast = false

    var isFirstLaunch: Bool { !layout.hasLaunched }

    init() {
        layout = store.load()
        instances = layout.widgets
    }

    // MARK: Siklus hidup

    func start() {
        for inst in instances { ensurePanel(for: inst) }
        applyAll()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.applyAll() } }

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setAwake(false) }
            }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setAwake(true) }
            }
        }
    }

    func completeFirstLaunch() {
        layout.hasLaunched = true
        saveNow()
    }

    private func setAwake(_ awake: Bool) {
        panels.values.forEach { $0.awake = awake }
    }

    // MARK: Akses

    func instance(_ id: UUID) -> WidgetInstance? { instances.first { $0.id == id } }
    var selected: WidgetInstance? { selectedID.flatMap(instance) }

    // MARK: Operasi (F-01, F-02, F-05)

    @discardableResult
    func add(type: String) -> UUID? {
        guard let def = WidgetRegistry.definition(for: type) else { return nil }
        let screen = DisplayManager.primary
        let size = def.defaultSize
        let rect = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                          width: size.width, height: size.height)
        let inst = WidgetInstance(type: type,
                                  frame: DisplayManager.relative(rect, on: screen),
                                  config: def.defaultConfig)
        instances.append(inst)
        ensurePanel(for: inst)
        selectedID = inst.id
        editMode = true   // juga memanggil applyAll
        persist()
        return inst.id
    }

    func remove(_ id: UUID) {
        panels[id]?.orderOut(nil)
        panels[id]?.close()
        panels[id] = nil
        instances.removeAll { $0.id == id }
        if selectedID == id { selectedID = instances.first?.id }
        persist()
    }

    func update(_ id: UUID, _ mutate: (inout WidgetInstance) -> Void) {
        guard let i = instances.firstIndex(where: { $0.id == id }) else { return }
        mutate(&instances[i])
        if let panel = panels[id] {
            panel.model.config = instances[i].config
            panel.model.opacity = instances[i].opacity
        }
        apply(instances[i])
        persist()
    }

    func applyPreset(_ id: UUID, _ preset: SizePreset) {
        guard let inst = instance(id), let def = WidgetRegistry.definition(for: inst.type) else { return }
        if preset == .fullScreen {
            update(id) {
                if !$0.fullScreen { $0.restoreFrame = $0.frame }
                $0.fullScreen = true
            }
            return
        }
        let screen = DisplayManager.screen(for: inst.display)
        let current = inst.fullScreen ? (inst.restoreFrame?.rect ?? CGRect(origin: .zero, size: def.defaultSize))
                                      : inst.frame.rect
        var size = CGSize(width: def.defaultSize.width * preset.scale, height: def.defaultSize.height * preset.scale)
        size.width = size.width.clamped(def.minimumSize.width, screen.frame.width)
        size.height = size.height.clamped(def.minimumSize.height, screen.frame.height)
        let rect = CGRect(x: current.midX - size.width / 2, y: current.midY - size.height / 2,
                          width: size.width, height: size.height)
        update(id) {
            $0.fullScreen = false
            $0.restoreFrame = nil
            $0.frame = FrameRect(rect)
        }
    }

    func toggleFullScreen(_ id: UUID) {
        guard let inst = instance(id) else { return }
        if inst.fullScreen {
            update(id) {
                if let r = $0.restoreFrame { $0.frame = r }
                $0.fullScreen = false
                $0.restoreFrame = nil
            }
        } else {
            applyPreset(id, .fullScreen)
        }
    }

    /// Dipanggil setelah pengguna selesai menggeser/mengubah ukuran di mode edit.
    private func userChangedFrame(_ id: UUID) {
        guard let panel = panels[id], let i = instances.firstIndex(where: { $0.id == id }) else { return }
        let rect = panel.frame
        let screen = DisplayManager.screen(containing: rect) ?? DisplayManager.screen(for: instances[i].display)
        instances[i].display = DisplayManager.id(for: screen) == DisplayManager.id(for: DisplayManager.primary)
            ? DisplayManager.mainID : DisplayManager.id(for: screen)
        if instances[i].fullScreen, rect != screen.frame {
            instances[i].fullScreen = false
            instances[i].restoreFrame = nil
        }
        instances[i].frame = DisplayManager.relative(rect, on: screen)
        persist()
    }

    // MARK: Jendela

    private func ensurePanel(for inst: WidgetInstance) {
        guard panels[inst.id] == nil, let def = WidgetRegistry.definition(for: inst.type) else { return }
        let model = WidgetViewModel(definition: def, config: inst.config, opacity: inst.opacity)
        let panel = WidgetPanel(model: model)
        let id = inst.id
        panel.onUserFrameChange = { [weak self] in self?.userChangedFrame(id) }
        panel.onActiveChange = { [weak self] in self?.updateHoverPolling() }
        panel.onFinishEditing = { [weak self] in self?.editMode = false }
        panel.onRestoreSize = { [weak self] in self?.toggleFullScreen(id) }
        panel.menuProvider = { [weak self] in self?.makeMenu(for: id) ?? NSMenu() }
        panels[id] = panel
    }

    private func applyAll() {
        for inst in instances { apply(inst) }
        updateHoverPolling()
    }

    // MARK: Hover (polling)

    /// Jendela level desktop tidak menerima event hover/klik (Finder mengambilnya), jadi posisi kursor dibaca berkala.
    /// Timer hanya hidup bila ada widget hover yang terlihat dan tidak sedang diedit: lambat saat kursor di luar, rapat saat di atas widget.
    private func updateHoverPolling() {
        let needed = !editMode && panels.values.contains { $0.model.hover != nil && $0.model.active && $0.isVisible }
        guard needed else {
            hoverTimer?.invalidate(); hoverTimer = nil
            panels.values.forEach { $0.hoverExited() }
            return
        }
        guard hoverTimer == nil else { return }
        scheduleHoverTimer(fast: false)
    }

    private func scheduleHoverTimer(fast: Bool) {
        hoverTimer?.invalidate()
        hoverFast = fast
        let t = Timer.scheduledTimer(withTimeInterval: fast ? 1.0 / 30 : 1.0 / 6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hoverTick() }
        }
        t.tolerance = fast ? 0.01 : 0.05
        hoverTimer = t
    }

    private func hoverTick() {
        let mouse = NSEvent.mouseLocation
        var over = false
        for panel in panels.values where panel.model.hover != nil {
            // Hanya bila widget ini benar-benar jendela paling atas di titik kursor (tidak tertutup jendela app lain).
            let hit = panel.model.active && panel.isVisible && panel.frame.contains(mouse)
                && NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0) == panel.windowNumber
            if hit { panel.hoverMoved(to: mouse); over = true } else { panel.hoverExited() }
        }
        if over != hoverFast { scheduleHoverTimer(fast: over) }
    }

    private func apply(_ inst: WidgetInstance) {
        guard let panel = panels[inst.id], let def = WidgetRegistry.definition(for: inst.type) else { return }
        guard inst.visible else {
            panel.orderOut(nil)
            return
        }

        let screen = DisplayManager.screen(for: inst.display)
        var rect = inst.fullScreen ? screen.frame : DisplayManager.absolute(inst.frame, on: screen)
        rect.size.width = rect.width.clamped(def.minimumSize.width, screen.frame.width)
        rect.size.height = rect.height.clamped(def.minimumSize.height, screen.frame.height)
        if !screen.frame.intersects(rect) {
            rect.origin = CGPoint(x: screen.frame.midX - rect.width / 2, y: screen.frame.midY - rect.height / 2)
        }
        if panel.frame != rect { panel.setFrame(rect, display: true) }

        panel.level = level(for: inst, def: def)
        panel.ignoresMouseEvents = !editMode && !(def.isInteractive || def.isHoverable)
        if editMode { panel.hoverExited() }
        panel.overlay.isHidden = !editMode
        panel.isFullScreen = inst.fullScreen
        panel.orderFrontRegardless()
        panel.refreshActive()
    }

    /// Mode edit: melayang agar bisa dipegang. Terkunci: level desktop (F-09).
    private func level(for inst: WidgetInstance, def: AnyWidgetDefinition) -> NSWindow.Level {
        if editMode { return inst.fullScreen ? .normal : .floating }
        // Jendela Finder (ikon desktop) menutupi seluruh layar tepat di atas level desktop dan memakan semua event mouse.
        // Widget yang perlu klik atau hover harus berada di atasnya.
        let needsMouse = def.isInteractive || def.isHoverable
        let key: CGWindowLevelKey = (inst.aboveIcons || needsMouse) ? .desktopIconWindow : .desktopWindow
        return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(key)) + 1)
    }

    // MARK: Menu klik kanan (mode edit)

    private func makeMenu(for id: UUID) -> NSMenu {
        let menu = NSMenu()
        for preset in SizePreset.allCases where preset != .fullScreen {
            menu.addItem(ClosureMenuItem("Ukuran \(preset.title)") { [weak self] in self?.applyPreset(id, preset) })
        }
        let fs = instance(id)?.fullScreen == true
        menu.addItem(ClosureMenuItem(fs ? "Kembalikan ukuran" : "Layar Penuh") { [weak self] in
            self?.toggleFullScreen(id)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Pengaturan…") { [weak self] in
            self?.selectedID = id
            self?.showManager?()
        })
        menu.addItem(ClosureMenuItem("Hapus widget") { [weak self] in self?.remove(id) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Selesai mengedit") { [weak self] in self?.editMode = false })
        return menu
    }

    // MARK: Penyimpanan

    private func persist() {
        layout.widgets = instances
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        layout.widgets = instances
        store.save(layout)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) tidak dipakai") }

    @objc private func fire() { handler() }
}
