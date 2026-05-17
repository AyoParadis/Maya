import AVFoundation
import AppKit
import CoreGraphics
import Foundation

actor VideoThumbnailGenerator {
    static let shared = VideoThumbnailGenerator()

    struct CacheKey: Hashable {
        let url: URL
        let count: Int
        let height: CGFloat
    }

    private var cache: [CacheKey: [NSImage]] = [:]
    private var inflight: [CacheKey: Task<[NSImage], Never>] = [:]

    func thumbnails(for url: URL, count: Int, height: CGFloat) async -> [NSImage] {
        let key = CacheKey(url: url, count: count, height: height)
        if let hit = cache[key] { return hit }
        if let task = inflight[key] { return await task.value }

        let task = Task.detached(priority: .utility) {
            await VideoThumbnailGenerator.shared.generate(key: key)
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        cache[key] = result
        return result
    }

    private func generate(key: CacheKey) async -> [NSImage] {
        _ = key.url.startAccessingSecurityScopedResource()
        defer { key.url.stopAccessingSecurityScopedResource() }

        let asset = AVURLAsset(url: key.url)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: key.height * 2, height: key.height * 2)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let times: [NSValue] = (0..<key.count).map { i in
            let frac = Double(i) / Double(max(key.count - 1, 1))
            let seconds = frac * duration.seconds
            return NSValue(time: CMTime(seconds: seconds, preferredTimescale: 600))
        }

        return await withCheckedContinuation { continuation in
            var results: [Int: NSImage] = [:]
            var completed = 0
            let total = times.count
            generator.generateCGImagesAsynchronously(forTimes: times) { requested, cgImage, _, _, _ in
                let idx = times.firstIndex(where: { $0.timeValue == requested }) ?? 0
                if let cg = cgImage {
                    let size = NSSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
                    results[idx] = NSImage(cgImage: cg, size: size)
                }
                completed += 1
                if completed == total {
                    let ordered = (0..<total).compactMap { results[$0] }
                    continuation.resume(returning: ordered)
                }
            }
        }
    }
}
