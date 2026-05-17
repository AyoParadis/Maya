import CoreGraphics
import Foundation

/// Drop shadow cast by the framed phone onto the canvas background. Values are
/// expressed in canvas points and translated to render pixels in the compositor.
struct PhoneShadow: Hashable, Sendable {
    var enabled: Bool = true
    var colorHex: String = "#000000"
    /// Gaussian blur radius. Same scale as SwiftUI's `.shadow(radius:)` and
    /// CoreImage's `CIGaussianBlur.inputRadius`.
    var radius: CGFloat = 28
    /// Positive Y moves the shadow downward (SwiftUI convention).
    var offsetY: CGFloat = 14
    var offsetX: CGFloat = 0
    /// 0…1. Multiplied into the silhouette's alpha.
    var opacity: Double = 0.35

    static let radiusRange: ClosedRange<CGFloat> = 0...100
    static let offsetXRange: ClosedRange<CGFloat> = -50...50
    static let offsetYRange: ClosedRange<CGFloat> = -40...80
    static let opacityRange: ClosedRange<Double> = 0...1
}
