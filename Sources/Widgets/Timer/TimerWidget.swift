import SwiftUI
import UserNotifications

enum TimerWidget: WidgetDefinition {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case countdown, stopwatch, pomodoro
        var id: String { rawValue }
        var title: String {
            switch self {
            case .countdown: return "Hitung mundur"
            case .stopwatch: return "Stopwatch"
            case .pomodoro: return "Pomodoro"
            }
        }
    }

    struct Config: Codable, Hashable {
        var mode: Mode = .pomodoro
        var countdownMinutes = 10
        var workMinutes = 25
        var breakMinutes = 5
        var theme = Look()
    }

    static let id = "timer"
    static let displayName = "Timer"
    static let symbol = "timer"
    static let minimumSize = CGSize(width: 120, height: 90)
    static let defaultSize = CGSize(width: 300, height: 220)
    static let isInteractive = true
    static let defaultConfig = Config()

    static func makeContent(config: Config, size: CGSize) -> some View {
        TimerView(config: config, size: size)
    }

    static func makeSettings(config: Binding<Config>) -> some View {
        TimerSettings(config: config)
    }
}

/// Status timer. Tanpa polling: akhir hitungan dijadwalkan sekali, tampilan di-tick oleh `TickView`.
@MainActor
final class TimerModel: ObservableObject {
    enum Phase { case work, rest }

    @Published private(set) var running = false
    @Published private(set) var finished = false
    @Published private(set) var phase = Phase.work
    private var accumulated: TimeInterval = 0
    private var startedAt: Date?
    private var endTask: Task<Void, Never>?

    func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggle(duration: TimeInterval?, onFinish: @escaping () -> Void) {
        if running {
            accumulated = elapsed()
            startedAt = nil
            running = false
            endTask?.cancel()
        } else {
            if finished { reset() }
            startedAt = Date()
            running = true
            scheduleEnd(duration: duration, onFinish: onFinish)
        }
    }

    func reset() {
        endTask?.cancel()
        accumulated = 0
        startedAt = nil
        running = false
        finished = false
    }

    func switchPhase() {
        phase = phase == .work ? .rest : .work
    }

    func complete() {
        endTask?.cancel()
        accumulated = 0
        startedAt = nil
        running = false
        finished = true
    }

    private func scheduleEnd(duration: TimeInterval?, onFinish: @escaping () -> Void) {
        guard let duration else { return }
        let remaining = max(0, duration - accumulated)
        endTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.complete()
            onFinish()
        }
    }
}

enum Notifier {
    static func notify(title: String, body: String) {
        NSSound(named: "Glass")?.play()
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

struct TimerView: View {
    let config: TimerWidget.Config
    let size: CGSize
    @StateObject private var model = TimerModel()

    private var duration: TimeInterval? {
        switch config.mode {
        case .stopwatch: return nil
        case .countdown: return TimeInterval(config.countdownMinutes * 60)
        case .pomodoro: return TimeInterval((model.phase == .work ? config.workMinutes : config.breakMinutes) * 60)
        }
    }

    var body: some View {
        let pad = min(size.width, size.height) * 0.06
        let icon = max(14, min(size.height * 0.14, 44))
        let showButtons = size.height >= 100
        let fs = max(10, min((size.height - pad * 2) * (showButtons ? 0.4 : 0.65), (size.width - pad * 2) / 2.6))

        VStack(spacing: icon * 0.35) {
            if config.mode == .pomodoro && size.height >= 140 {
                LText(text: model.phase == .work ? "Fokus" : "Istirahat", look: config.theme,
                      size: max(10, fs * 0.22), weight: .semibold)
                    .foregroundStyle(config.theme.accent)
            }
            TickView(interval: 1) { date in
                let text = format(displaySeconds(at: date))
                let w100 = config.theme.measure(text, 100, .semibold, monoDigits: true).width
                let fit = max(8, min(fs, (size.width - pad * 2) * 100 / max(1, w100)))
                LText(text: text, look: config.theme, size: fit, weight: .semibold, monoDigits: true)
            }
            if showButtons {
                HStack(spacing: icon * 0.7) {
                    Button(action: toggle) {
                        Image(systemName: model.running ? "pause.fill" : "play.fill").font(.system(size: icon))
                    }
                    .accessibilityLabel(model.running ? "Jeda" : "Mulai")
                    Button(action: model.reset) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: icon))
                    }
                    .accessibilityLabel("Reset")
                }
                .buttonStyle(.plain)
                .foregroundStyle(config.theme.foreground)
            }
        }
        .foregroundStyle(config.theme.foreground)
        .padding(pad)
        .frame(width: size.width, height: size.height)
        .themed(config.theme, size: size)
        .onChange(of: config) { _ in model.reset() }
    }

    private func displaySeconds(at date: Date) -> Int {
        let elapsed = model.elapsed(at: date)
        guard let duration else { return Int(elapsed) }
        return Int(max(0, duration - elapsed).rounded(.up))
    }

    private func format(_ total: Int) -> String {
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private func toggle() {
        let mode = config.mode
        let wasWork = model.phase == .work
        model.toggle(duration: duration) { handleFinish(mode: mode, wasWork: wasWork) }
    }

    private func handleFinish(mode: TimerWidget.Mode, wasWork: Bool) {
        if mode == .pomodoro {
            Notifier.notify(title: "Pomodoro", body: wasWork ? "Waktunya istirahat." : "Waktunya kembali fokus.")
            model.switchPhase()
            toggle()   // lanjut otomatis ke fase berikutnya
        } else {
            Notifier.notify(title: "Timer", body: "Waktu habis.")
        }
    }
}

struct TimerSettings: View {
    @Binding var config: TimerWidget.Config

    var body: some View {
        Picker("Mode", selection: $config.mode) {
            ForEach(TimerWidget.Mode.allCases) { Text($0.title).tag($0) }
        }
        LookSettings(look: $config.theme)
        switch config.mode {
        case .countdown:
            Stepper("Durasi: \(config.countdownMinutes) menit", value: $config.countdownMinutes, in: 1...600)
        case .pomodoro:
            Stepper("Fokus: \(config.workMinutes) menit", value: $config.workMinutes, in: 1...180)
            Stepper("Istirahat: \(config.breakMinutes) menit", value: $config.breakMinutes, in: 1...60)
        case .stopwatch:
            EmptyView()
        }
    }
}
