@preconcurrency import AVFoundation
import AppKit
import CoreMedia
import Foundation
import VideoToolbox

@MainActor
final class CarouselExportService {
    private let renderer = CarouselRenderService()

    func exportVideo(
        project: CarouselProject,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let exportCards = project.exportCards
        guard !exportCards.isEmpty else { throw CarouselExportError.noCards }

        let access = outputURL.startAccessingSecurityScopedResource()
        defer { if access { outputURL.stopAccessingSecurityScopedResource() } }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let renderSize = project.canvasAspect.renderSize
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate(for: renderSize),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw CarouselExportError.writerSetupFailed }
        writer.add(input)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(renderSize.width),
                kCVPixelBufferHeightKey as String: Int(renderSize.height)
            ]
        )

        guard writer.startWriting() else { throw CarouselExportError.writerFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 30
        let totalFrames = exportCards.reduce(0) { $0 + max(1, Int((max(0.5, $1.duration) * Double(fps)).rounded())) }
        var frameIndex = 0

        for card in exportCards {
            let framesForCard = max(1, Int((max(0.5, card.duration) * Double(fps)).rounded()))
            for localFrame in 0..<framesForCard {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                let time = Double(localFrame) / Double(fps)
                let cgImage = try renderer.renderCard(card, project: project, time: time, size: renderSize)
                let buffer = try pixelBuffer(from: cgImage, size: renderSize)
                let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
                guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                    throw CarouselExportError.appendFailed
                }
                frameIndex += 1
                progress(Double(frameIndex) / Double(max(totalFrames, 1)))
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }

        if writer.status == .failed {
            throw CarouselExportError.writerFailed(writer.error)
        }
        progress(1)
    }

    func exportImages(project: CarouselProject, to directory: URL) throws -> [URL] {
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        return try renderer.writeStillImages(project: project, to: directory)
    }

    func exportBundle(project: CarouselProject, to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let videoURL = directory.appendingPathComponent("\(safeName(project.title))-video.mp4")
        let imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        try await exportVideo(project: project, to: videoURL, progress: { p in progress(p * 0.72) })
        _ = try exportImages(project: project, to: imagesDirectory)
        progress(0.84)
        try writeJSON(project.brief, to: directory.appendingPathComponent("carousel-brief.json"))
        try writeCopy(project: project, to: directory.appendingPathComponent("copy.txt"))
        try writePlan(project: project, to: directory.appendingPathComponent("carousel-outline.json"))
        try writeSlides(project: project, to: directory.appendingPathComponent("slides.json"))
        try writeBundleReadme(project: project, to: directory.appendingPathComponent("README.txt"))
        progress(1)
    }

    private func pixelBuffer(from image: CGImage, size: CGSize) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw CarouselExportError.pixelBufferFailed
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            throw CarouselExportError.pixelBufferFailed
        }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return pixelBuffer
    }

    private func bitrate(for size: CGSize) -> Int {
        let pixels = size.width * size.height
        if pixels >= 2_000_000 { return 12_000_000 }
        if pixels >= 1_000_000 { return 8_000_000 }
        return 5_000_000
    }

    private func writeCopy(project: CarouselProject, to url: URL) throws {
        let text = project.exportCards.enumerated().map { index, card in
            """
            Card \(index + 1): \(card.displayName)
            Status: \(card.status.label)
            Role: \(card.role)
            Badge: \(card.badge)
            Headline: \(card.headline)
            Subtitle: \(card.subtitle)
            CTA: \(card.cta)
            Visual prompt: \(card.visualPrompt)
            """
        }.joined(separator: "\n\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writePlan(project: CarouselProject, to url: URL) throws {
        if let plan = project.plan {
            let data = try JSONEncoder.pretty.encode(plan)
            try data.write(to: url, options: .atomic)
        } else {
            let fallback = CarouselAIDirectorBridge.fallbackPlan(for: project, warning: nil)
            let data = try JSONEncoder.pretty.encode(fallback)
            try data.write(to: url, options: .atomic)
        }
    }

    private func writeSlides(project: CarouselProject, to url: URL) throws {
        let slides = project.exportCards.enumerated().map { index, card in
            ExportSlide(
                index: index + 1,
                id: card.id,
                displayName: card.displayName,
                role: card.role,
                status: card.status,
                badge: card.badge,
                headline: card.headline,
                subtitle: card.subtitle,
                cta: card.cta,
                visualPrompt: card.visualPrompt,
                rationale: card.rationale,
                duration: card.duration,
                motion: card.motionOverride ?? project.motionPreset
            )
        }
        try writeJSON(slides, to: url)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder.pretty.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func writeBundleReadme(project: CarouselProject, to url: URL) throws {
        let size = project.canvasAspect.renderSize
        let text = """
        Maya AI Studio Carousel Export

        Project: \(project.title)
        Format: \(project.canvasAspect.displayName) (\(Int(size.width))x\(Int(size.height)))
        Cards exported: \(project.exportCards.count)
        Approved slides: \(project.approvedCards.count) of \(project.cards.count)
        Duration: \(String(format: "%.2f", project.totalDuration)) seconds

        Contents:
        - \(safeName(project.title))-video.mp4: motion carousel video
        - images/: still carousel image set
        - copy.txt: card copy for upload workflows
        - carousel-brief.json: source brief and generation setup
        - carousel-outline.json: AI/fallback outline used for this export
        - slides.json: exported slide copy, visual prompts, rationale, and status

        Platform guidance is advisory. Review safe zones and upload previews before publishing ads.
        """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func safeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "carousel" : cleaned
    }
}

private struct ExportSlide: Encodable {
    var index: Int
    var id: UUID
    var displayName: String
    var role: String
    var status: CarouselSlideStatus
    var badge: String
    var headline: String
    var subtitle: String
    var cta: String
    var visualPrompt: String
    var rationale: String
    var duration: Double
    var motion: CarouselMotionPreset
}


enum CarouselExportError: LocalizedError {
    case noCards
    case writerSetupFailed
    case writerFailed(Error?)
    case pixelBufferFailed
    case appendFailed

    var errorDescription: String? {
        switch self {
        case .noCards: "Create an outline or import images before exporting."
        case .writerSetupFailed: "Could not configure the carousel video writer."
        case .writerFailed(let error): "Carousel video export failed: \(error?.localizedDescription ?? "unknown error")"
        case .pixelBufferFailed: "Could not prepare a video frame."
        case .appendFailed: "Could not append a carousel video frame."
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
