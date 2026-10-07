import Foundation
import SQLite3
import AppKit
import SwiftUI

// MARK: - Model

enum TokenMetric: String, Codable, CaseIterable, Identifiable {
    case all, io, output, cost
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Semua token (termasuk cache)"
        case .io: return "Input + output (tanpa cache)"
        case .output: return "Output saja"
        case .cost: return "Biaya (USD, perkiraan)"
        }
    }
}

/// Token per jam (indeks 0...23) untuk satu agent dalam satu hari.
struct TokenDay: Codable {
    var i = [Int](repeating: 0, count: 24)    // input (tanpa cache)
    var o = [Int](repeating: 0, count: 24)    // output (termasuk reasoning)
    var cr = [Int](repeating: 0, count: 24)   // cache read
    var cw = [Int](repeating: 0, count: 24)   // cache write

    func hours(_ metric: TokenMetric) -> [Double] {
        (0..<24).map { h in
            switch metric {
            case .all: return Double(i[h] + o[h] + cr[h] + cw[h])
            case .io: return Double(i[h] + o[h])
            case .output: return Double(o[h])
            case .cost: return 0   // biaya dihitung per model oleh TokenStore
            }
        }
    }
}

/// Posisi baca terakhir per file/database, supaya tiap pemindaian hanya membaca data baru.
struct TokenFileState: Codable {
    var offset: Int64 = 0
    var stamp: Double = 0          // mtime (Antigravity)
    var count = 0                  // jumlah generation yang sudah dihitung (Antigravity)
    var prevIn: Int = 0            // total kumulatif terakhir (Codex)
    var prevCached: Int = 0
    var prevOut: Int = 0
    var model = ""                // model aktif terakhir (Codex)
}

struct TokenData: Codable {
    var version = 2
    /// "yyyy-MM-dd" -> id agent -> nama model -> token
    var days: [String: [String: [String: TokenDay]]] = [:]
    var files: [String: TokenFileState] = [:]
    var opencodeUpdated: Int64 = 0
}

struct TokenProviderInfo: Identifiable {
    let id: String
    let name: String
    let initial: String
    let color: RGB
    let roots: [String]
    /// Format log tidak terdokumentasi resmi, jadi angkanya perkiraan.
    var estimated = false

    var available: Bool { roots.contains { FileManager.default.fileExists(atPath: NSString(string: $0).expandingTildeInPath) } }
}

enum TokenProviders {
    static let all: [TokenProviderInfo] = [
        .init(id: "claude", name: "Claude Code", initial: "C", color: RGB(Color(red: 0.85, green: 0.47, blue: 0.34)),
              roots: ["~/.claude/projects", "~/.config/claude/projects"]),
        .init(id: "codex", name: "Codex", initial: "X", color: RGB(Color(red: 0.20, green: 0.72, blue: 0.58)),
              roots: ["~/.codex/sessions"]),
        .init(id: "antigravity", name: "Antigravity CLI", initial: "A", color: RGB(Color(red: 0.26, green: 0.52, blue: 0.96)),
              roots: ["~/.gemini/antigravity-cli/conversations"], estimated: true),
        .init(id: "opencode", name: "OpenCode", initial: "O", color: RGB(Color(red: 0.62, green: 0.45, blue: 0.95)),
              roots: ["~/.local/share/opencode/opencode.db"]),
    ]

    static func info(_ id: String) -> TokenProviderInfo? { all.first { $0.id == id } }
}

enum DayKey {
    static func string(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

enum TokenFormat {
    static func money(_ v: Double) -> String {
        if v <= 0 { return "$0" }
        if v < 0.01 { return "<$0.01" }
        if v >= 10_000 { return String(format: "$%.1fK", v / 1_000) }
        if v >= 1_000 { return String(format: "$%.0f", v) }
        return String(format: "$%.2f", v)
    }

    static func short(_ v: Double) -> String {
        func fmt(_ x: Double, _ suffix: String, _ digits: Int) -> String {
            var t = String(format: "%.\(digits)f", x)
            if t.contains(".") { while t.hasSuffix("0") { t.removeLast() }; if t.hasSuffix(".") { t.removeLast() } }
            return t + suffix
        }
        switch v {
        case 1_000_000_000...: return fmt(v / 1_000_000_000, "B", 1)
        case 1_000_000...: return fmt(v / 1_000_000, "M", 1)
        case 10_000...: return fmt(v / 1_000, "K", 0)
        case 1_000...: return fmt(v / 1_000, "K", 1)
        default: return "\(Int(v))"
        }
    }
}

// MARK: - Store

/// Total token harian per agent, dibaca dari log lokal masing-masing agent. Tidak ada data yang dikirim ke mana pun.
@MainActor
final class TokenStore: ObservableObject {
    static let shared = TokenStore()

    @Published private(set) var revision = 0
    @Published private(set) var scanning = false
    @Published private(set) var lastScan: Date?
    private(set) var data: TokenData
    private let scanner = TokenScanner()

    private init() { data = TokenScanner.loadData() }

    func refresh() async {
        guard !scanning else { return }
        scanning = true
        let scanner = self.scanner
        let snapshot = await Task.detached(priority: .utility) { scanner.scan() }.value
        data = snapshot
        lastScan = Date()
        scanning = false
        revision &+= 1
    }

    func rescanFromScratch() async {
        guard !scanning else { return }
        data = TokenData()
        scanner.reset()
        revision &+= 1
        await refresh()
    }

    // MARK: Kueri

    private func models(_ provider: String, day: String) -> [String: TokenDay] {
        data.days[day]?[provider] ?? [:]
    }

    /// Nilai per jam untuk satu agent; metrik biaya dihitung per model dengan tabel harga saat ini.
    func hourly(_ provider: String, _ metric: TokenMetric, day: String) -> [Double] {
        var out = [Double](repeating: 0, count: 24)
        for (model, d) in models(provider, day: day) {
            if metric == .cost {
                guard let p = PricingStore.shared.price(for: model) else { continue }
                for h in 0..<24 { out[h] += Self.cost(p, i: d.i[h], o: d.o[h], cr: d.cr[h], cw: d.cw[h]) }
            } else {
                let hrs = d.hours(metric)
                for h in 0..<24 { out[h] += hrs[h] }
            }
        }
        return out
    }

    func total(_ provider: String, _ metric: TokenMetric, day: String) -> Double {
        hourly(provider, metric, day: day).reduce(0, +)
    }

    /// Rincian lengkap untuk tooltip: input/output/cache, biaya, dan per model. `hour` nil = seluruh hari.
    func breakdown(_ provider: String, day: String, hour: Int? = nil) -> TokenBreakdown {
        var b = TokenBreakdown()
        for (model, d) in models(provider, day: day) {
            let range = hour.map { $0...$0 } ?? 0...23
            var i = 0, o = 0, cr = 0, cw = 0
            for h in range { i += d.i[h]; o += d.o[h]; cr += d.cr[h]; cw += d.cw[h] }
            guard i + o + cr + cw > 0 else { continue }
            let price = PricingStore.shared.price(for: model)
            let cost = price.map { Self.cost($0, i: i, o: o, cr: cr, cw: cw) } ?? 0
            b.input += Double(i); b.output += Double(o); b.cacheRead += Double(cr); b.cacheWrite += Double(cw)
            b.cost += cost
            b.perModel.append(.init(model: model, tokens: Double(i + o + cr + cw), cost: cost, priced: price != nil))
        }
        b.perModel.sort { $0.tokens > $1.tokens }
        return b
    }

    private static func cost(_ p: PriceRule, i: Int, o: Int, cr: Int, cw: Int) -> Double {
        let input = Double(i) * p.input, output = Double(o) * p.output
        let read = Double(cr) * p.cacheRead, write = Double(cw) * p.cacheWrite
        return (input + output + read + write) / 1_000_000
    }

    /// Model yang pernah tercatat tetapi belum punya aturan harga.
    var unpricedModels: [String] {
        var seen = Set<String>()
        for (_, provs) in data.days { for (_, models) in provs { for model in models.keys where PricingStore.shared.price(for: model) == nil { seen.insert(model) } } }
        return seen.sorted()
    }

    /// Format nilai sesuai metrik: biaya dalam dolar, selain itu jumlah token singkat.
    static func format(_ v: Double, _ metric: TokenMetric) -> String {
        metric == .cost ? TokenFormat.money(v) : TokenFormat.short(v)
    }
}

struct ModelUsage {
    let model: String
    let tokens: Double
    let cost: Double
    let priced: Bool
}

struct TokenBreakdown {
    var input = 0.0, output = 0.0, cacheRead = 0.0, cacheWrite = 0.0
    var cost = 0.0
    var perModel: [ModelUsage] = []
    var total: Double { input + output + cacheRead + cacheWrite }
    var unpriced: [String] { perModel.filter { !$0.priced }.map(\.model) }
}

// MARK: - Pemindai (di luar main thread)

final class TokenScanner: @unchecked Sendable {
    private static var dir: URL { AppPaths.dataDir }
    private static var dataURL: URL { dir.appendingPathComponent("tokens-v2.json") }
    private static var seenURL: URL { dir.appendingPathComponent("tokens-seen-v2.bin") }

    private let lock = NSLock()
    private var data: TokenData
    /// Claude Code: hash("id:requestId") -> output token yang sudah dihitung (menghindari hitung ganda antar file).
    private var seen: [UInt64: UInt32]
    private var dirty = false
    private let cal = Calendar.current
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain = ISO8601DateFormatter()

    init() {
        // Format lama (tanpa dimensi model) tidak kompatibel; berkas lama dibuang dan data dipindai ulang.
        let old = Self.dir
        for name in ["tokens.json", "tokens-seen.bin"] { try? FileManager.default.removeItem(at: old.appendingPathComponent(name)) }
        data = Self.loadData()
        seen = Self.loadSeen()
    }

    static func loadData() -> TokenData {
        guard let d = try? Data(contentsOf: dataURL), let t = try? JSONDecoder().decode(TokenData.self, from: d) else {
            return TokenData()
        }
        return t
    }

    private static func loadSeen() -> [UInt64: UInt32] {
        guard let d = try? Data(contentsOf: seenURL) else { return [:] }
        var out: [UInt64: UInt32] = [:]
        out.reserveCapacity(d.count / 12)
        d.withUnsafeBytes { raw in
            var off = 0
            while off + 12 <= raw.count {
                out[raw.loadUnaligned(fromByteOffset: off, as: UInt64.self)] = raw.loadUnaligned(fromByteOffset: off + 8, as: UInt32.self)
                off += 12
            }
        }
        return out
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        data = TokenData()
        seen = [:]
        dirty = true
        save()
    }

    func scan() -> TokenData {
        lock.lock(); defer { lock.unlock() }
        scanClaude()
        scanCodex()
        scanOpenCode()
        scanAntigravity()
        save()
        malloc_zone_pressure_relief(nil, 0)
        return data
    }

    private func save() {
        guard dirty else { return }
        dirty = false
        if let enc = try? JSONEncoder().encode(data) { try? enc.write(to: Self.dataURL, options: .atomic) }
        var bin = Data(capacity: seen.count * 12)
        for (k, v) in seen {
            var kk = k, vv = v
            withUnsafeBytes(of: &kk) { bin.append(contentsOf: $0) }
            withUnsafeBytes(of: &vv) { bin.append(contentsOf: $0) }
        }
        try? bin.write(to: Self.seenURL, options: .atomic)
    }

    // MARK: Penambahan

    private func add(_ provider: String, model: String, _ date: Date, i: Int, o: Int, cr: Int, cw: Int) {
        guard i > 0 || o > 0 || cr > 0 || cw > 0 else { return }
        let c = cal.dateComponents([.year, .month, .day, .hour], from: date)
        let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let h = min(23, max(0, c.hour ?? 0))
        let name = model.isEmpty ? "unknown" : model
        var day = data.days[key]?[provider]?[name] ?? TokenDay()
        day.i[h] += i; day.o[h] += o; day.cr[h] += cr; day.cw[h] += cw
        data.days[key, default: [:]][provider, default: [:]][name] = day
        dirty = true
    }

    private func parseDate(_ s: String) -> Date? { iso.date(from: s) ?? isoPlain.date(from: s) }

    private func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

    // MARK: Baca file per baris

    /// Membaca baris lengkap dari `offset`; mengembalikan offset baru (baris terakhir yang belum selesai ditunda).
    private func forEachLine(_ url: URL, from offset: Int64, _ body: (Data) -> Void) -> Int64 {
        guard let h = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? h.close() }
        do { try h.seek(toOffset: UInt64(offset)) } catch { return offset }
        var carry = Data()
        var consumed = offset
        var finished = false
        // Tiap potongan diproses dalam pool sendiri; kalau tidak, seluruh isi file menumpuk di memori sampai pemindaian selesai.
        while !finished {
            autoreleasepool {
                guard let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty else { finished = true; return }
                carry.append(chunk)
                guard let lastNL = carry.lastIndex(of: 0x0A) else { return }
                let complete = carry[carry.startIndex...lastNL]
                var start = complete.startIndex
                while let nl = complete[start...].firstIndex(of: 0x0A) {
                    if nl > start { autoreleasepool { body(complete[start..<nl]) } }
                    start = complete.index(after: nl)
                }
                consumed += Int64(complete.count)
                carry = Data(carry[carry.index(after: lastNL)...])
            }
        }
        return consumed
    }

    private func jsonlFiles(under roots: [String]) -> [URL] {
        var out: [URL] = []
        for r in roots {
            let root = URL(fileURLWithPath: NSString(string: r).expandingTildeInPath)
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let u as URL in e where u.pathExtension == "jsonl" { out.append(u) }
        }
        return out
    }

    private func contains(_ line: Data, _ needle: [UInt8]) -> Bool {
        line.withUnsafeBytes { hay in
            needle.withUnsafeBytes { n in
                memmem(hay.baseAddress, hay.count, n.baseAddress, n.count) != nil
            }
        }
    }

    private func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    // MARK: Claude Code

    private static let usageKey = Array("\"usage\":".utf8)
    private static let timestampKey = Array("\"timestamp\":\"".utf8)
    private static let messageIDKey = Array("\"id\":\"msg_".utf8)
    private static let requestIDKey = Array("\"requestId\":\"".utf8)
    private static let inputKey = Array("\"input_tokens\":".utf8)
    private static let outputKey = Array("\"output_tokens\":".utf8)
    private static let cacheReadKey = Array("\"cache_read_input_tokens\":".utf8)
    private static let cacheWriteKey = Array("\"cache_creation_input_tokens\":".utf8)
    private static let modelKey = Array("\"model\":\"".utf8)
    private static let syntheticModel = Array("\"model\":\"<synthetic>\"".utf8)

    private func scanClaude() {
        let needle = Array("\"usage\"".utf8)
        for url in jsonlFiles(under: TokenProviders.info("claude")?.roots ?? []) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
            var st = data.files[url.path] ?? TokenFileState()
            if Int64(size) < st.offset { st = TokenFileState() }
            if Int64(size) == st.offset { continue }

            st.offset = forEachLine(url, from: st.offset) { line in
                guard contains(line, needle) else { return }
                // Baris log memuat seluruh isi percakapan; hanya field yang dibutuhkan yang diambil,
                // tanpa mengurai JSON penuh (hemat memori dan CPU, dan isi percakapan tidak disentuh).
                line.withUnsafeBytes { raw in
                    let j = RawJSON(raw)
                    // Hanya pesan assistant yang punya "id":"msg_…"; usage dicari setelahnya, bukan di hasil tool/subagent.
                    guard !j.contains(Self.syntheticModel),
                          let idAt = j.find(Self.messageIDKey, from: 0),
                          let usage = j.object(after: Self.usageKey, from: idAt),
                          let tsText = j.string(after: Self.timestampKey), let ts = parseDate(tsText) else { return }

                    let input = j.int(Self.inputKey, in: usage), out = j.int(Self.outputKey, in: usage)
                    let cr = j.int(Self.cacheReadKey, in: usage), cw = j.int(Self.cacheWriteKey, in: usage)
                    let id = j.string(after: Self.messageIDKey).map { "msg_" + $0 } ?? "", req = j.string(after: Self.requestIDKey) ?? ""
                    // Di log, "model" tercatat tepat sebelum "id" pada objek message.
                    let model = j.string(after: Self.modelKey, from: max(0, idAt - 200)) ?? j.string(after: Self.modelKey) ?? "unknown"
                    if id.isEmpty && req.isEmpty {
                        add("claude", model: model, ts, i: input, o: out, cr: cr, cw: cw)
                        return
                    }
                    let h = fnv("\(id):\(req)")
                    if let prev = seen[h] {
                        // Salinan streaming/riwayat yang di-resume: hanya tambah kenaikan output.
                        if out > Int(prev) {
                            add("claude", model: model, ts, i: 0, o: out - Int(prev), cr: 0, cw: 0)
                            seen[h] = UInt32(min(out, Int(UInt32.max)))
                            dirty = true
                        }
                    } else {
                        add("claude", model: model, ts, i: input, o: out, cr: cr, cw: cw)
                        seen[h] = UInt32(min(out, Int(UInt32.max)))
                    }
                }
            }
            data.files[url.path] = st
            dirty = true
        }
    }

    // MARK: Codex

    private func scanCodex() {
        let needle = Array("\"token_count\"".utf8)
        let contextNeedle = Array("\"turn_context\"".utf8)
        for url in jsonlFiles(under: TokenProviders.info("codex")?.roots ?? []) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
            var st = data.files[url.path] ?? TokenFileState()
            if Int64(size) < st.offset { st = TokenFileState() }
            if Int64(size) == st.offset { continue }

            st.offset = forEachLine(url, from: st.offset) { line in
                if contains(line, contextNeedle) {
                    // Model aktif ditandai di turn_context; diambil langsung dari byte tanpa mengurai baris besar.
                    line.withUnsafeBytes { raw in
                        if let m = RawJSON(raw).string(after: Self.modelKey) { st.model = m }
                    }
                    return
                }
                guard contains(line, needle),
                      let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let p = o["payload"] as? [String: Any], (p["type"] as? String) == "token_count",
                      let info = p["info"] as? [String: Any],
                      let total = info["total_token_usage"] as? [String: Any],
                      let ts = (o["timestamp"] as? String).flatMap(parseDate) else { return }

                // `total_token_usage` kumulatif per sesi: yang dihitung adalah selisihnya.
                let cin = int(total["input_tokens"]), ccached = int(total["cached_input_tokens"]), cout = int(total["output_tokens"])
                let reset = cin < st.prevIn || cout < st.prevOut
                let din = reset ? cin : cin - st.prevIn
                let dcached = reset ? ccached : ccached - st.prevCached
                let dout = reset ? cout : cout - st.prevOut
                st.prevIn = cin; st.prevCached = ccached; st.prevOut = cout
                // `input_tokens` sudah termasuk bagian yang di-cache.
                add("codex", model: st.model, ts, i: max(0, din - dcached), o: max(0, dout), cr: max(0, dcached), cw: 0)
            }
            data.files[url.path] = st
            dirty = true
        }
    }

    // MARK: OpenCode (SQLite)

    private func scanOpenCode() {
        let path = NSString(string: "~/.local/share/opencode/opencode.db").expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path), let db = SQLiteDB(path: path) else { return }
        var newest = data.opencodeUpdated
        db.query("SELECT time_updated, data FROM message WHERE time_updated > ? ORDER BY time_updated",
                 bind: data.opencodeUpdated) { stmt in
            let updated = sqlite3_column_int64(stmt, 0)
            newest = max(newest, updated)
            guard let blob = SQLiteDB.data(stmt, 1),
                  let o = try? JSONSerialization.jsonObject(with: blob) as? [String: Any],
                  (o["role"] as? String) == "assistant",
                  let tokens = o["tokens"] as? [String: Any],
                  let time = o["time"] as? [String: Any], time["completed"] != nil,
                  let created = (time["created"] as? NSNumber)?.doubleValue else { return }
            let cache = tokens["cache"] as? [String: Any]
            // Reasoning dihitung terpisah dari output di OpenCode.
            add("opencode", model: (o["modelID"] as? String) ?? "unknown", Date(timeIntervalSince1970: created / 1000),
                i: int(tokens["input"]), o: int(tokens["output"]) + int(tokens["reasoning"]),
                cr: int(cache?["read"]), cw: int(cache?["write"]))
        }
        if newest != data.opencodeUpdated { data.opencodeUpdated = newest; dirty = true }
    }

    // MARK: Antigravity CLI (SQLite + protobuf, format tidak terdokumentasi)

    /// Nama model "gemini-…" yang tertanam sebagai teks di blob generation.
    private static func geminiModel(in blob: Data) -> String {
        let key = Array("gemini-".utf8)
        return blob.withUnsafeBytes { raw -> String in
            guard let at = RawJSON(raw).find(key, from: 0) else { return "gemini" }
            var end = at
            while end < raw.count, (raw[end] >= 0x30 && raw[end] <= 0x39) || (raw[end] >= 0x61 && raw[end] <= 0x7A) || raw[end] == 0x2E || raw[end] == 0x2D { end += 1 }
            return String(decoding: UnsafeRawBufferPointer(rebasing: raw[at..<end]), as: UTF8.self)
        }
    }

    private func scanAntigravity() {
        let root = URL(fileURLWithPath: NSString(string: "~/.gemini/antigravity-cli/conversations").expandingTildeInPath)
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in files where url.pathExtension == "db" {
            // WAL berisi data terbaru, jadi perubahan mtime file -wal juga dihitung.
            let wal = URL(fileURLWithPath: url.path + "-wal")
            let stamp = [url, wal].compactMap {
                (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970
            }.max() ?? 0
            var st = data.files[url.path] ?? TokenFileState()
            if stamp == st.stamp { continue }

            guard let db = SQLiteDB(path: url.path) else { continue }
            var stepTimes: [Date] = []
            db.query("SELECT metadata FROM steps WHERE step_type = 15 ORDER BY idx") { stmt in
                guard let md = SQLiteDB.data(stmt, 0), case .bytes(let ts)? = PB.first(md, 1),
                      case .varint(let sec)? = PB.first(ts, 1) else { stepTimes.append(Date(timeIntervalSince1970: 0)); return }
                stepTimes.append(Date(timeIntervalSince1970: TimeInterval(sec)))
            }
            var k = 0
            db.query("SELECT data FROM gen_metadata ORDER BY idx") { stmt in
                defer { k += 1 }
                guard k >= st.count, k < stepTimes.count, stepTimes[k].timeIntervalSince1970 > 0,
                      let blob = SQLiteDB.data(stmt, 0),
                      case .bytes(let meta)? = PB.first(blob, 1), case .bytes(let u)? = PB.first(meta, 4) else { return }
                func num(_ f: Int) -> Int { if case .varint(let v)? = PB.first(u, f) { return Int(v) }; return 0 }
                // Dugaan dari pola data: 2 = input, 5 = cache read, 3 = output (sudah termasuk reasoning).
                add("antigravity", model: Self.geminiModel(in: blob), stepTimes[k], i: num(2), o: num(3), cr: num(5), cw: 0)
            }
            st.count = min(k, stepTimes.count)
            st.stamp = stamp
            data.files[url.path] = st
            dirty = true
        }
    }
}

// MARK: - Ekstraksi field JSON langsung dari byte

/// Pembaca field JSON tanpa mengurai dokumen. Aman untuk kunci yang dicari karena kutip di dalam string
/// selalu di-escape (`\"`), sehingga pola `"kunci":` hanya cocok dengan kunci sungguhan.
private struct RawJSON {
    let b: UnsafeRawBufferPointer
    init(_ b: UnsafeRawBufferPointer) { self.b = b }

    func contains(_ needle: [UInt8]) -> Bool { find(needle, from: 0) != nil }

    func find(_ needle: [UInt8], from: Int) -> Int? {
        guard from < b.count else { return nil }
        return needle.withUnsafeBytes { n in
            guard let p = memmem(b.baseAddress! + from, b.count - from, n.baseAddress, n.count) else { return nil }
            return b.baseAddress!.distance(to: UnsafeRawPointer(p))
        }
    }

    /// Teks setelah `needle` sampai kutip berikutnya.
    func string(after needle: [UInt8], from: Int = 0) -> String? {
        guard let at = find(needle, from: from) else { return nil }
        let start = at + needle.count
        var i = start
        while i < b.count, b[i] != 0x22 { i += 1 }
        guard i < b.count else { return nil }
        return String(decoding: UnsafeRawBufferPointer(rebasing: b[start..<i]), as: UTF8.self)
    }

    /// Rentang objek `{...}` setelah `needle` (mis. nilai dari "usage":).
    func object(after needle: [UInt8], from: Int = 0) -> Range<Int>? {
        guard let at = find(needle, from: from) else { return nil }
        var i = at + needle.count
        guard i < b.count, b[i] == 0x7B else { return nil }
        let start = i
        var depth = 0
        while i < b.count {
            if b[i] == 0x7B { depth += 1 }
            else if b[i] == 0x7D { depth -= 1; if depth == 0 { return start..<(i + 1) } }
            i += 1
        }
        return nil
    }

    /// Bilangan bulat setelah `key` di dalam `range`; 0 bila tidak ada.
    func int(_ key: [UInt8], in range: Range<Int>) -> Int {
        guard let at = find(key, from: range.lowerBound), at < range.upperBound else { return 0 }
        var i = at + key.count
        var v = 0
        while i < range.upperBound, b[i] >= 0x30, b[i] <= 0x39 { v = v &* 10 &+ Int(b[i] - 0x30); i += 1 }
        return v
    }
}

// MARK: - SQLite & protobuf mini

private final class SQLiteDB {
    private var db: OpaquePointer?

    init?(path: String) {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        sqlite3_busy_timeout(db, 500)
    }

    deinit { sqlite3_close(db) }

    @discardableResult
    func query(_ sql: String, bind: Int64? = nil, row: (OpaquePointer) -> Void) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else { return false }
        defer { sqlite3_finalize(s) }
        if let bind { sqlite3_bind_int64(s, 1, bind) }
        while sqlite3_step(s) == SQLITE_ROW { autoreleasepool { row(s) } }
        return true
    }

    static func data(_ stmt: OpaquePointer, _ col: Int32) -> Data? {
        let n = Int(sqlite3_column_bytes(stmt, col))
        guard n > 0 else { return nil }
        if let p = sqlite3_column_blob(stmt, col) { return Data(bytes: p, count: n) }
        if let t = sqlite3_column_text(stmt, col) { return Data(bytes: t, count: n) }
        return nil
    }
}

private enum PB {
    enum Value { case varint(UInt64), bytes(Data) }

    /// Field tingkat atas pertama dengan nomor `field`.
    static func first(_ d: Data, _ field: Int) -> Value? {
        let b = [UInt8](d)
        var i = 0
        func varint() -> UInt64? {
            var v: UInt64 = 0, shift: UInt64 = 0
            while i < b.count {
                let c = b[i]; i += 1
                v |= UInt64(c & 0x7f) << shift
                if c < 0x80 { return v }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }
        while i < b.count {
            guard let key = varint() else { return nil }
            let f = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let v = varint() else { return nil }
                if f == field { return .varint(v) }
            case 2:
                guard let l = varint(), i + Int(l) <= b.count else { return nil }
                if f == field { return .bytes(Data(b[i..<(i + Int(l))])) }
                i += Int(l)
            case 1: i += 8
            case 5: i += 4
            default: return nil
            }
        }
        return nil
    }
}
