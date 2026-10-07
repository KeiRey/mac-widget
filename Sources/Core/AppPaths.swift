import Foundation

enum AppPaths {
    /// Folder data aplikasi. `DESKWIDGETS_DATA_DIR` mengalihkannya (dipakai untuk pengujian agar data asli tidak tersentuh).
    static var dataDir: URL {
        let dir: URL
        if let custom = ProcessInfo.processInfo.environment["DESKWIDGETS_DATA_DIR"], !custom.isEmpty {
            dir = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            dir = base.appendingPathComponent("DeskWidgets", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
