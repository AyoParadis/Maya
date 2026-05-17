import CoreGraphics
import Foundation

struct DeviceFrame: Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let imageName: String
    let frameAspectRatio: CGFloat
    let screenRectNormalized: CGRect
    let screenCornerRadiusNormalized: CGFloat

    static let iPhone15Pro = DeviceFrame(
        id: "iphone-15-pro",
        displayName: "iPhone 15 Pro",
        imageName: "iPhone 15 Pro",
        frameAspectRatio: 450.0 / 920.0,
        screenRectNormalized: CGRect(
            x: 24.0 / 450.0,
            y: 23.0 / 920.0,
            width: 402.0 / 450.0,
            height: 874.0 / 920.0
        ),
        screenCornerRadiusNormalized: 60.0 / 450.0
    )

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
}
