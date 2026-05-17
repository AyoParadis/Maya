import CoreGraphics
import Foundation

enum CanvasAspectRatio: String, CaseIterable, Identifiable, Hashable, Sendable {
    case square      // 1:1
    case vertical9x16
    case vertical4x5
    case landscape4x3

    var id: String { rawValue }

    /// width / height
    var ratio: CGFloat {
        switch self {
        case .square:        return 1.0
        case .vertical9x16:  return 9.0 / 16.0
        case .vertical4x5:   return 4.0 / 5.0
        case .landscape4x3:  return 4.0 / 3.0
        }
    }

    var displayName: String {
        switch self {
        case .square:        return "Square"
        case .vertical9x16:  return "Reels / Story"
        case .vertical4x5:   return "Portrait"
        case .landscape4x3:  return "Landscape"
        }
    }

    var shortLabel: String {
        switch self {
        case .square:        return "1:1"
        case .vertical9x16:  return "9:16"
        case .vertical4x5:   return "4:5"
        case .landscape4x3:  return "4:3"
        }
    }

    /// Pixel dimensions used by the export pipeline. Sized to keep the short
    /// side at 1080 for Reels/Shorts parity, except 4:3 which keeps 1080 tall.
    var renderSize: CGSize {
        switch self {
        case .square:        return CGSize(width: 1080, height: 1080)
        case .vertical9x16:  return CGSize(width: 1080, height: 1920)
        case .vertical4x5:   return CGSize(width: 1080, height: 1350)
        case .landscape4x3:  return CGSize(width: 1440, height: 1080)
        }
    }

    /// SF Symbol matching the aspect — for the sidebar picker chips.
    var symbol: String {
        switch self {
        case .square:        return "square"
        case .vertical9x16:  return "rectangle.portrait"
        case .vertical4x5:   return "rectangle.portrait"
        case .landscape4x3:  return "rectangle"
        }
    }
}
