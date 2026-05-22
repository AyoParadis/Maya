@preconcurrency import AVFoundation
import AppKit
import CoreMedia
import Foundation
import VideoToolbox

final class CarouselExportService {
    private struct UnsafeSendableBox<Value>: @unchecked Sendable {
        let value: Value
    }

    private let stallTimeout: TimeInterval = 18
    private let renderer = CarouselRenderService()

    func exportVideo(
        project: CarouselProject,
        to outputURL: URL,
        progress: @escaping @Sendable (CarouselExportProgress) -> Void
    ) async throws {
        let cancellation = CarouselExportCancellation()
        try await withTaskCancellationHandler {
            try await exportVideoCore(project: project, to: outputURL, cancellation: cancellation, progress: progress)
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func exportVideoCore(
        project: CarouselProject,
        to outputURL: URL,
        cancellation: CarouselExportCancellation,
        progress: @escaping @Sendable (CarouselExportProgress) -> Void
    ) async throws {
        try await PerformanceMetrics.measure(.carouselExportVideo, detail: "\(project.exportQuality.label) \(project.exportCards.count) cards") {
            let exportCards = project.exportCards
            guard !exportCards.isEmpty else { throw CarouselExportError.noCards }

            let access = outputURL.startAccessingSecurityScopedResource()
            defer { if access { outputURL.stopAccessingSecurityScopedResource() } }

            progress(.init(phase: .preparing, progress: 0, detail: exportDetail(project: project, outputURL: outputURL)))

            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            let renderSize = project.canvasAspect.renderSize(for: project.exportQuality)
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            cancellation.setWriter(writer, outputURL: outputURL)
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

            let narrationReader = try await makeNarrationReader(
                for: project,
                maxDuration: CMTime(seconds: project.totalDuration, preferredTimescale: 600)
            )
            if let narrationReader {
                guard writer.canAdd(narrationReader.input) else {
                    throw CarouselExportError.writerSetupFailed
                }
                writer.add(narrationReader.input)
            }

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
            try Task.checkCancellation()

            let fps = project.exportQuality.fps
            let totalFrames = exportCards.reduce(0) { $0 + max(1, Int((max(0.5, $1.duration) * Double(fps)).rounded())) }
            let activity = CarouselExportActivity()
            if let narrationReader {
                guard narrationReader.reader.startReading() else {
                    throw CarouselExportError.writerFailed(narrationReader.reader.error)
                }
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { [self] in
                        try await self.pumpVideo(
                            cards: exportCards,
                            project: project,
                            renderSize: renderSize,
                            fps: fps,
                            totalFrames: totalFrames,
                            input: input,
                            adaptor: adaptor,
                            cancellation: cancellation,
                            activity: activity,
                            progress: { value in
                                progress(.init(phase: .renderingFrames, progress: value * 0.9, detail: "Rendering frame output"))
                            }
                        )
                    }
                    group.addTask { [self] in
                        try await self.pumpAudio(
                            output: narrationReader.output,
                            input: narrationReader.input,
                            cancellation: cancellation,
                            activity: activity,
                            label: "Writing narration audio"
                        )
                    }
                    group.addTask {
                        try await self.watchForStall(
                            activity: activity,
                            cancellation: cancellation,
                            phase: .renderingFrames,
                            quality: project.exportQuality,
                            renderSize: renderSize,
                            fps: fps,
                            cardCount: exportCards.count
                        )
                    }
                    for _ in 0..<2 {
                        try await group.next()
                    }
                    group.cancelAll()
                }
            } else {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { [self] in
                        try await self.pumpVideo(
                            cards: exportCards,
                            project: project,
                            renderSize: renderSize,
                            fps: fps,
                            totalFrames: totalFrames,
                            input: input,
                            adaptor: adaptor,
                            cancellation: cancellation,
                            activity: activity,
                            progress: { value in
                                progress(.init(phase: .renderingFrames, progress: value * 0.9, detail: "Rendering frame output"))
                            }
                        )
                    }
                    group.addTask {
                        try await self.watchForStall(
                            activity: activity,
                            cancellation: cancellation,
                            phase: .renderingFrames,
                            quality: project.exportQuality,
                            renderSize: renderSize,
                            fps: fps,
                            cardCount: exportCards.count
                        )
                    }
                    _ = try await group.next()
                    group.cancelAll()
                }
            }

            try Task.checkCancellation()
            try validateWriter(writer)
            progress(.init(phase: .finalizing, progress: 0.95, detail: "Finalizing \(outputURL.lastPathComponent)"))
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writer.finishWriting { continuation.resume() }
            }

            if writer.status == .failed {
                throw CarouselExportError.writerFailed(writer.error)
            }
            if writer.status == .cancelled {
                try? removePartialFile(outputURL)
                throw CancellationError()
            }
            progress(.init(phase: .complete, progress: 1, detail: "Export complete"))
        }
    }

    private func preloadedImages(for cards: [CarouselCard], renderSize: CGSize) async -> [UUID: CGImage] {
        let maxPixelSize = Int(max(renderSize.width, renderSize.height) * 1.35)
        let sources = cards.compactMap { card -> (UUID, URL)? in
            guard let imageURL = card.imageURL else { return nil }
            return (card.id, imageURL)
        }
        return await withTaskGroup(of: (UUID, CGImage?).self, returning: [UUID: CGImage].self) { group in
            for (id, imageURL) in sources {
                group.addTask {
                    let image = await ImageDecodeCache.shared.cgImage(for: imageURL, maxPixelSize: maxPixelSize)
                    return (id, image)
                }
            }

            var images: [UUID: CGImage] = [:]
            for await (id, image) in group {
                if let image { images[id] = image }
            }
            return images
        }
    }

    private func pumpVideo(
        cards: [CarouselCard],
        project: CarouselProject,
        renderSize: CGSize,
        fps: Int32,
        totalFrames: Int,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        cancellation: CarouselExportCancellation,
        activity: CarouselExportActivity,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let queue = DispatchQueue(label: "maya.carousel-export.video", qos: .userInitiated)
        let state = ContinuationGuard<Void>()
        let inputBox = UnsafeSendableBox(value: input)
        let adaptorBox = UnsafeSendableBox(value: adaptor)
        let renderer = self.renderer
        let imageCache = await preloadedImages(for: cards, renderSize: renderSize)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.continuation = continuation
            var frameIndex = 0
            var cardIndex = 0
            var localFrame = 0
            var staticFrameCache: [UUID: CGImage] = [:]

            inputBox.value.requestMediaDataWhenReady(on: queue) {
                let input = inputBox.value
                let adaptor = adaptorBox.value
                do {
                    while input.isReadyForMoreMediaData {
                        if Task.isCancelled || cancellation.isCancelled {
                            input.markAsFinished()
                            state.finish(.failure(CancellationError()))
                            return
                        }

                        guard cardIndex < cards.count else {
                            input.markAsFinished()
                            state.finish(.success(()))
                            return
                        }

                        let card = cards[cardIndex]
                        let framesForCard = max(1, Int((max(0.5, card.duration) * Double(fps)).rounded()))
                        let sourceImage = imageCache[card.id]

                        let cgImage: CGImage
                        if self.usesStaticFrame(for: card, project: project),
                           let cached = staticFrameCache[card.id] {
                            cgImage = cached
                        } else {
                            let time = Double(localFrame) / Double(fps)
                            cgImage = try renderer.renderCard(
                                card,
                                project: project,
                                time: time,
                                size: renderSize,
                                sourceImage: sourceImage
                            )
                            if self.usesStaticFrame(for: card, project: project) {
                                staticFrameCache[card.id] = cgImage
                            }
                        }
                        let buffer = try self.pixelBuffer(from: cgImage, size: renderSize, pool: adaptor.pixelBufferPool)
                        let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
                        guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                            throw CarouselExportError.appendFailed
                        }

                        frameIndex += 1
                        localFrame += 1
                        activity.markProgress("frame \(frameIndex) of \(totalFrames)")
                        if frameIndex == 1 || frameIndex.isMultiple(of: 120) {
                            PerformanceMetrics.event(.carouselRenderFrame, detail: "frame \(frameIndex) of \(totalFrames)")
                        }
                        progress(Double(frameIndex) / Double(max(totalFrames, 1)))

                        if localFrame >= framesForCard {
                            cardIndex += 1
                            localFrame = 0
                        }
                    }
                } catch {
                    input.markAsFinished()
                    state.finish(.failure(error))
                }
            }
        }
    }

    private func usesStaticFrame(for card: CarouselCard, project: CarouselProject) -> Bool {
        let motion = card.motionOverride ?? project.motionPreset
        return motion == .still
    }

    private func makeNarrationReader(
        for project: CarouselProject,
        maxDuration: CMTime
    ) async throws -> (reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)? {
        if project.hasSlideNarration {
            return try await makeSlideNarrationReader(for: project, maxDuration: maxDuration)
        }
        return try await makeSingleNarrationReader(from: project.narrationAudioURL, maxDuration: maxDuration)
    }

    private func makeSingleNarrationReader(
        from url: URL?,
        maxDuration: CMTime
    ) async throws -> (reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)? {
        guard let url else { return nil }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw CarouselExportError.noNarrationAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let assetDuration = try await asset.load(.duration)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTimeMinimum(assetDuration, maxDuration))

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100
        ])
        if reader.canAdd(output) { reader.add(output) }

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128_000
        ])
        input.expectsMediaDataInRealTime = false
        return (reader, output, input)
    }

    private func makeSlideNarrationReader(
        for project: CarouselProject,
        maxDuration: CMTime
    ) async throws -> (reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)? {
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CarouselExportError.writerSetupFailed
        }

        var cursor = CMTime.zero
        var insertedAudio = false
        for card in project.exportCards {
            let cardDuration = CMTime(seconds: max(0.5, card.duration), preferredTimescale: 600)
            defer { cursor = cursor + cardDuration }
            guard let audioURL = card.narrationAudioURL else { continue }

            let asset = AVURLAsset(url: audioURL)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let audioDuration = try await asset.load(.duration)
            let insertDuration = CMTimeMinimum(audioDuration, cardDuration)
            guard insertDuration > .zero else { continue }
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertDuration),
                of: track,
                at: cursor
            )
            insertedAudio = true
        }

        guard insertedAudio else { return nil }
        let reader = try AVAssetReader(asset: composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: maxDuration)

        let output = AVAssetReaderTrackOutput(track: compositionTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100
        ])
        if reader.canAdd(output) { reader.add(output) }

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128_000
        ])
        input.expectsMediaDataInRealTime = false
        return (reader, output, input)
    }

    private func pumpAudio(
        output: AVAssetReaderTrackOutput,
        input: AVAssetWriterInput,
        cancellation: CarouselExportCancellation,
        activity: CarouselExportActivity,
        label: String
    ) async throws {
        let queue = DispatchQueue(label: "maya.carousel-export.audio", qos: .userInitiated)
        let state = ContinuationGuard<Void>()
        let outputBox = UnsafeSendableBox(value: output)
        let inputBox = UnsafeSendableBox(value: input)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.continuation = continuation
            inputBox.value.requestMediaDataWhenReady(on: queue) {
                let output = outputBox.value
                let input = inputBox.value
                while input.isReadyForMoreMediaData {
                    if Task.isCancelled || cancellation.isCancelled {
                        input.markAsFinished()
                        state.finish(.failure(CancellationError()))
                        return
                    }
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        state.finish(.success(()))
                        return
                    }
                    guard input.append(sample) else {
                        input.markAsFinished()
                        state.finish(.failure(CarouselExportError.appendFailed))
                        return
                    }
                    activity.markProgress(label)
                }
            }
        }
    }

    func exportImages(project: CarouselProject, to directory: URL) throws -> [URL] {
        try PerformanceMetrics.measure(.carouselExportImages, detail: "\(project.exportCards.count) cards") {
            let access = directory.startAccessingSecurityScopedResource()
            defer { if access { directory.stopAccessingSecurityScopedResource() } }
            return try renderer.writeStillImages(project: project, to: directory)
        }
    }

    func exportBundle(project: CarouselProject, to directory: URL, progress: @escaping @Sendable (CarouselExportProgress) -> Void) async throws {
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let videoURL = directory.appendingPathComponent("\(safeName(project.title))-video.mp4")
        let imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        try await exportVideo(project: project, to: videoURL, progress: { p in
            progress(.init(phase: p.phase, progress: p.progress * 0.72, detail: p.detail))
        })
        progress(.init(phase: .exportingImages, progress: 0.72, detail: "Exporting still images"))
        _ = try exportImages(project: project, to: imagesDirectory)
        progress(.init(phase: .packaging, progress: 0.84, detail: "Packaging carousel files"))
        try writeJSON(project.brief, to: directory.appendingPathComponent("carousel-brief.json"))
        try writeCopy(project: project, to: directory.appendingPathComponent("copy.txt"))
        try writePlan(project: project, to: directory.appendingPathComponent("carousel-outline.json"))
        try writeSlides(project: project, to: directory.appendingPathComponent("slides.json"))
        try writeBundleReadme(project: project, to: directory.appendingPathComponent("README.txt"))
        progress(.init(phase: .complete, progress: 1, detail: "Export complete"))
    }

    private func pixelBuffer(from image: CGImage, size: CGSize, pool: CVPixelBufferPool?) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status: CVReturn
        if let pool {
            status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(size.width),
                Int(size.height),
                kCVPixelFormatType_32ARGB,
                attrs as CFDictionary,
                &pixelBuffer
            )
        }
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
        if pixels <= 600_000 { return 2_000_000 }
        if pixels >= 2_000_000 { return 12_000_000 }
        if pixels >= 1_000_000 { return 8_000_000 }
        return 5_000_000
    }

    private func validateWriter(_ writer: AVAssetWriter) throws {
        if writer.status == .failed {
            throw CarouselExportError.writerFailed(writer.error)
        }
        if writer.status == .cancelled {
            throw CancellationError()
        }
    }

    private func watchForStall(
        activity: CarouselExportActivity,
        cancellation: CarouselExportCancellation,
        phase: CarouselExportPhase,
        quality: CarouselExportQuality,
        renderSize: CGSize,
        fps: Int32,
        cardCount: Int
    ) async throws {
        while !Task.isCancelled && !cancellation.isCancelled {
            try await Task.sleep(for: .seconds(2))
            let idle = activity.secondsSinceProgress
            guard idle >= stallTimeout else { continue }
            let detail = """
            Carousel export stalled during \(phase.title).
            Last progress: \(activity.lastLabel)
            Preset: \(quality.label)
            Render size: \(Int(renderSize.width))x\(Int(renderSize.height))
            FPS: \(fps)
            Cards: \(cardCount)
            """
            cancellation.cancel()
            throw CarouselExportError.stalled(detail)
        }
    }

    private func exportDetail(project: CarouselProject, outputURL: URL) -> String {
        let size = project.canvasAspect.renderSize(for: project.exportQuality)
        return "\(outputURL.lastPathComponent) · \(project.exportQuality.label) · \(Int(size.width))x\(Int(size.height)) · \(project.exportQuality.fps)fps"
    }

    private func removePartialFile(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
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
        let outline = ExportOutline(
            title: project.title,
            canvasAspect: project.canvasAspect.rawValue,
            exportQuality: project.exportQuality,
            defaultMotion: project.motionPreset,
            duration: project.totalDuration,
            slides: exportSlides(for: project)
        )
        try writeJSON(outline, to: url)
    }

    private func writeSlides(project: CarouselProject, to url: URL) throws {
        try writeJSON(exportSlides(for: project), to: url)
    }

    private func exportSlides(for project: CarouselProject) -> [ExportSlide] {
        project.exportCards.enumerated().map { index, card in
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
                motion: card.motionOverride ?? project.motionPreset,
                voiceoverScript: card.narrationScript,
                voiceoverDuration: card.narrationAudioDuration
            )
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder.pretty.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func writeBundleReadme(project: CarouselProject, to url: URL) throws {
        let size = project.canvasAspect.renderSize(for: project.exportQuality)
        let text = """
        Maya AI Studio Carousel Export

        Project: \(project.title)
        Format: \(project.canvasAspect.displayName) (\(Int(size.width))x\(Int(size.height)))
        Slides exported: \(project.exportCards.count)
        Duration: \(String(format: "%.2f", project.totalDuration)) seconds

        Contents:
        - \(safeName(project.title))-video.mp4: motion carousel video
        - images/: still carousel image set
        - copy.txt: card copy for upload workflows
        - carousel-brief.json: source brief and project setup
        - carousel-outline.json: carousel slide summary and export settings
        - slides.json: exported slide copy, visual prompts, motion, and voiceover data

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

private struct ExportOutline: Encodable {
    var schemaVersion = 1
    var title: String
    var canvasAspect: String
    var exportQuality: CarouselExportQuality
    var defaultMotion: CarouselMotionPreset
    var duration: Double
    var slides: [ExportSlide]
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
    var voiceoverScript: String
    var voiceoverDuration: Double?
}


enum CarouselExportError: LocalizedError {
    case noCards
    case writerSetupFailed
    case writerFailed(Error?)
    case pixelBufferFailed
    case appendFailed
    case noNarrationAudioTrack
    case stalled(String)

    var errorDescription: String? {
        switch self {
        case .noCards: "Create an outline or import images before exporting."
        case .writerSetupFailed: "Could not configure the carousel video writer."
        case .writerFailed(let error): "Carousel video export failed: \(error?.localizedDescription ?? "unknown error")"
        case .pixelBufferFailed: "Could not prepare a video frame."
        case .appendFailed: "Could not append a carousel video frame."
        case .noNarrationAudioTrack: "The generated narration file has no audio track."
        case .stalled(let detail): detail
        }
    }
}

enum CarouselExportPhase: String, Sendable {
    case preparing
    case renderingFrames
    case writingAudio
    case exportingImages
    case packaging
    case finalizing
    case complete

    var title: String {
        switch self {
        case .preparing: "Preparing export"
        case .renderingFrames: "Rendering frames"
        case .writingAudio: "Writing audio"
        case .exportingImages: "Exporting images"
        case .packaging: "Packaging files"
        case .finalizing: "Finalizing video"
        case .complete: "Export complete"
        }
    }
}

struct CarouselExportProgress: Sendable {
    var phase: CarouselExportPhase
    var progress: Double
    var detail: String
}

final class CarouselExportActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var lastProgressDate = Date()
    private var label = "starting export"

    var secondsSinceProgress: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastProgressDate)
    }

    var lastLabel: String {
        lock.lock()
        defer { lock.unlock() }
        return label
    }

    func markProgress(_ label: String) {
        lock.lock()
        lastProgressDate = Date()
        self.label = label
        lock.unlock()
    }
}

final class CarouselExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var writer: AVAssetWriter?
    nonisolated(unsafe) private var outputURL: URL?
    nonisolated(unsafe) private var cancelled = false

    nonisolated init() {}

    nonisolated var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    nonisolated func setWriter(_ writer: AVAssetWriter, outputURL: URL) {
        lock.lock()
        self.writer = writer
        self.outputURL = outputURL
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel {
            writer.cancelWriting()
        }
    }

    nonisolated func cancel() {
        lock.lock()
        cancelled = true
        let writer = writer
        let url = outputURL
        lock.unlock()
        writer?.cancelWriting()
        if let url {
            try? FileManager.default.removeItem(at: url)
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
