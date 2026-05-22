import CoreGraphics
import Foundation

enum CanvasAspectRatio: String, CaseIterable, Identifiable, Hashable, Sendable {
    case square      // 1:1
    case vertical9x16
    case appStoreIPhone
    case appStoreIPad
    case vertical4x5
    case landscape4x3
    case landscape16x9

    var id: String { rawValue }

    /// width / height
    var ratio: CGFloat {
        switch self {
        case .square:        return 1.0
        case .vertical9x16:  return 9.0 / 16.0
        case .appStoreIPhone:return 1242.0 / 2688.0
        case .appStoreIPad:  return 2064.0 / 2752.0
        case .vertical4x5:   return 4.0 / 5.0
        case .landscape4x3:  return 4.0 / 3.0
        case .landscape16x9: return 16.0 / 9.0
        }
    }

    var displayName: String {
        switch self {
        case .square:        return "Square"
        case .vertical9x16:  return "Reels / Story"
        case .appStoreIPhone:return "App Store iPhone"
        case .appStoreIPad:  return "App Store iPad"
        case .vertical4x5:   return "Portrait"
        case .landscape4x3:  return "Landscape"
        case .landscape16x9: return "YouTube / Widescreen"
        }
    }

    var shortLabel: String {
        switch self {
        case .square:        return "1:1"
        case .vertical9x16:  return "9:16"
        case .appStoreIPhone:return "1242x2688"
        case .appStoreIPad:  return "2064x2752"
        case .vertical4x5:   return "4:5"
        case .landscape4x3:  return "4:3"
        case .landscape16x9: return "16:9"
        }
    }

    /// Pixel dimensions used by the export pipeline. Short side stays at 1080
    /// for Reels/Shorts parity; landscape variants keep 1080 tall so HD
    /// (1920×1080) is the default for 16:9.
    var renderSize: CGSize {
        switch self {
        case .square:        return CGSize(width: 1080, height: 1080)
        case .vertical9x16:  return CGSize(width: 1080, height: 1920)
        case .appStoreIPhone:return CGSize(width: 1242, height: 2688)
        case .appStoreIPad:  return CGSize(width: 2064, height: 2752)
        case .vertical4x5:   return CGSize(width: 1080, height: 1350)
        case .landscape4x3:  return CGSize(width: 1440, height: 1080)
        case .landscape16x9: return CGSize(width: 1920, height: 1080)
        }
    }

    func renderSize(for quality: CarouselExportQuality) -> CGSize {
        let full = renderSize
        let longEdge = max(full.width, full.height)
        guard longEdge > quality.maxLongEdge else { return full }
        let scale = quality.maxLongEdge / longEdge
        let width = max(2, (full.width * scale).rounded(.toNearestOrEven))
        let height = max(2, (full.height * scale).rounded(.toNearestOrEven))
        return CGSize(width: width, height: height)
    }

    /// SF Symbol matching the aspect — for the sidebar picker chips.
    var symbol: String {
        switch self {
        case .square:        return "square"
        case .vertical9x16:  return "rectangle.portrait"
        case .appStoreIPhone:return "iphone"
        case .appStoreIPad:  return "ipad"
        case .vertical4x5:   return "rectangle.portrait"
        case .landscape4x3:  return "rectangle"
        case .landscape16x9: return "rectangle"
        }
    }
}
