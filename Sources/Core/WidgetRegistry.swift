import Foundation

enum WidgetRegistry {
    /// Daftarkan widget baru di sini.
    static let all: [AnyWidgetDefinition] = [
        AnyWidgetDefinition(ClockWidget.self),
        AnyWidgetDefinition(DateCalendarWidget.self),
        AnyWidgetDefinition(TimerWidget.self),
        AnyWidgetDefinition(SystemMonitorWidget.self),
        AnyWidgetDefinition(AppUsageWidget.self),
        AnyWidgetDefinition(AITokensWidget.self),
    ]

    static func definition(for id: String) -> AnyWidgetDefinition? {
        all.first { $0.id == id }
    }
}
