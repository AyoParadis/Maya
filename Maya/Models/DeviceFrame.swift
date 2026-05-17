import CoreGraphics
import Foundation
import SwiftUI

enum DeviceFrameKind: String, Hashable, Sendable {
    case physical    // Real device with a PNG asset.
    case drawn       // SwiftUI-rendered frame with no bundled PNG asset.
    case generic     // Drawn placeholder phone (no specific brand/model look).
    case none        // No frame — video is shown bare at its own aspect ratio.
}

enum DeviceFrameStyle: String, Hashable, Sendable {
    case modernPhone
    case classicPhone
    case androidPhone
    case tablet
    case laptop
}

struct DeviceColor: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Exact asset name in the catalog.
    let imageName: String
    /// Swatch tint shown in the picker.
    let swatchHex: String
}

struct DeviceModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    /// Width / height of the rasterized PNG (all currently-supported Pro models share these).
    let frameAspectRatio: CGFloat
    /// Screen rect relative to the PNG, in normalized coords (top-left origin).
    let screenRectNormalized: CGRect
    let screenCornerRadiusNormalized: CGFloat
    let colors: [DeviceColor]
    let kind: DeviceFrameKind
    let style: DeviceFrameStyle
    /// SF Symbol used in the picker chip when there is no color swatch.
    let symbol: String

    var defaultColor: DeviceColor { colors.first! }

    func color(id: String) -> DeviceColor? {
        colors.first { $0.id == id }
    }

    func frame(for color: DeviceColor) -> DeviceFrame {
        DeviceFrame(
            id: "\(id).\(color.id)",
            displayName: kind == .physical || kind == .drawn ? "\(displayName) - \(color.name)" : displayName,
            imageName: color.imageName,
            frameAspectRatio: frameAspectRatio,
            screenRectNormalized: screenRectNormalized,
            screenCornerRadiusNormalized: screenCornerRadiusNormalized,
            kind: kind,
            style: style
        )
    }
}

extension DeviceModel {
    /// iPhone 16 Pro and 17 Pro share rasterization: 450×920 frame, 402×874
    /// screen at (24, 23), ~60pt screen radius (relative to the PNG's 450 width).
    private static let pro16_17Geometry = (
        aspect: CGFloat(450.0 / 920.0),
        screenRect: CGRect(
            x: 24.0 / 450.0,
            y: 23.0 / 920.0,
            width: 402.0 / 450.0,
            height: 874.0 / 920.0
        ),
        cornerRadius: CGFloat(60.0 / 450.0)
    )

    /// iPhone 15 Pro: 473×932 frame, 393×852 screen (centered → 40pt inset on
    /// every edge). Corner radius kept proportional to the older render so the
    /// visual mask still matches Apple's screen radius.
    private static let pro15Geometry = (
        aspect: CGFloat(473.0 / 932.0),
        screenRect: CGRect(
            x: 40.0 / 473.0,
            y: 40.0 / 932.0,
            width: 393.0 / 473.0,
            height: 852.0 / 932.0
        ),
        cornerRadius: CGFloat(60.0 / 473.0)
    )

    /// Sentinel "color" used by non-physical models so callers can keep using
    /// `model.frame(for:)` without special-casing.
    private static let voidColor = DeviceColor(
        id: "default",
        name: "Default",
        imageName: "",
        swatchHex: "#000000"
    )

    static let none = DeviceModel(
        id: "no-frame",
        displayName: "No frame",
        // Aspect is irrelevant when kind == .none — the renderer falls back to
        // the source video's natural aspect. We seed a reasonable iPhone-ish
        // aspect for the brief moment before the video loads.
        frameAspectRatio: 9.0 / 19.5,
        screenRectNormalized: CGRect(x: 0, y: 0, width: 1, height: 1),
        screenCornerRadiusNormalized: 0.04,
        colors: [voidColor],
        kind: .none,
        style: .modernPhone,
        symbol: "rectangle.dashed"
    )

    static let generic = DeviceModel(
        id: "generic-phone",
        displayName: "Generic",
        // Aspect/cornerRadius are seeded reasonably for the first frame; the
        // renderer overrides both at runtime: aspect = source video, corner =
        // user-controlled `Project.bareCornerRadius`. The screen rect fills
        // the entire phone box so the bezel can grow *outward* around it.
        frameAspectRatio: 9.0 / 19.5,
        screenRectNormalized: CGRect(x: 0, y: 0, width: 1, height: 1),
        screenCornerRadiusNormalized: 0.06,
        colors: [voidColor],
        kind: .generic,
        style: .modernPhone,
        symbol: "iphone"
    )

    static let classicPhone = DeviceModel(
        id: "classic-phone",
        displayName: "Classic iPhone",
        frameAspectRatio: 390.0 / 844.0,
        screenRectNormalized: CGRect(x: 20.0 / 390.0, y: 26.0 / 844.0, width: 350.0 / 390.0, height: 792.0 / 844.0),
        screenCornerRadiusNormalized: 42.0 / 390.0,
        colors: [
            DeviceColor(id: "graphite", name: "Graphite", imageName: "", swatchHex: "#27272A"),
            DeviceColor(id: "silver", name: "Silver", imageName: "", swatchHex: "#D7D7D2"),
            DeviceColor(id: "blue", name: "Blue", imageName: "", swatchHex: "#385A7C")
        ],
        kind: .drawn,
        style: .classicPhone,
        symbol: "iphone.gen2"
    )

    static let androidPhone = DeviceModel(
        id: "android-phone",
        displayName: "Android Phone",
        frameAspectRatio: 410.0 / 880.0,
        screenRectNormalized: CGRect(x: 20.0 / 410.0, y: 24.0 / 880.0, width: 370.0 / 410.0, height: 832.0 / 880.0),
        screenCornerRadiusNormalized: 34.0 / 410.0,
        colors: [
            DeviceColor(id: "obsidian", name: "Obsidian", imageName: "", swatchHex: "#18181B"),
            DeviceColor(id: "porcelain", name: "Porcelain", imageName: "", swatchHex: "#ECE7DD"),
            DeviceColor(id: "sage", name: "Sage", imageName: "", swatchHex: "#9BAE9D")
        ],
        kind: .drawn,
        style: .androidPhone,
        symbol: "smartphone"
    )

    static let tablet = DeviceModel(
        id: "tablet",
        displayName: "Tablet",
        frameAspectRatio: 820.0 / 1180.0,
        screenRectNormalized: CGRect(x: 42.0 / 820.0, y: 42.0 / 1180.0, width: 736.0 / 820.0, height: 1096.0 / 1180.0),
        screenCornerRadiusNormalized: 26.0 / 820.0,
        colors: [
            DeviceColor(id: "space-gray", name: "Space Gray", imageName: "", swatchHex: "#4B4A50"),
            DeviceColor(id: "silver", name: "Silver", imageName: "", swatchHex: "#D9D9D4"),
            DeviceColor(id: "rose", name: "Rose", imageName: "", swatchHex: "#C8A59A")
        ],
        kind: .drawn,
        style: .tablet,
        symbol: "ipad"
    )

    static let laptop = DeviceModel(
        id: "laptop-browser",
        displayName: "Laptop",
        frameAspectRatio: 1440.0 / 960.0,
        screenRectNormalized: CGRect(x: 72.0 / 1440.0, y: 76.0 / 960.0, width: 1296.0 / 1440.0, height: 748.0 / 960.0),
        screenCornerRadiusNormalized: 12.0 / 1440.0,
        colors: [
            DeviceColor(id: "space-black", name: "Space Black", imageName: "", swatchHex: "#303034"),
            DeviceColor(id: "silver", name: "Silver", imageName: "", swatchHex: "#D8D8D2")
        ],
        kind: .drawn,
        style: .laptop,
        symbol: "laptopcomputer"
    )

    static let iPhone15Pro = DeviceModel(
        id: "iphone-15-pro",
        displayName: "iPhone 15 Pro",
        frameAspectRatio: pro15Geometry.aspect,
        screenRectNormalized: pro15Geometry.screenRect,
        screenCornerRadiusNormalized: pro15Geometry.cornerRadius,
        colors: [
            DeviceColor(id: "natural-titanium", name: "Natural Titanium",
                        imageName: "iPhone 15 Pro - Natural Titanium", swatchHex: "#8B8378"),
            DeviceColor(id: "black-titanium",   name: "Black Titanium",
                        imageName: "iPhone 15 Pro - Black Titanium",   swatchHex: "#3A3A3C"),
            DeviceColor(id: "white-titanium",   name: "White Titanium",
                        imageName: "iPhone 15 Pro - White Titanium",   swatchHex: "#E3E0DA")
        ],
        kind: .physical,
        style: .modernPhone,
        symbol: "iphone"
    )

    static let iPhone16Pro = DeviceModel(
        id: "iphone-16-pro",
        displayName: "iPhone 16 Pro",
        frameAspectRatio: pro16_17Geometry.aspect,
        screenRectNormalized: pro16_17Geometry.screenRect,
        screenCornerRadiusNormalized: pro16_17Geometry.cornerRadius,
        colors: [
            DeviceColor(id: "natural-titanium", name: "Natural Titanium",
                        imageName: "iPhone 16 Pro - Natural Titanium ", swatchHex: "#BFB4A1"),
            DeviceColor(id: "black-titanium",   name: "Black Titanium",
                        imageName: "iPhone 16 Pro - Black Titanium",    swatchHex: "#3A3A3C"),
            DeviceColor(id: "white-titanium",   name: "White Titanium",
                        imageName: "iPhone 16 Pro - White Titanium",    swatchHex: "#E3E0DA"),
            DeviceColor(id: "gold-titanium",    name: "Desert Titanium",
                        imageName: "iPhone 16 Pro - Gold Titanium",     swatchHex: "#C9A77F")
        ],
        kind: .physical,
        style: .modernPhone,
        symbol: "iphone"
    )

    static let iPhone17Pro = DeviceModel(
        id: "iphone-17-pro",
        displayName: "iPhone 17 Pro",
        frameAspectRatio: pro16_17Geometry.aspect,
        screenRectNormalized: pro16_17Geometry.screenRect,
        screenCornerRadiusNormalized: pro16_17Geometry.cornerRadius,
        colors: [
            DeviceColor(id: "cosmic-orange", name: "Cosmic Orange",
                        imageName: "iPhone 17 Pro - Cosmic Orange", swatchHex: "#E96A2C"),
            DeviceColor(id: "deep-blue",     name: "Deep Blue",
                        imageName: "iPhone 17 Pro - Deep Blue",     swatchHex: "#3F5476"),
            DeviceColor(id: "silver",        name: "Silver",
                        imageName: "iPhone 17 Pro - Silver",        swatchHex: "#C9CCD0")
        ],
        kind: .physical,
        style: .modernPhone,
        symbol: "iphone"
    )

    static let all: [DeviceModel] = [
        .none,
        .generic,
        .iPhone17Pro,
        .iPhone16Pro,
        .iPhone15Pro,
        .classicPhone,
        .androidPhone,
        .tablet,
        .laptop
    ]

    static func model(id: String) -> DeviceModel? {
        all.first { $0.id == id }
    }
}

struct DeviceFrame: Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let imageName: String
    let frameAspectRatio: CGFloat
    let screenRectNormalized: CGRect
    let screenCornerRadiusNormalized: CGFloat
    let kind: DeviceFrameKind
    let style: DeviceFrameStyle

    static let iPhone15Pro = DeviceModel.iPhone15Pro.frame(for: DeviceModel.iPhone15Pro.defaultColor)

    func screenRect(in frameSize: CGSize) -> CGRect {
        CGRect(
            x: screenRectNormalized.minX * frameSize.width,
            y: screenRectNormalized.minY * frameSize.height,
            width: screenRectNormalized.width * frameSize.width,
            height: screenRectNormalized.height * frameSize.height
        )
    }

    func screenCornerRadius(in frameSize: CGSize) -> CGFloat {
        screenCornerRadiusNormalized * frameSize.width
    }

    var outerCornerRadiusFraction: CGFloat {
        switch style {
        case .modernPhone:
            return 0.135
        case .classicPhone:
            return 0.11
        case .androidPhone:
            return 0.09
        case .tablet:
            return 0.07
        case .laptop:
            return 0.035
        }
    }
}
