import AppKit
import ServiceManagement

// Dipakai uninstall.sh untuk mencabut item login sebelum .app dihapus.
if CommandLine.arguments.contains("--unregister-login") {
    try? SMAppService.mainApp.unregister()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
