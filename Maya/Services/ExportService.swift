import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import Foundation
import SwiftUI
import VideoToolbox

actor ExportService {
    struct Snapshot: @unchecked Sendable {
        /// Already inside the app's sandbox container — no security-scope dance required.
        let sourceVideoURL: URL
        let deviceFrame: DeviceFrame
        let scale: CGFloat
        let offsetFraction: CGSize
        let background: BackgroundOption
        let blurPosterCG: CGImage?
        let backgroundImageCG: CGImage?
        let frameOverlayCG: CGImage
        let animations: [ZoomSegment]
        let renderSize: CGSize
    }

    func exportWithBackground(
        project: Project,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let snap = try await MainActor.run { try ExportService.snapshot(from: project) }
        try await runWithBackground(snapshot: snap, outputURL: outputURL, progress: progress)
    }

    func exportTransparent(
        project: Project,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let snap = try await MainActor.run { try ExportService.snapshot(from: project) }
        try await runTransparent(snapshot: snap, outputURL: outputURL, progress: progress)
    }

    // MARK: - With background pipeline

    private func runWithBackground(snapshot: Snapshot, outputURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        // Source lives inside our sandbox already — no scope needed there. The save-panel
        // URL still requires scope for the writer to create the destination file.
        let outputAccess = outputURL.startAccessingSecurityScopedResource()
        defer { if outputAccess { outputURL.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: snapshot.sourceVideoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else { throw ExportError.noVideoTrack }
        let duration = try await asset.load(.duration)

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ExportError.cannotBuildComposition }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )

        // Audio passthrough
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let sourceAudio = audioTracks.first,
           let compositionAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudio.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceAudio,
                at: .zero
            )
        }

        let renderSize = snapshot.renderSize
        let frameDuration = try await sourceVideoTrack.load(.minFrameDuration)
        let fps = frameDuration == .invalid || frameDuration.seconds <= 0 ? CMTime(value: 1, timescale: 60) : frameDuration

        let backgroundImage = try buildBackgroundCIImage(snapshot: snapshot, size: renderSize)
        let frameOverlay = CIImage(cgImage: snapshot.frameOverlayCG)

        let instruction = DeviceFrameCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.deviceFrame = snapshot.deviceFrame
        instruction.scale = snapshot.scale
        instruction.offsetFraction = snapshot.offsetFraction
        instruction.sourceTrackID = compositionVideoTrack.trackID
        instruction.backgroundImage = backgroundImage
        instruction.frameOverlay = frameOverlay
        instruction.renderTransparent = false
        instruction.animations = snapshot.animations

        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = fps
        videoComposition.renderSize = renderSize
        videoComposition.customVideoCompositorClass = DeviceFrameCompositor.self
        videoComposition.instructions = [instruction]

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.cannotInitExportSession
        }
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let progressTask = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                progress(Double(session.progress))
                if session.status == .completed || session.status == .failed || session.status == .cancelled {
                    return
                }
            }
        }
        defer { progressTask.cancel() }

        try await session.export(to: outputURL, as: .mp4)
        progress(1.0)
    }

    // MARK: - Transparent pipeline

    private func runTransparent(snapshot: Snapshot, outputURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let outputAccess = outputURL.startAccessingSecurityScopedResource()
        defer { if outputAccess { outputURL.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: snapshot.sourceVideoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else { throw ExportError.noVideoTrack }
        let duration = try await asset.load(.duration)
        let rawFrameDuration = try await sourceVideoTrack.load(.minFrameDuration)
        let frameDuration: CMTime = (rawFrameDuration == .invalid || rawFrameDuration.seconds <= 0)
            ? CMTime(value: 1, timescale: 60)
            : rawFrameDuration

        let renderSize = snapshot.renderSize
        let frameOverlay = CIImage(cgImage: snapshot.frameOverlayCG)

        let instruction = DeviceFrameCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.deviceFrame = snapshot.deviceFrame
        instruction.scale = snapshot.scale
        instruction.offsetFraction = snapshot.offsetFraction
        instruction.sourceTrackID = sourceVideoTrack.trackID
        instruction.backgroundImage = nil
        instruction.frameOverlay = frameOverlay
        instruction.renderTransparent = true
        instruction.animations = snapshot.animations

        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = frameDuration
        videoComposition.renderSize = renderSize
        videoComposition.customVideoCompositorClass = DeviceFrameCompositor.self
        videoComposition.instructions = [instruction]

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = videoComposition
        if reader.canAdd(videoOutput) { reader.add(videoOutput) }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack = audioTracks.first {
            let o = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100
            ])
            if reader.canAdd(o) {
                reader.add(o)
                audioOutput = o
            }
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoCompressionProps: [String: Any] = [
            kVTCompressionPropertyKey_Quality as String: 0.85,
            kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_PremultipliedAlpha
        ]
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: videoCompressionProps
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        if writer.canAdd(videoInput) { writer.add(videoInput) }

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 128_000
            ]
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            a.expectsMediaDataInRealTime = false
            if writer.canAdd(a) {
                writer.add(a)
                audioInput = a
            }
        }

        let pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(renderSize.width),
                kCVPixelBufferHeightKey as String: Int(renderSize.height)
            ]
        )

        guard reader.startReading() else { throw ExportError.readerStartFailed(reader.error) }
        guard writer.startWriting() else { throw ExportError.writerStartFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = duration.seconds

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                try await self.pumpVideo(
                    output: videoOutput,
                    input: videoInput,
                    adaptor: pixelAdaptor,
                    totalSeconds: totalSeconds,
                    progress: progress
                )
            }
            if let ao = audioOutput, let ai = audioInput {
                group.addTask { [self] in
                    try await self.pumpAudio(output: ao, input: ai)
                }
            }
            try await group.waitForAll()
        }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }
        if writer.status == .failed { throw writer.error ?? ExportError.writerFinishFailed }
        progress(1.0)
    }

    private nonisolated func pumpVideo(
        output: AVAssetReaderVideoCompositionOutput,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        totalSeconds: Double,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let queue = DispatchQueue(label: "maya.export.video", qos: .userInitiated)
        let state = ContinuationGuard<Void>()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.continuation = continuation
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        state.finish(.success(()))
                        return
                    }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                    if !adaptor.append(buffer, withPresentationTime: pts) {
                        input.markAsFinished()
                        state.finish(.failure(ExportError.appendFailed))
                        return
                    }
                    if totalSeconds > 0 {
                        let p = pts.seconds / totalSeconds
                        progress(min(max(p, 0), 0.99))
                    }
                }
            }
        }
    }

    private nonisolated func pumpAudio(
        output: AVAssetReaderTrackOutput,
        input: AVAssetWriterInput
    ) async throws {
        let queue = DispatchQueue(label: "maya.export.audio", qos: .userInitiated)
        let state = ContinuationGuard<Void>()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.continuation = continuation
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        state.finish(.success(()))
                        return
                    }
                    if !input.append(sample) {
                        input.markAsFinished()
                        state.finish(.failure(ExportError.appendFailed))
                        return
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func buildBackgroundCIImage(snapshot: Snapshot, size: CGSize) throws -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        switch snapshot.background {
        case .solid(let hex):
            let color = (Color(hex: hex) ?? .black).ciColor
            return CIImage(color: color).cropped(to: rect)
        case .gradient(let spec):
            let filter = CIFilter.linearGradient()
            filter.color0 = spec.startColor.ciColor
            filter.color1 = spec.endColor.ciColor
            let r = spec.angleDegrees * .pi / 180
            let half = max(size.width, size.height)
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            filter.point0 = CGPoint(x: mid.x - cos(r) * half, y: mid.y - sin(r) * half)
            filter.point1 = CGPoint(x: mid.x + cos(r) * half, y: mid.y + sin(r) * half)
            return (filter.outputImage ?? CIImage(color: .black)).cropped(to: rect)
        case .image:
            if let cg = snapshot.backgroundImageCG {
                let img = CIImage(cgImage: cg)
                let s = img.extent.size
                guard s.width > 0, s.height > 0 else { return CIImage(color: .black).cropped(to: rect) }
                let scale = max(size.width / s.width, size.height / s.height)
                var scaled = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                scaled = scaled.transformed(by: CGAffineTransform(
                    translationX: rect.midX - scaled.extent.midX,
                    y: rect.midY - scaled.extent.midY
                ))
                return scaled.cropped(to: rect)
            }
            return CIImage(color: .black).cropped(to: rect)
        case .videoBlur:
            if let cg = snapshot.blurPosterCG {
                let img = CIImage(cgImage: cg)
                let s = img.extent.size
                guard s.width > 0, s.height > 0 else { return CIImage(color: .black).cropped(to: rect) }
                let scale = max(size.width / s.width, size.height / s.height)
                var scaled = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                scaled = scaled.transformed(by: CGAffineTransform(
                    translationX: rect.midX - scaled.extent.midX,
                    y: rect.midY - scaled.extent.midY
                ))
                return scaled.cropped(to: rect)
            }
            return CIImage(color: .black).cropped(to: rect)
        case .none:
            // Should never reach here — transparent path uses renderTransparent flag instead.
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: rect)
        }
    }

    // MARK: - Snapshot builder (MainActor)

    @MainActor
    static func snapshot(from project: Project) throws -> Snapshot {
        guard let url = project.videoURL else { throw ExportError.noSourceVideo }
        guard let overlay = FrameOverlayProvider.cgImage(for: project.deviceFrame) else {
            throw ExportError.missingFrameOverlay
        }
        var backgroundCG: CGImage?
        if case .image(let imageURL) = project.background {
            _ = imageURL.startAccessingSecurityScopedResource()
            defer { imageURL.stopAccessingSecurityScopedResource() }
            if let ns = NSImage(contentsOf: imageURL) {
                var r = NSRect(origin: .zero, size: ns.size)
                backgroundCG = ns.cgImage(forProposedRect: &r, context: nil, hints: nil)
            }
        }
        var blurPosterCG: CGImage?
        if case .videoBlur = project.background {
            blurPosterCG = BlurPosterCache.shared.cachedCGImage(for: url)
        }
        return Snapshot(
            sourceVideoURL: url,
            deviceFrame: project.deviceFrame,
            scale: project.scale,
            offsetFraction: project.offset,
            background: project.background,
            blurPosterCG: blurPosterCG,
            backgroundImageCG: backgroundCG,
            frameOverlayCG: overlay,
            animations: project.animations,
            renderSize: project.canvasAspect.renderSize
        )
    }
}

enum ExportError: LocalizedError {
    case noSourceVideo
    case noVideoTrack
    case cannotBuildComposition
    case cannotInitExportSession
    case missingFrameOverlay
    case readerStartFailed(Error?)
    case writerStartFailed(Error?)
    case writerFinishFailed
    case appendFailed

    var errorDescription: String? {
        switch self {
        case .noSourceVideo: "No source video loaded."
        case .noVideoTrack: "Source file has no video track."
        case .cannotBuildComposition: "Failed to build the AV composition."
        case .cannotInitExportSession: "Could not initialize the export session."
        case .missingFrameOverlay: "Could not produce the iPhone frame overlay."
        case .readerStartFailed(let e): "Reader failed to start: \(e?.localizedDescription ?? "unknown")"
        case .writerStartFailed(let e): "Writer failed to start: \(e?.localizedDescription ?? "unknown")"
        case .writerFinishFailed: "Writer failed to finish."
        case .appendFailed: "Failed to append sample buffer."
        }
    }
}

final class ContinuationGuard<T>: @unchecked Sendable {
    nonisolated(unsafe) var continuation: CheckedContinuation<T, Error>?
    private let lock = NSLock()

    nonisolated init() {}

    nonisolated func finish(_ result: Result<T, Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        guard let c else { return }
        switch result {
        case .success(let v): c.resume(returning: v)
        case .failure(let e): c.resume(throwing: e)
        }
    }
}

@MainActor
enum FrameOverlayProvider {
    static func cgImage(for frame: DeviceFrame) -> CGImage? {
        if let ns = NSImage(named: frame.imageName), ns.size.width > 1 {
            var r = NSRect(origin: .zero, size: ns.size)
            return ns.cgImage(forProposedRect: &r, context: nil, hints: nil)
        }
        // Rasterize placeholder
        let height: CGFloat = 2622
        let width = height * frame.frameAspectRatio
        let renderer = ImageRenderer(content:
            PlaceholderFrameView(frame: frame)
                .frame(width: width, height: height)
        )
        renderer.scale = 1
        return renderer.cgImage
    }
}
