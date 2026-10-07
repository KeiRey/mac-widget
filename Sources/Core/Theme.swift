import SwiftUI
import AppKit

enum WidgetTheme: String, Codable, CaseIterable, Identifiable {
    case minimal, glass, dark, light, neon, auto
    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: return "Minimal (tanpa latar)"
        case .glass: return "Liquid Glass"
        case .dark: return "Gelap"
        case .light: return "Terang"
        case .neon: return "Neon"
        case .auto: return "Ikuti sistem"
        }
    }

    var foreground: Color {
        switch self {
        case .minimal, .dark, .glass: return .white
        case .light: return Color(white: 0.1)
        case .neon: return Color(red: 0.25, green: 1.0, blue: 0.7)
        case .auto: return .primary
        }
    }

    var accent: Color {
        switch self {
        case .neon: return Color(red: 1.0, green: 0.3, blue: 0.7)
        default: return Color.orange
        }
    }

    var background: Color? {
        switch self {
        case .minimal, .glass: return nil
        case .dark: return Color.black.opacity(0.78)
        case .light: return Color.white.opacity(0.88)
        case .neon: return Color.black.opacity(0.85)
        case .auto: return Color(nsColor: .windowBackgroundColor).opacity(0.8)
        }
    }
}

struct RGB: Codable, Hashable {
    var r: Double, g: Double, b: Double

    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        r = Double(c.redComponent); g = Double(c.greenComponent); b = Double(c.blueComponent)
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

enum FontDesignChoice: String, Codable, CaseIterable, Identifiable {
    case rounded, standard, serif, mono
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rounded: return "Bulat"
        case .standard: return "Standar"
        case .serif: return "Serif"
        case .mono: return "Monospace"
        }
    }
    var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .standard: return .default
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}

/// Seluruh pengaturan tampilan satu widget: tema, warna, font, dan parameter Liquid Glass.
struct Look: Codable, Hashable {
    var theme: WidgetTheme = .minimal
    var textColor: RGB?
    var accentColor: RGB?
    var backgroundColor: RGB?
    var backgroundOpacity = 0.8
    var fontFamily = ""            // kosong = font sistem
    var fontDesign: FontDesignChoice = .rounded
    /// Liquid Glass: 0 = pekat/ber-tint, 1 = sangat bening.
    var transparency = 0.5
    /// Liquid Glass: kekuatan kilau tepi dan pantulan "cair".
    var liquid = 0.7

    init(_ theme: WidgetTheme = .minimal) { self.theme = theme }

    // Menerima format lama (hanya string nama tema) dan field yang belum ada.
    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            theme = WidgetTheme(rawValue: s) ?? .minimal
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decodeIfPresent(WidgetTheme.self, forKey: .theme) ?? .minimal
        textColor = try c.decodeIfPresent(RGB.self, forKey: .textColor)
        accentColor = try c.decodeIfPresent(RGB.self, forKey: .accentColor)
        backgroundColor = try c.decodeIfPresent(RGB.self, forKey: .backgroundColor)
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.8
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? ""
        fontDesign = try c.decodeIfPresent(FontDesignChoice.self, forKey: .fontDesign) ?? .rounded
        transparency = try c.decodeIfPresent(Double.self, forKey: .transparency) ?? 0.5
        liquid = try c.decodeIfPresent(Double.self, forKey: .liquid) ?? 0.7
    }

    static var glassAvailable: Bool {
        if #available(macOS 26.0, *) { return true } else { return false }
    }

    var isGlass: Bool { theme == .glass }
    var foreground: Color { textColor?.color ?? theme.foreground }
    var secondary: Color { foreground.opacity(0.65) }
    var accent: Color { accentColor?.color ?? theme.accent }

    /// Warna latar datar (nil bila tanpa latar atau memakai glass).
    var background: Color? {
        if let bg = backgroundColor { return bg.color.opacity(backgroundOpacity) }
        return theme.background
    }

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if fontFamily.isEmpty { return .system(size: size, weight: weight, design: fontDesign.design) }
        return .custom(fontFamily, size: size).weight(weight)
    }
}

extension View {
    /// Latar datar (jika ada). Tema Glass tidak punya latar: kacanya ada pada huruf (lihat `LText`).
    func themed(_ look: Look, size: CGSize) -> some View {
        let radius = min(size.width, size.height) * 0.1
        return self
            .background {
                if let bg = look.background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(bg)
                }
            }
            .shadow(color: look.theme == .minimal ? .black.opacity(0.35) : .clear, radius: 3, y: 1)
    }
}

// MARK: - Pengaturan tampilan (dipakai semua widget)

struct LookSettings: View {
    @Binding var look: Look
    private static let families = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        Picker("Tema", selection: $look.theme) {
            ForEach(WidgetTheme.allCases) { Text($0.title).tag($0) }
        }

        if look.theme == .glass {
            HStack {
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary)
                Slider(value: $look.transparency, in: 0...1) { Text("Transparansi") }
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Transparansi")
            HStack {
                Image(systemName: "drop").foregroundStyle(.secondary)
                Slider(value: $look.liquid, in: 0...1) { Text("Ketebalan lensa") }
                Image(systemName: "drop.fill").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ketebalan lensa")
            Text(Look.glassAvailable
                 ? "Huruf memakai Liquid Glass asli macOS (membiaskan latar). Transparansi: kiri lebih pekat/ber-tint, kanan bening. Ketebalan lensa: menebalkan kontur huruf sehingga area pembiasan lebih besar."
                 : "Liquid Glass asli butuh macOS 26 atau lebih baru. Di versi ini huruf tampil sebagai teks biasa.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Picker("Font", selection: $look.fontFamily) {
            Text("Sistem").tag("")
            ForEach(Self.families, id: \.self) { Text($0).tag($0) }
        }
        if look.fontFamily.isEmpty {
            Picker("Gaya huruf", selection: $look.fontDesign) {
                ForEach(FontDesignChoice.allCases) { Text($0.title).tag($0) }
            }
        }

        optionalColor("Warna teks", $look.textColor, fallback: look.theme.foreground)
        optionalColor("Warna aksen", $look.accentColor, fallback: look.theme.accent)
        optionalColor("Warna latar", $look.backgroundColor, fallback: .black)
        if look.backgroundColor != nil {
            HStack {
                Text("Opasitas latar")
                Slider(value: $look.backgroundOpacity, in: 0...1)
            }
        }
    }

    private func optionalColor(_ title: String, _ value: Binding<RGB?>, fallback: Color) -> some View {
        HStack {
            ColorPicker(title, selection: Binding(
                get: { value.wrappedValue?.color ?? fallback },
                set: { value.wrappedValue = RGB($0) }))
            if value.wrappedValue != nil {
                Button("Reset") { value.wrappedValue = nil }.buttonStyle(.borderless)
            }
        }
    }
}
