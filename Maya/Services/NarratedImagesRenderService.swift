import AppKit
import CoreGraphics
import Foundation

enum NarratedImagesRenderError: LocalizedError {
    case cannotCreateContext
    case cannotCreateFrame

    var errorDescription: String? {
        switch self {
        case .cannotCreateContext: "Could not create the narrated image render context."
        case .cannotCreateFrame: "Could not render a narrated image frame."
        }
    }
}

struct NarratedImagesRenderService {
    private static let renderColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    func renderScene(
        _ scene: NarratedImageScene,
        project: NarratedImageProject,
        time: Double = 0,
        size: CGSize? = nil,
        sourceImage: CGImage? = nil
    ) throws -> CGImage {
        let renderSize = size ?? project.canvasAspect.renderSize
        guard let context = CGContext(
            data: nil,
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: Self.renderColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NarratedImagesRenderError.cannotCreateContext
        }

        let rect = CGRect(origin: .zero, size: renderSize)
        context.setFillColor(NSColor(calibratedWhite: 0.04, alpha: 1).cgColor)
        context.fill(rect)

        let source = sourceImage ?? scene.imageURL.flatMap { NSImage(contentsOf: $0) }?.cgImageForRendering
        if let source {
            drawImage(source, scene: scene, time: time, in: rect, context: context)
        }
        drawVignette(in: rect, context: context)
        drawCaption(scene: scene, project: project, time: time, in: rect, context: context)

        guard let frame = context.makeImage() else {
            throw NarratedImagesRenderError.cannotCreateFrame
        }
        return frame
    }

    private func drawImage(_ image: CGImage, scene: NarratedImageScene, time: Double, in rect: CGRect, context: CGContext) {
        let progress = max(0, min(1, time / max(0.5, scene.duration)))
        let eased = 0.5 - cos(progress * .pi) * 0.5
        let motionScale: CGFloat
        let pan: CGPoint
        switch scene.motionPreset {
        case .still:
            motionScale = 1
            pan = .zero
        case .subtleZoom, .auto:
            motionScale = 1 + CGFloat(eased) * 0.06
            pan = .zero
        case .punchZoom:
            motionScale = 1 + CGFloat(eased) * 0.12
            pan = .zero
        case .pan:
            motionScale = 1.06
            pan = CGPoint(x: CGFloat(eased - 0.5) * rect.width * 0.07, y: 0)
        }

        let sourceSize = CGSize(width: image.width, height: image.height)
        let baseScale = max(rect.width / sourceSize.width, rect.height / sourceSize.height) * motionScale
        let drawSize = CGSize(width: sourceSize.width * baseScale, height: sourceSize.height * baseScale)
        let origin = CGPoint(
            x: rect.midX - drawSize.width / 2 + pan.x,
            y: rect.midY - drawSize.height / 2 + pan.y
        )

        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: origin, size: drawSize))
        context.restoreGState()
    }

    private func drawVignette(in rect: CGRect, context: CGContext) {
        guard let gradient = CGGradient(
            colorsSpace: Self.renderColorSpace,
            colors: [
                NSColor.black.withAlphaComponent(0.0).cgColor,
                NSColor.black.withAlphaComponent(0.34).cgColor
            ] as CFArray,
            locations: [0.42, 1.0]
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.midY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
    }

    private func drawCaption(scene: NarratedImageScene, project: NarratedImageProject, time: Double, in rect: CGRect, context: CGContext) {
        guard let beat = project.activeCaption(for: scene, at: time) else { return }
        let text = beat.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !text.isEmpty else { return }

        let maxWidth = rect.width * max(0.38, min(0.96, scene.captionBoxWidth))
        let fontSize = captionFontSize(for: text, scene: scene, style: beat.style, rect: rect)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = max(1, fontSize * 0.04)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: captionFont(for: scene, size: fontSize),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black.withAlphaComponent(0.82),
            .strokeWidth: -4.2,
            .paragraphStyle: paragraph,
            .kern: 0.3
        ]
        let string = NSString(string: text)
        let used = string.boundingRect(
            with: CGSize(width: maxWidth, height: rect.height * 0.42),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let center = CGPoint(
            x: rect.width * max(0.08, min(0.92, scene.captionAnchor.x)),
            y: rect.height * max(0.08, min(0.92, scene.captionAnchor.y))
        )
        let drawRect = CGRect(
            x: center.x - maxWidth / 2,
            y: center.y - used.height / 2,
            width: maxWidth,
            height: min(rect.height * 0.42, used.height + fontSize * 0.35)
        )

        context.saveGState()
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        string.draw(
            with: drawRect.offsetBy(dx: 0, dy: 4),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: shadowAttributes(from: attrs)
        )
        string.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        context.restoreGState()
    }

    private func captionFontSize(for text: String, scene: NarratedImageScene, style: NarratedCaptionStyle, rect: CGRect) -> CGFloat {
        let scale = CGFloat(max(0.72, min(1.45, scene.captionFontScale)))
        let base = rect.width * (style == .softSubtitle ? 0.07 : 0.105) * scale
        if text.count <= 8 { return min(rect.width * 0.15, base * 1.16) }
        if text.count >= 24 { return max(32, base * 0.72) }
        return max(34, base)
    }

    private func captionFont(for scene: NarratedImageScene, size: CGFloat) -> NSFont {
        guard let family = scene.captionFontFamily, !family.isEmpty else {
            return NSFont.systemFont(ofSize: size, weight: .black)
        }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
            .withSymbolicTraits(.bold)
        return NSFont(descriptor: descriptor, size: size) ?? NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size, weight: .black)
    }

    private func shadowAttributes(from attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var shadow = attrs
        shadow[.foregroundColor] = NSColor.black.withAlphaComponent(0.45)
        shadow[.strokeWidth] = 0
        return shadow
    }
}
