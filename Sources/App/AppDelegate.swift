import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let host = WidgetHost()
    let settings = AppSettings()
    private var managerWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    /// Quit biasa (Dock, ⌘Q) hanya menutup ke latar. Hanya "Keluar sepenuhnya" atau shutdown yang mematikan proses.
    private var reallyQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        host.showManager = { [weak self] in self?.showManager() }
        host.start()

        if host.isFirstLaunch {
            // UX 12.1: satu Jam langsung muncul, mode edit aktif, Widget Manager terbuka.
            host.add(type: ClockWidget.id)
            host.completeFirstLaunch()
            showManager()
        }

        settings.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &cancellables)

        // Shutdown, restart, dan logout harus tetap bisa menutup app.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.reallyQuit = true } }

        settings.$trackUsage
            .receive(on: RunLoop.main)
            .sink { enabled in
                if enabled { UsageTracker.shared.start() } else { UsageTracker.shared.stop() }
            }
            .store(in: &cancellables)

        host.$editMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildStatusMenu() }
            .store(in: &cancellables)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManager()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if reallyQuit { return .terminateNow }
        sendToBackground()
        return .terminateCancel
    }

    /// Menyembunyikan ikon Dock dan Widget Manager; widget, menu bar, dan pelacak tetap berjalan.
    private func sendToBackground() {
        managerWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        refreshStatusItem()
    }

    private func quitCompletely() {
        reallyQuit = true
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        UsageTracker.shared.stop()
        host.saveNow()
    }

    // MARK: Widget Manager

    func showManager() {
        if managerWindow == nil {
            let view = ManagerView(host: host, settings: settings)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "DeskWidgets"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("ManagerWindow")
            window.center()
            managerWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        refreshStatusItem()
        NSApp.activate(ignoringOtherApps: true)
        managerWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menu bar (F-23)

    /// Saat berjalan di latar tanpa ikon Dock, ikon menu bar wajib ada agar app bisa dibuka lagi.
    private func refreshStatusItem() {
        let visible = settings.showMenuBarIcon || NSApp.activationPolicy() == .accessory
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "DeskWidgets")
            statusItem = item
            rebuildStatusMenu()
        } else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func rebuildStatusMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Buka Widget Manager") { [weak self] in self?.showManager() })
        menu.addItem(ClosureMenuItem(host.editMode ? "Selesai mengedit (kunci)" : "Mode edit") { [weak self] in
            guard let self else { return }
            self.host.editMode.toggle()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Keluar sepenuhnya") { [weak self] in self?.quitCompletely() })
        item.menu = menu
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(ClosureMenuItem("Widget Manager") { [weak self] in self?.showManager() })
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Sembunyikan DeskWidgets", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Tutup (tetap berjalan di latar)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let full = ClosureMenuItem("Keluar sepenuhnya") { [weak self] in self?.quitCompletely() }
        full.keyEquivalent = "q"
        full.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(full)
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Salin", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Tempel", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Pilih Semua", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}
