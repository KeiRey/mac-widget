import SwiftUI
import AppKit
import CoreText

// Liquid Glass asli: sistem menghitung pembiasan (lensing) dari BENTUK yang diberikan ke `glassEffect`.
// Karena `Text` tidak bisa dijadikan bentuk, kontur huruf diambil dari CoreText dan dipakai sebagai `Shape`.

extension Look {
    /// Font AppKit setara `font(_:_:)`, dipakai untuk mengukur dan mengambil kontur huruf.
    func nsFont(_ size: CGFloat, _ weight: Font.Weight = .regular, monoDigits: Bool = false) -> NSFont {
        let w = weight.nsWeight
        var base: NSFont
        if fontFamily.isEmpty {
            base = NSFont.systemFont(ofSize: size, weight: w)
            if let d = base.fontDescriptor.withDesign(fontDesign.nsDesign), let f = NSFont(descriptor: d, size: size) {
                base = f
            }
        } else {
            let desc = NSFontDescriptor(fontAttributes: [
                .family: fontFamily,
                .traits: [NSFontDescriptor.TraitKey.weight: w.rawValue],
            ])
            base = NSFont(descriptor: desc, size: size) ?? NSFont.systemFont(ofSize: size, weight: w)
        }
        if monoDigits {
            let desc = base.fontDescriptor.addingAttributes([.featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: 6,       // Number Spacing
                NSFontDescriptor.FeatureKey.selectorIdentifier: 0,   // Monospaced Numbers
            ]]])
            base = NSFont(descriptor: desc, size: size) ?? base
        }
        return base
    }

    /// Ukuran teks sebenarnya (untuk menyesuaikan font dengan ruang yang tersedia).
    func measure(_ text: String, _ size: CGFloat, _ weight: Font.Weight = .regular, monoDigits: Bool = false) -> CGSize {
        TextOutline.measure(text, nsFont(size, weight, monoDigits: monoDigits))
    }
}

private extension Font.Weight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

private extension FontDesignChoice {
    var nsDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .rounded: return .rounded
        case .standard: return .default
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}

enum TextOutline {
    static func line(_ text: String, _ font: NSFont) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    }

    static func measure(_ text: String, _ font: NSFont) -> CGSize {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let w = CTLineGetTypographicBounds(line(text, font), &ascent, &descent, &leading)
        return CGSize(width: ceil(w), height: ceil(ascent + descent))
    }

    /// Kontur teks, dipusatkan pada `center` (koordinat SwiftUI, sumbu Y ke bawah).
    static func path(_ text: String, _ font: NSFont, center: CGPoint) -> CGPath {
        let ct = line(text, font)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(ct, &ascent, &descent, &leading))
        let x0 = center.x - width / 2
        let baseline = center.y - (ascent + descent) / 2 + ascent
        let out = CGMutablePath()
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x0, ty: baseline)

        for case let run as CTRun in CTLineGetGlyphRuns(ct) as NSArray {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = (attrs[kCTFontAttributeName] as! CTFont?) ?? (font as CTFont)
            let n = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var positions = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &positions)
            for i in 0..<n {
                guard let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                out.addPath(g, transform: flip.translatedBy(x: positions[i].x, y: positions[i].y))
            }
        }
        return out
    }
}

/// Satu atau beberapa teks sebagai satu bentuk, supaya sistem membuat satu lensa glass untuk semuanya.
struct GlyphRunsShape: Shape, @unchecked Sendable {
    struct Run: @unchecked Sendable {
        let text: String
        let font: NSFont
        let center: CGPoint
    }

    let runs: [Run]
    /// Menebalkan kontur agar area pembiasan lebih lebar.
    var outset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for r in runs { p.addPath(Path(TextOutline.path(r.text, r.font, center: r.center))) }
        guard outset > 0.1 else { return p }
        let stroked = p.strokedPath(StrokeStyle(lineWidth: outset * 2, lineCap: .round, lineJoin: .round))
        return Path(p.cgPath.union(stroked.cgPath))
    }
}

extension Look {
    @available(macOS 26.0, *)
    var glassStyle: Glass {
        // Kiri: kaca "regular" ber-tint (lebih pekat). Kanan: kaca "clear" (bening).
        let base: Glass = transparency > 0.5 ? .clear : .regular
        let tint = textColor?.color ?? Color.black
        return base.tint(tint.opacity(0.35 * (1 - transparency)))
    }

    var glassOutset: CGFloat { CGFloat(liquid) }
}

/// Teks yang mengikuti `Look`: kaca cair asli di tema Glass (macOS 26+), teks biasa selain itu.
struct LText: View {
    let text: String
    let look: Look
    let size: CGFloat
    var weight: Font.Weight = .regular
    var monoDigits = false

    var body: some View {
        if look.isGlass, #available(macOS 26.0, *) {
            GlassText(text: text, look: look, size: size, weight: weight, monoDigits: monoDigits)
        } else {
            let f = look.font(size, weight)
            Text(text).font(monoDigits ? f.monospacedDigit() : f)
        }
    }
}

@available(macOS 26.0, *)
struct GlassText: View {
    let text: String
    let look: Look
    let size: CGFloat
    let weight: Font.Weight
    let monoDigits: Bool

    var body: some View {
        let font = look.nsFont(size, weight, monoDigits: monoDigits)
        let m = TextOutline.measure(text, font)
        let outset = look.glassOutset * size * 0.04
        let pad = ceil(outset) + 2
        let box = CGSize(width: m.width + pad * 2, height: m.height + pad * 2)
        let shape = GlyphRunsShape(runs: [.init(text: text, font: font, center: CGPoint(x: box.width / 2, y: box.height / 2))],
                                   outset: outset)
        Color.clear
            .glassEffect(look.glassStyle, in: shape)
            .frame(width: box.width, height: box.height)
            .accessibilityElement()
            .accessibilityLabel(text)
    }
}
