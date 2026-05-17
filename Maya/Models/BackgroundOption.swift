import AppKit
import CoreImage
import Foundation
import SwiftUI

struct GradientSpec: Hashable, Sendable {
    var startHex: String
    var endHex: String
    var angleDegrees: Double

    nonisolated var startColor: Color { Color(hex: startHex) ?? .black }
    nonisolated var endColor: Color { Color(hex: endHex) ?? .white }

    static let presets: [GradientSpec] = [
        // Brand mono — the official color blended into a lighter twin.
        GradientSpec(startHex: "#6466FA", endHex: "#A78BFA", angleDegrees: 135),
        // Nebula — brand to magenta, energetic and modern.
        GradientSpec(startHex: "#6466FA", endHex: "#EC4899", angleDegrees: 135),
        // Cyber wave — brand to cyan, futurístico.
        GradientSpec(startHex: "#6466FA", endHex: "#22D3EE", angleDegrees: 135),
        // Sunset dream — soft brand to amber, contraste cálido.
        GradientSpec(startHex: "#818CF8", endHex: "#F59E0B", angleDegrees: 135),
        // Midnight brand — vertical desde noche profunda al brand.
        GradientSpec(startHex: "#1E1B4B", endHex: "#6466FA", angleDegrees: 180),
        // Deep space — oscuro premium, brand al fondo.
        GradientSpec(startHex: "#4338CA", endHex: "#0F172A", angleDegrees: 135),
        // Mist — lavanda suave, ideal para mockups claros.
        GradientSpec(startHex: "#E0E7FF", endHex: "#818CF8", angleDegrees: 135),
        // Aurora — brand entre dos tonos análogos, look soñador.
        GradientSpec(startHex: "#A5B4FC", endHex: "#C084FC", angleDegrees: 135)
    ]
}

enum BackgroundOption: Hashable, Sendable {
    /// No background — the export will be a `.mov` with HEVC + alpha channel so the
    /// framed phone can be composited over arbitrary content in another app.
    case none
    case solid(hex: String)
    case gradient(GradientSpec)
    case image(URL)
    case videoBlur

    var isTransparent: Bool {
        if case .none = self { return true }
        return false
    }

    static let defaultSolids: [String] = [
        "#6466FA", // brand
        "#4338CA", // deep brand (indigo-700)
        "#A78BFA", // soft tint (violet-400)
        "#1E1B4B", // brand-aligned near-black (indigo-950)
        "#0F172A", // premium dark (slate-900)
        "#000000",
        "#FFFFFF",
        "#F8FAFC", // premium light
        "#E0E7FF"  // lavender wash
    ]
}

extension Color {
    nonisolated init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    nonisolated var ciColor: CIColor {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return CIColor(red: ns.redComponent,
                       green: ns.greenComponent,
                       blue: ns.blueComponent,
                       alpha: ns.alphaComponent)
    }

    nonisolated var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
