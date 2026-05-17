import AppKit
import SwiftUI

extension GradientSpec {
    var startUnitPoint: UnitPoint {
        let r = angleDegrees * .pi / 180
        return UnitPoint(x: 0.5 - cos(r) * 0.5, y: 0.5 - sin(r) * 0.5)
    }
    var endUnitPoint: UnitPoint {
        let r = angleDegrees * .pi / 180
        return UnitPoint(x: 0.5 + cos(r) * 0.5, y: 0.5 + sin(r) * 0.5)
    }
}

struct BackgroundView: View {
    let background: BackgroundOption
    let blurPoster: NSImage?

    var body: some View {
        switch background {
        case .none:
            TransparencyCheckerboard()
        case .solid(let hex):
            (Color(hex: hex) ?? .black)
                .ignoresSafeArea()
        case .gradient(let spec):
            LinearGradient(
                colors: [spec.startColor, spec.endColor],
                startPoint: spec.startUnitPoint,
                endPoint: spec.endUnitPoint
            )
        case .image(let url):
            BackgroundImageView(url: url)
        case .videoBlur:
            if let poster = blurPoster {
                Image(nsImage: poster)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
    }
}

/// Photoshop-style checkered pattern that signals "this area will be transparent in the export".
struct TransparencyCheckerboard: View {
    var cellSize: CGFloat = 16

    var body: some View {
        Canvas { ctx, size in
            let cols = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))
            for r in 0..<rows {
                for c in 0..<cols {
                    let color: Color = (r + c) % 2 == 0
                        ? Color(white: 0.92)
                        : Color(white: 0.78)
                    let rect = CGRect(
                        x: CGFloat(c) * cellSize,
                        y: CGFloat(r) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}

private struct BackgroundImageView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
        .task(id: url) {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            let loaded = NSImage(contentsOf: url)
            await MainActor.run { self.image = loaded }
        }
    }
}
