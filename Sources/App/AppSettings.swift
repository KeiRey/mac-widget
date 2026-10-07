import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    private static let menuBarKey = "showMenuBarIcon"
    private static let trackKey = "trackAppUsage"

    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: Self.menuBarKey) }
    }
    /// Pelacakan waktu pemakaian app untuk widget Penggunaan Aplikasi (lokal saja).
    @Published var trackUsage: Bool {
        didSet { UserDefaults.standard.set(trackUsage, forKey: Self.trackKey) }
    }
    @Published private(set) var launchAtLogin: Bool
    @Published var loginError: String?

    init() {
        showMenuBarIcon = UserDefaults.standard.object(forKey: Self.menuBarKey) as? Bool ?? true
        trackUsage = UserDefaults.standard.object(forKey: Self.trackKey) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// `SMAppService` bisa gagal pada app ad-hoc signed; kegagalan ditampilkan, bukan disembunyikan.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Gagal mengatur buka otomatis: \(error.localizedDescription)"
        }
        trackUsage = UserDefaults.standard.object(forKey: Self.trackKey) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
