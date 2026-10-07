import AppKit
import Combine

enum UsageMetric: String, Codable, CaseIterable, Identifiable {
    /// App yang sedang di depan dan dipakai.
    case active
    /// App yang sedang terbuka, walau di latar.
    case running

    var id: String { rawValue }
    var title: String { self == .active ? "Aktif di depan" : "Aplikasi berjalan" }
}

/// Detik pemakaian per jam (indeks 0...23) untuk satu app dalam satu hari.
struct AppDay: Codable {
    var a = [Double](repeating: 0, count: 24)
    var r = [Double](repeating: 0, count: 24)

    func hours(_ metric: UsageMetric) -> [Double] { metric == .active ? a : r }
}

struct UsageData: Codable {
    var version = 1
    /// "yyyy-MM-dd" -> bundleID -> pemakaian
    var days: [String: [String: AppDay]] = [:]
    var names: [String: String] = [:]
}

/// Riwayat pemakaian app, disimpan lokal di Application Support (usage.json).
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()
    private static let retentionDays = 400

    /// Bertambah tiap data berubah, supaya widget menggambar ulang.
    @Published private(set) var revision = 0
    private(set) var data: UsageData
    private let url: URL
    private var dirty = false

    private init() {
        url = AppPaths.dataDir.appendingPathComponent("usage.json")
        if let d = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(UsageData.self, from: d) {
            data = decoded
        } else {
            data = UsageData()
        }
    }

    // MARK: Kunci hari

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String { keyFormatter.string(from: date) }

    // MARK: Menulis

    /// Mencatat rentang waktu, dipecah per jam supaya jatuh ke slot yang benar.
    func record(bundle: String, name: String?, metric: UsageMetric, from: Date, to: Date) {
        guard to > from else { return }
        let cal = Calendar.current
        var t = from
        while t < to {
            let nextHour = cal.dateInterval(of: .hour, for: t)?.end ?? to
            let end = min(to, max(nextHour, t.addingTimeInterval(1)))
            let hour = cal.component(.hour, from: t)
            let key = Self.key(t)
            var day = data.days[key]?[bundle] ?? AppDay()
            if metric == .active { day.a[hour] += end.timeIntervalSince(t) } else { day.r[hour] += end.timeIntervalSince(t) }
            data.days[key, default: [:]][bundle] = day
            t = end
        }
        if let name, data.names[bundle] != name { data.names[bundle] = name }
        dirty = true
    }

    func touch() { revision &+= 1 }

    // MARK: Membaca

    func hourly(_ bundle: String, _ metric: UsageMetric, day: String) -> [Double] {
        data.days[day]?[bundle]?.hours(metric) ?? [Double](repeating: 0, count: 24)
    }

    func seconds(_ bundle: String, _ metric: UsageMetric, day: String) -> Double {
        data.days[day]?[bundle]?.hours(metric).reduce(0, +) ?? 0
    }

    /// Semua app yang pernah tercatat, diurutkan dari pemakaian aktif terbanyak.
    var knownApps: [(id: String, name: String)] {
        var totals: [String: Double] = [:]
        for (_, apps) in data.days { for (id, d) in apps { totals[id, default: 0] += d.a.reduce(0, +) } }
        return totals.keys.sorted { totals[$0, default: 0] > totals[$1, default: 0] }
            .map { ($0, data.names[$0] ?? $0) }
    }

    // MARK: Penyimpanan

    func saveIfNeeded() {
        guard dirty else { return }
        pruneOld()
        dirty = false
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        let url = self.url
        DispatchQueue.global(qos: .utility).async { try? encoded.write(to: url, options: .atomic) }
    }

    func clear() {
        data = UsageData()
        dirty = true
        saveIfNeeded()
        touch()
    }

    private func pruneOld() {
        guard data.days.count > Self.retentionDays else { return }
        for key in data.days.keys.sorted().dropLast(Self.retentionDays) { data.days[key] = nil }
    }
}

/// Pelacak berbasis event (tanpa polling cepat): mencatat app di depan dan app yang berjalan.
/// Hanya memakai `NSWorkspace`; tidak butuh izin Accessibility atau Screen Recording.
@MainActor
final class UsageTracker {
    static let shared = UsageTracker()

    /// Setelah selama ini tanpa input, waktu "aktif" berhenti dihitung.
    private let idleLimit: TimeInterval = 180
    private let store = UsageStore.shared
    private let ownBundle = Bundle.main.bundleIdentifier
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastTick = Date()
    private var awake = true
    private var front: NSRunningApplication?

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        lastTick = Date()
        awake = true
        front = NSWorkspace.shared.frontmostApplication

        let nc = NSWorkspace.shared.notificationCenter
        func watch(_ name: Notification.Name, _ handler: @escaping @MainActor (Notification) -> Void) {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { handler(note) }
            })
        }
        watch(NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            self?.accumulate()
            self?.front = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        }
        watch(NSWorkspace.didLaunchApplicationNotification) { [weak self] _ in self?.accumulate() }
        watch(NSWorkspace.didTerminateApplicationNotification) { [weak self] _ in self?.accumulate() }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            watch(name) { [weak self] _ in self?.accumulate(); self?.awake = false }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            watch(name) { [weak self] _ in self?.awake = true; self?.lastTick = Date() }
        }

        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.accumulate()
                self?.store.saveIfNeeded()
            }
        }
        t.tolerance = 10
        timer = t
    }

    func stop() {
        guard timer != nil else { return }
        accumulate()
        timer?.invalidate()
        timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        store.saveIfNeeded()
    }

    private func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Mencatat waktu sejak tick terakhir ke app yang sedang di depan dan app yang berjalan.
    private func accumulate() {
        let now = Date()
        defer { lastTick = now }
        guard awake else { return }
        let dt = now.timeIntervalSince(lastTick)
        // Selisih besar berarti mesin tidur tanpa notifikasi; jangan dihitung sebagai pemakaian.
        guard dt > 0, dt < 600 else { return }

        if let app = front, let id = app.bundleIdentifier, id != ownBundle {
            let idle = idleSeconds()
            let activeDt = idle > idleLimit ? max(0, dt - (idle - idleLimit)) : dt
            if activeDt > 0 {
                store.record(bundle: id, name: app.localizedName, metric: .active,
                             from: lastTick, to: lastTick.addingTimeInterval(activeDt))
            }
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != ownBundle else { continue }
            store.record(bundle: id, name: app.localizedName, metric: .running, from: lastTick, to: now)
        }
        store.touch()
    }
}
