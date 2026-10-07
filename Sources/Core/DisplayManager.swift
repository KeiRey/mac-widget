import AppKit

enum DisplayManager {
    static let mainID = "main"

    static var primary: NSScreen { NSScreen.screens.first ?? NSScreen.main! }

    static func id(for screen: NSScreen) -> String {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(num)?.takeRetainedValue(),
              let str = CFUUIDCreateString(nil, uuid) as String? else { return mainID }
        return str
    }

    static func screen(for id: String) -> NSScreen {
        if id == mainID { return primary }
        return NSScreen.screens.first { Self.id(for: $0) == id } ?? primary
    }

    static var all: [(id: String, name: String)] {
        [(mainID, "Layar utama")] + NSScreen.screens.map { (id(for: $0), $0.localizedName) }
    }

    static func absolute(_ f: FrameRect, on screen: NSScreen) -> CGRect {
        CGRect(x: screen.frame.minX + f.x, y: screen.frame.minY + f.y, width: f.w, height: f.h)
    }

    static func relative(_ r: CGRect, on screen: NSScreen) -> FrameRect {
        FrameRect(CGRect(x: r.minX - screen.frame.minX, y: r.minY - screen.frame.minY,
                         width: r.width, height: r.height))
    }

    /// Layar tempat titik tengah jendela berada.
    static func screen(containing rect: CGRect) -> NSScreen? {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(c) }
    }
}
