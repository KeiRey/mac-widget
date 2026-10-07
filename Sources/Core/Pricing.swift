import Foundation

/// Harga per 1 juta token (USD). `match` dicocokkan sebagai potongan nama model (tanpa membedakan huruf besar/kecil).
struct PriceRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var match: String
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheWrite: Double
}

enum DefaultPricing {
    /// Urutan penting: aturan yang lebih spesifik harus di atas yang umum.
    static let rules: [PriceRule] = [
        // Claude (tabel harga resmi Anthropic). Cache write = 1,25x input; cache read bervariasi per model.
        .init(match: "fable-5", input: 10, output: 50, cacheRead: 0.25, cacheWrite: 12.5),
        .init(match: "opus-5-5", input: 4, output: 20, cacheRead: 0.20, cacheWrite: 5),
        .init(match: "opus-5", input: 5, output: 25, cacheRead: 0.50, cacheWrite: 6.25),
        .init(match: "opus-4", input: 5, output: 25, cacheRead: 0.50, cacheWrite: 6.25),
        .init(match: "sonnet-5", input: 2, output: 10, cacheRead: 0.20, cacheWrite: 2.5),
        .init(match: "sonnet-4", input: 3, output: 15, cacheRead: 0.30, cacheWrite: 3.75),
        .init(match: "haiku", input: 1, output: 5, cacheRead: 0.10, cacheWrite: 1.25),
        // OpenAI GPT-5 / Codex (perkiraan dari daftar harga publik)
        .init(match: "gpt-5", input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 0),
        // Google Gemini Flash (perkiraan dari daftar harga publik)
        .init(match: "flash", input: 0.50, output: 3.00, cacheRead: 0.05, cacheWrite: 0),
    ]
}

/// Tabel harga yang bisa diedit pengguna, disimpan di Application Support (pricing.json).
@MainActor
final class PricingStore: ObservableObject {
    static let shared = PricingStore()

    @Published var rules: [PriceRule] {
        didSet { save() }
    }

    private let url: URL

    private init() {
        url = AppPaths.dataDir.appendingPathComponent("pricing.json")
        if let d = try? Data(contentsOf: url), let r = try? JSONDecoder().decode([PriceRule].self, from: d) {
            rules = r
        } else {
            rules = DefaultPricing.rules
        }
    }

    func price(for model: String) -> PriceRule? {
        let m = model.lowercased()
        return rules.first { !$0.match.isEmpty && m.contains($0.match.lowercased()) }
    }

    func reset() { rules = DefaultPricing.rules }

    private func save() {
        if let d = try? JSONEncoder().encode(rules) { try? d.write(to: url, options: .atomic) }
    }
}
