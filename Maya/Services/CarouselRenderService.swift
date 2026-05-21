import AppKit
import CoreGraphics
import Foundation

enum CarouselRenderError: LocalizedError {
    case missingImage(URL)
    case cannotCreateContext
    case cannotCreateFrame
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingImage(let url): "Could not load image \(url.lastPathComponent)."
        case .cannotCreateContext: "Could not create the carousel render context."
        case .cannotCreateFrame: "Could not render a carousel frame."
        case .imageEncodingFailed: "Could not encode a carousel image."
        }
    }
}

struct CarouselRenderService {
    func renderCard(
        _ card: CarouselCard,
        project: CarouselProject,
        time: Double = 0,
        size: CGSize? = nil
    ) throws -> CGImage {
        let renderSize = size ?? project.canvasAspect.renderSize
        let source = card.imageURL.flatMap { NSImage(contentsOf: $0) }?.cgImageForRendering

        guard let context = CGContext(
            data: nil,
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CarouselRenderError.cannotCreateContext
        }

        context.setFillColor(NSColor(calibratedWhite: 0.06, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: renderSize))

        let rect = CGRect(origin: .zero, size: renderSize)
        if let source {
            drawImage(source, in: rect, card: card, project: project, time: time, context: context)
        } else {
            drawComposedBackground(in: rect, card: card, project: project, context: context)
        }
        drawVignette(in: rect, context: context)
        drawText(for: card, project: project, in: rect, context: context)

        guard let frame = context.makeImage() else {
            throw CarouselRenderError.cannotCreateFrame
        }
        return frame
    }

    func writeStillImages(project: CarouselProject, to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (index, card) in project.exportCards.enumerated() {
            let image = try renderCard(card, project: project)
            let url = directory.appendingPathComponent(String(format: "%02d-%@.png", index + 1, sanitized(card.displayName)))
            try writePNG(image, to: url)
            urls.append(url)
        }
        return urls
    }

    func writePNG(_ cgImage: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CarouselRenderError.imageEncodingFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private func drawImage(
        _ image: CGImage,
        in rect: CGRect,
        card: CarouselCard,
        project: CarouselProject,
        time: Double,
        context: CGContext
    ) {
        let motion = effectiveMotion(for: card, project: project)
        let progress = max(0, min(1, time / max(0.1, card.duration)))
        let eased = 0.5 - cos(progress * .pi) * 0.5
        let motionScale: CGFloat
        let pan: CGPoint

        switch motion {
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
        let focal = CGPoint(
            x: max(0, min(1, card.focalPoint.x)),
            y: max(0, min(1, card.focalPoint.y))
        )
        var origin = CGPoint(
            x: rect.midX - drawSize.width * focal.x + pan.x,
            y: rect.midY - drawSize.height * (1 - focal.y) + pan.y
        )
        origin.x = min(0, max(rect.width - drawSize.width, origin.x))
        origin.y = min(0, max(rect.height - drawSize.height, origin.y))

        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: origin, size: drawSize))
        context.restoreGState()
    }

    private func drawComposedBackground(in rect: CGRect, card: CarouselCard, project: CarouselProject, context: CGContext) {
        let brandColor = NSColor(hex: project.brandHex) ?? NSColor.systemIndigo
        let blueColor = NSColor(hex: "#377DFF") ?? NSColor.systemBlue
        let colors = [brandColor.withAlphaComponent(0.94).cgColor, blueColor.withAlphaComponent(0.88).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.minX, y: rect.minY),
                end: CGPoint(x: rect.maxX, y: rect.maxY),
                options: []
            )
        }

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.13).cgColor)
        context.setLineWidth(1)
        let step = max(72, rect.width * 0.12)
        var x = -rect.height
        while x < rect.width {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x + rect.height, y: rect.height))
            context.strokePath()
            x += step
        }
    }

    private func drawVignette(in rect: CGRect, context: CGContext) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            NSColor.black.withAlphaComponent(0.0).cgColor,
            NSColor.black.withAlphaComponent(0.38).cgColor
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.45, 1.0]) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.midY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
    }

    private func drawText(for card: CarouselCard, project: CarouselProject, in rect: CGRect, context: CGContext) {
        let margin = max(32, rect.width * 0.065)
        let maxWidth = rect.width - margin * 2
        let brandColor = NSColor(hex: project.brandHex) ?? NSColor.systemIndigo

        context.saveGState()
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)

        if !card.badge.isEmpty {
            let attrs = textAttributes(size: max(16, rect.width * 0.03), weight: .semibold, color: .white)
            drawPill(text: card.badge, at: CGPoint(x: margin, y: margin), attrs: attrs, fill: brandColor.withAlphaComponent(0.92))
        }

        var y = rect.height - margin - max(92, rect.height * 0.18)
        if !card.headline.isEmpty {
            let attrs = textAttributes(size: max(34, rect.width * 0.075), weight: .bold, color: .white)
            y += drawWrapped(card.headline, rect: CGRect(x: margin, y: y, width: maxWidth, height: rect.height * 0.28), attrs: attrs)
        }

        if !card.subtitle.isEmpty {
            let attrs = textAttributes(size: max(18, rect.width * 0.037), weight: .medium, color: NSColor.white.withAlphaComponent(0.88))
            _ = drawWrapped(card.subtitle, rect: CGRect(x: margin, y: y + 12, width: maxWidth, height: rect.height * 0.18), attrs: attrs)
        }

        if !card.cta.isEmpty {
            let attrs = textAttributes(size: max(17, rect.width * 0.034), weight: .bold, color: .white)
            let ctaY = rect.height - margin - 48
            drawPill(text: card.cta, at: CGPoint(x: margin, y: ctaY), attrs: attrs, fill: brandColor)
        }

        context.restoreGState()
    }

    private func drawWrapped(_ text: String, rect: CGRect, attrs: [NSAttributedString.Key: Any]) -> CGFloat {
        let string = NSString(string: text)
        let used = string.boundingRect(
            with: rect.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        string.draw(with: CGRect(origin: rect.origin, size: rect.size), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        return ceil(used.height)
    }

    private func drawPill(text: String, at point: CGPoint, attrs: [NSAttributedString.Key: Any], fill: NSColor) {
        let string = NSString(string: text)
        let size = string.size(withAttributes: attrs)
        let rect = CGRect(x: point.x, y: point.y, width: size.width + 28, height: size.height + 14)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        fill.setFill()
        path.fill()
        string.draw(at: CGPoint(x: point.x + 14, y: point.y + 7), withAttributes: attrs)
    }

    private func textAttributes(size: CGFloat, weight: NSFont.Weight, color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        return [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .kern: 0
        ]
    }

    private func effectiveMotion(for card: CarouselCard, project: CarouselProject) -> CarouselMotionPreset {
        let motion = card.motionOverride ?? project.motionPreset
        if motion == .auto {
            let denseText = [card.headline, card.subtitle, card.cta, card.badge].joined(separator: " ").count > 130
            if denseText { return .still }
            if !card.cta.isEmpty || !card.badge.isEmpty { return .subtleZoom }
            return .pan
        }
        return motion
    }

    private func sanitized(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return name
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .prefix(44)
            .description
    }
}

private extension NSImage {
    var cgImageForRendering: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
