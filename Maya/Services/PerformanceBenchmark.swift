import AVFoundation
import Foundation
import SwiftUI

enum PerformanceBenchmark {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--maya-performance-benchmark") else { return }
        Task {
            do {
                let report = try await run()
                print(report)
                exit(0)
            } catch {
                fputs("Performance benchmark failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        RunLoop.main.run()
    }

    private static func run() async throws -> String {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MayaPerformanceBenchmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var lines: [String] = [
            "Maya Performance Benchmark",
            "Output: \(outputDirectory.path)"
        ]

        if let videoURL = videoFixtureURL() {
            let thumbnailTimer = WallClockTimer()
            let thumbnails = await VideoThumbnailGenerator.shared.thumbnails(for: videoURL, count: 18, height: 56)
            lines.append("thumbnail_generation_ms=\(thumbnailTimer.elapsedMilliseconds) thumbnails=\(thumbnails.count)")

            let posterTimer = WallClockTimer()
            let poster = await BlurPosterCache.shared.cgImage(for: videoURL)
            lines.append("blur_poster_ms=\(posterTimer.elapsedMilliseconds) generated=\(poster != nil)")

            let project = await MainActor.run {
                let project = Project()
                project.videoURL = videoURL
                project.displayName = videoURL.lastPathComponent
                project.background = .gradient(GradientSpec.presets[0])
                project.canvasAspect = .square
                project.isMuted = true
                return project
            }
            let asset = AVURLAsset(url: videoURL)
            let duration = (try? await asset.load(.duration)) ?? .zero
            let naturalSize = try await asset.loadTracks(withMediaType: .video).first?.load(.naturalSize) ?? .zero
            await MainActor.run {
                project.videoDuration = duration
                project.videoNaturalSize = naturalSize
                project.trimStartTime = 0
                project.trimEndTime = duration.seconds.isFinite ? duration.seconds : 0
            }
            let editorURL = outputDirectory.appendingPathComponent("editor-background.mp4")
            let editorTimer = WallClockTimer()
            try await ExportService().exportWithBackground(project: project, to: editorURL) { _ in }
            lines.append("editor_export_background_ms=\(editorTimer.elapsedMilliseconds) bytes=\(fileSize(editorURL))")
        } else {
            lines.append("video_fixture=missing")
        }

        for quality in [CarouselExportQuality.draft, .standard, .high] {
            let project = carouselFixture(quality: quality)
            let url = outputDirectory.appendingPathComponent("carousel-\(quality.rawValue).mp4")
            let timer = WallClockTimer()
            try await CarouselExportService().exportVideo(project: project, to: url) { _ in }
            lines.append("carousel_\(quality.rawValue)_export_ms=\(timer.elapsedMilliseconds) bytes=\(fileSize(url))")
        }

        let piperRequest = NarrationRequest(engine: .piper, text: NarrationService.previewText, voice: PiperNarrationService.defaultVoice)
        let piperTimer = WallClockTimer()
        if let result = try? await NarrationService.preview(piperRequest) {
            lines.append("piper_preview_ms=\(piperTimer.elapsedMilliseconds) cache=\(result.usedCache)")
        } else {
            lines.append("piper_preview=unavailable")
        }

        for engine in [NarrationEngine.kokoro] {
            let request = NarrationRequest(engine: engine, text: NarrationService.previewText, voice: engine.defaultVoice)
            let timer = WallClockTimer()
            if let result = try? await NarrationService.preview(request) {
                lines.append("\(engine.rawValue)_preview_ms=\(timer.elapsedMilliseconds) cache=\(result.usedCache)")
            } else {
                lines.append("\(engine.rawValue)_preview=unavailable")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func carouselFixture(quality: CarouselExportQuality) -> CarouselProject {
        let cards = (1...5).map { index in
            CarouselCard(
                displayName: "Benchmark \(index)",
                role: "Slide \(index)",
                headline: "Make product videos faster",
                subtitle: "Benchmark slide \(index) checks carousel render throughput with real text drawing.",
                cta: index.isMultiple(of: 2) ? "Try Maya" : "Export now",
                badge: "Benchmark",
                status: .drafted,
                duration: 1.2,
                motionOverride: index.isMultiple(of: 2) ? .still : .subtleZoom
            )
        }
        let project = CarouselProject(title: "Performance Benchmark", cards: cards)
        project.exportQuality = quality
        project.canvasAspect = .square
        project.motionPreset = .subtleZoom
        project.brandHex = "#6466FA"
        return project
    }

    private static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private static func videoFixtureURL() -> URL? {
        if ProcessInfo.processInfo.environment["MAYA_SKIP_HEADLESS_VIDEO_BENCHMARK"] == "1" {
            return nil
        }
        if let url = Bundle.main.url(forResource: "dramatic", withExtension: "mp4", subdirectory: "PresetPreviews") {
            return url
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            root.appendingPathComponent("Maya/Resources/PresetPreviews/dramatic.mp4"),
            root.appendingPathComponent("presets-videos/dramatic.mp4")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
