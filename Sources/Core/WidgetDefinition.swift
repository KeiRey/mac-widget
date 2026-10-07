import SwiftUI

/// Kontrak widget. Menambah widget baru = membuat tipe yang memenuhi protokol ini
/// lalu mendaftarkannya di `WidgetRegistry`. Engine tidak perlu diubah.
protocol WidgetDefinition {
    associatedtype Config: Codable & Hashable
    associatedtype Content: View
    associatedtype SettingsView: View

    static var id: String { get }
    static var displayName: String { get }
    static var symbol: String { get }
    static var minimumSize: CGSize { get }
    static var defaultSize: CGSize { get }
    /// Widget interaktif tetap menerima klik saat terkunci.
    static var isInteractive: Bool { get }
    /// Widget yang menampilkan tooltip saat di-hover. Perlu menerima mouse, jadi tidak klik-tembus saat terkunci.
    static var isHoverable: Bool { get }
    static var defaultConfig: Config { get }

    @ViewBuilder static func makeContent(config: Config, size: CGSize) -> Content
    @ViewBuilder static func makeSettings(config: Binding<Config>) -> SettingsView
}

extension WidgetDefinition {
    static var symbol: String { "square.dashed" }
    static var defaultSize: CGSize { CGSize(width: 320, height: 320) }
    static var isInteractive: Bool { false }
    static var isHoverable: Bool { false }
}

/// Versi type-erased dari `WidgetDefinition` supaya bisa disimpan dalam satu daftar.
struct AnyWidgetDefinition: Identifiable {
    let id: String
    let displayName: String
    let symbol: String
    let minimumSize: CGSize
    let defaultSize: CGSize
    let isInteractive: Bool
    let isHoverable: Bool
    let defaultConfig: JSONValue
    let content: (JSONValue, CGSize) -> AnyView
    let settings: (Binding<JSONValue>) -> AnyView

    init<W: WidgetDefinition>(_ type: W.Type) {
        id = W.id
        displayName = W.displayName
        symbol = W.symbol
        minimumSize = W.minimumSize
        defaultSize = W.defaultSize
        isInteractive = W.isInteractive
        isHoverable = W.isHoverable
        defaultConfig = (try? JSONValue(encoding: W.defaultConfig)) ?? .null
        content = { json, size in
            AnyView(W.makeContent(config: Self.config(W.self, json), size: size))
        }
        settings = { binding in
            let typed = Binding<W.Config>(
                get: { Self.config(W.self, binding.wrappedValue) },
                set: { if let json = try? JSONValue(encoding: $0) { binding.wrappedValue = json } }
            )
            return AnyView(W.makeSettings(config: typed))
        }
    }

    private static func config<W: WidgetDefinition>(_ type: W.Type, _ json: JSONValue) -> W.Config {
        (try? json.decoded(as: W.Config.self)) ?? W.defaultConfig
    }
}

private struct WidgetActiveKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// `false` saat layar tidur/terkunci atau widget tertutup penuh. Widget harus berhenti merender.
    var widgetActive: Bool {
        get { self[WidgetActiveKey.self] }
        set { self[WidgetActiveKey.self] = newValue }
    }
}

/// Memperbarui konten pada interval tetap yang selaras dengan jam dinding,
/// dan berhenti sepenuhnya saat widget tidak aktif.
struct TickView<Content: View>: View {
    let interval: TimeInterval
    @ViewBuilder let content: (Date) -> Content
    @Environment(\.widgetActive) private var active

    var body: some View {
        if active {
            let now = Date().timeIntervalSinceReferenceDate
            let anchor = Date(timeIntervalSinceReferenceDate: (now / interval).rounded(.down) * interval)
            TimelineView(.periodic(from: anchor, by: interval)) { ctx in content(ctx.date) }
        } else {
            content(Date())
        }
    }
}
