import Foundation
import CoreGraphics

struct FrameRect: Codable, Hashable {
    var x: Double, y: Double, w: Double, h: Double

    init(_ r: CGRect) { x = r.origin.x; y = r.origin.y; w = r.size.width; h = r.size.height }
    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

struct WidgetInstance: Codable, Identifiable, Hashable {
    var id = UUID()
    var type: String
    /// "main" atau UUID display. Frame relatif terhadap pojok kiri-bawah layar tersebut.
    var display = "main"
    var frame: FrameRect
    var opacity = 1.0
    var visible = true
    var aboveIcons = false
    var fullScreen = false
    var restoreFrame: FrameRect?
    var config: JSONValue

    init(type: String, frame: FrameRect, config: JSONValue) {
        self.type = type
        self.frame = frame
        self.config = config
    }

    // Toleran terhadap field yang belum ada di file lama.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try c.decode(String.self, forKey: .type)
        display = try c.decodeIfPresent(String.self, forKey: .display) ?? "main"
        frame = try c.decode(FrameRect.self, forKey: .frame)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        aboveIcons = try c.decodeIfPresent(Bool.self, forKey: .aboveIcons) ?? false
        fullScreen = try c.decodeIfPresent(Bool.self, forKey: .fullScreen) ?? false
        restoreFrame = try c.decodeIfPresent(FrameRect.self, forKey: .restoreFrame)
        config = try c.decodeIfPresent(JSONValue.self, forKey: .config) ?? .null
    }
}

struct Layout: Codable {
    var version = 1
    var hasLaunched = false
    var widgets: [WidgetInstance] = []
}

final class LayoutStore {
    let url: URL

    init() {
        url = AppPaths.dataDir.appendingPathComponent("layout.json")
    }

    func load() -> Layout {
        guard let data = try? Data(contentsOf: url) else { return Layout() }
        do {
            return try JSONDecoder().decode(Layout.self, from: data)
        } catch {
            // Simpan salinan file rusak agar data pengguna tidak hilang diam-diam.
            try? FileManager.default.copyItem(at: url, to: url.appendingPathExtension("corrupt"))
            return Layout()
        }
    }

    func save(_ layout: Layout) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(layout) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
