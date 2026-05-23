@preconcurrency import AVFoundation
import AppKit
import CoreMedia
import Foundation

final class NarratedImagesExportService {
    private struct UnsafeSendableBox<Value>: @unchecked Sendable {
        let value: Value
    }

    private static let pixelColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let renderer = NarratedImagesRenderService()

    func exportVideo(
        project: NarratedImageProject,
        to outputURL: URL,
        progress: @escaping @Sendable (CarouselExportProgress) -> Void
    ) async throws {
        let scenes = project.scenes
        guard !scenes.isEmpty else { throw NarratedImagesExportError.noScenes }

        let access = outputURL.startAccessingSecurityScopedResource()
        defer { if access { outputURL.stopAccessingSecurityScopedResource() } }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        progress(.init(phase: .preparing, progress: 0, detail: outputURL.lastPathComponent))
        let renderSize = project.canvasAspect.renderSize(for: project.exportQuality)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate(for: renderSize),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw NarratedImagesExportError.writerSetupFailed }
        writer.add(videoInput)

        let audioReader = try await makeNarrationReader(for: project)
        if let audioReader {
            guard writer.canAdd(audioReader.input) else { throw NarratedImagesExportError.writerSetupFailed }
            writer.add(audioReader.input)
        }

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(renderSize.width),
                kCVPixelBufferHeightKey as String: Int(renderSize.height)
            ]
        )

        guard writer.startWriting() else { throw NarratedImagesExportError.writerFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        let fps = project.exportQuality.fps
        let totalFrames = scenes.reduce(0) { $0 + max(1, Int((max(0.5, $1.duration) * Double(fps)).rounded())) }
        if let audioReader {
            guard audioReader.reader.startReading() else {
                throw NarratedImagesExportError.writerFailed(audioReader.reader.error)
            }
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { [self] in
                    try await self.pumpVideo(
                        scenes: scenes,
                        project: project,
                        renderSize: renderSize,
                        fps: fps,
                        totalFrames: totalFrames,
                        input: videoInput,
                        adaptor: adaptor,
                        progress: { value in
                            progress(.init(phase: .renderingFrames, progress: value * 0.9, detail: "Rendering narrated image frames"))
                        }
                    )
                }
                group.addTask { [self] in
                    try await self.pumpAudio(output: audioReader.output, input: audioReader.input)
                }
                for _ in 0..<2 {
                    try await group.next()
                }
                group.cancelAll()
            }
        } else {
            try await pumpVideo(
                scenes: scenes,
                project: project,
                renderSize: renderSize,
                fps: fps,
                totalFrames: totalFrames,
                input: videoInput,
                adaptor: adaptor,
                progress: { value in
                    progress(.init(phase: .renderingFrames, progress: value * 0.9, detail: "Rendering narrated image frames"))
                }
            )
        }

        progress(.init(phase: .finalizing, progress: 0.95, detail: "Finalizing \(outputURL.lastPathComponent)"))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status == .failed {
            throw NarratedImagesExportError.writerFailed(writer.error)
        }
        progress(.init(phase: .complete, progress: 1, detail: "Export complete"))
    }

    private func pumpVideo(
        scenes: [NarratedImageScene],
        project: NarratedImageProject,
        renderSize: CGSize,
        fps: Int32,
        totalFrames: Int,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let queue = DispatchQueue(label: "maya.narrated-images-export.video", qos: .userInitiated)
        let state = ContinuationGuard<Void>()
        let inputBox = UnsafeSendableBox(value: input)
        let adaptorBox = UnsafeSendableBox(value: adaptor)
        let imageCache = await preloadedImages(for: scenes, renderSize: renderSize)
        let progressInterval = max(1, Int(fps) / 2)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.continuation = continuation
            var frameIndex = 0
            var sceneIndex = 0
            var localFrame = 0
            var staticFrameCache: [UUID: CGImage] = [:]
            inputBox.value.requestMediaDataWhenReady(on: queue) { [self] in
                let input = inputBox.value
                let adaptor = adaptorBox.value
                do {
                    while input.isReadyForMoreMediaData {
                        if Task.isCancelled {
                            input.markAsFinished()
                            state.finish(.failure(CancellationError()))
                            return
                        }
                        guard sceneIndex < scenes.count else {
                            input.markAsFinished()
                            state.finish(.success(()))
                            return
                        }

                        let scene = scenes[sceneIndex]
                        let framesForScene = max(1, Int((max(0.5, scene.duration) * Double(fps)).rounded()))
                        let time = Double(localFrame) / Double(fps)
                        let cgImage: CGImage
                        if self.usesStaticFrame(for: scene),
                           let cached = staticFrameCache[scene.id] {
                            cgImage = cached
                        } else {
                            cgImage = try self.renderer.renderScene(
                                scene,
                                project: project,
                                time: time,
                                size: renderSize,
                                sourceImage: imageCache[scene.id]
                            )
                            if self.usesStaticFrame(for: scene) {
                                staticFrameCache[scene.id] = cgImage
                            }
                        }
                        let buffer = try self.pixelBuffer(from: cgImage, size: renderSize, pool: adaptor.pixelBufferPool)
                        let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
                        guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                            throw NarratedImagesExportError.appendFailed
                        }

                        frameIndex += 1
                        localFrame += 1
                        if frameIndex == totalFrames || frameIndex.isMultiple(of: progressInterval) {
                            progress(Double(frameIndex) / Double(max(totalFrames, 1)))
                        }
                        if localFrame >= framesForScene {
                            sceneIndex += 1
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

    private func usesStaticFrame(for scene: NarratedImageScene) -> Bool {
        let hasChangingCaptions = scene.captionBeats.count > 1
        return scene.motionPreset == .still && !hasChangingCaptions
    }

    private func preloadedImages(for scenes: [NarratedImageScene], renderSize: CGSize) async -> [UUID: CGImage] {
        let maxPixelSize = Int(max(renderSize.width, renderSize.height) * 1.35)
        return await withTaskGroup(of: (UUID, CGImage?).self, returning: [UUID: CGImage].self) { group in
            for scene in scenes {
                let id = scene.id
                guard let imageURL = scene.imageURL else { continue }
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

    private func makeNarrationReader(
        for project: NarratedImageProject
    ) async throws -> (reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)? {
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NarratedImagesExportError.writerSetupFailed
        }

        var cursor = CMTime.zero
        var insertedAudio = false
        for scene in project.scenes {
            let sceneDuration = CMTime(seconds: max(0.5, scene.duration), preferredTimescale: 600)
            defer { cursor = cursor + sceneDuration }
            guard let audioURL = scene.narrationAudioURL else { continue }

            let asset = AVURLAsset(url: audioURL)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let audioDuration = try await asset.load(.duration)
            let insertDuration = CMTimeMinimum(audioDuration, sceneDuration)
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
        reader.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: project.totalDuration, preferredTimescale: 600)
        )
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

    private func pumpAudio(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput) async throws {
        let queue = DispatchQueue(label: "maya.narrated-images-export.audio", qos: .userInitiated)
        let state = ContinuationGuard<Void>()
        let outputBox = UnsafeSendableBox(value: output)
        let inputBox = UnsafeSendableBox(value: input)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.continuation = continuation
            inputBox.value.requestMediaDataWhenReady(on: queue) {
                let output = outputBox.value
                let input = inputBox.value
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        state.finish(.success(()))
                        return
                    }
                    guard input.append(sample) else {
                        input.markAsFinished()
                        state.finish(.failure(NarratedImagesExportError.appendFailed))
                        return
                    }
                }
            }
        }
    }

    private func pixelBuffer(from image: CGImage, size: CGSize, pool: CVPixelBufferPool?) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status: CVReturn
        if let pool {
            status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        } else {
            status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(size.width),
                Int(size.height),
                kCVPixelFormatType_32ARGB,
                [
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
                ] as CFDictionary,
                &pixelBuffer
            )
        }
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NarratedImagesExportError.pixelBufferFailed
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: Self.pixelColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            throw NarratedImagesExportError.pixelBufferFailed
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
}

enum NarratedImagesExportError: LocalizedError {
    case noScenes
    case writerSetupFailed
    case writerFailed(Error?)
    case pixelBufferFailed
    case appendFailed

    var errorDescription: String? {
        switch self {
        case .noScenes: "Import at least one image before exporting."
        case .writerSetupFailed: "Could not configure the narrated images video writer."
        case .writerFailed(let error): "Narrated images export failed: \(error?.localizedDescription ?? "unknown error")"
        case .pixelBufferFailed: "Could not prepare a video frame."
        case .appendFailed: "Could not append a narrated images sample."
        }
    }
}
