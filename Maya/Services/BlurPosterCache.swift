import AVFoundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

actor BlurPosterCache {
    static let shared = BlurPosterCache()

    private var cache: [URL: CGImage] = [:]
    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    func poster(for url: URL) async -> NSImage? {
        let cg = await cgImage(for: url)
        guard let cg else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func cgImage(for url: URL) async -> CGImage? {
        if let cached = cache[url] { return cached }
        let result = await generate(for: url)
        if let result { cache[url] = result }
        return result
    }

    nonisolated func cachedCGImage(for url: URL) -> CGImage? {
        // Synchronous best-effort fetch. The actor lookup is async; for the export snapshot we
        // accept that the cache may not be primed yet — caller can call cgImage(for:) ahead of time.
        return UnsafeCacheBridge.shared.value(for: url)
    }

    private func generate(for url: URL) async -> CGImage? {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        let time: CMTime
        if let duration = try? await asset.load(.duration), duration.seconds > 0.5 {
            time = CMTime(seconds: min(0.5, duration.seconds / 2), preferredTimescale: 600)
        } else {
            time = .zero
        }

        let sample: CGImage? = await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, _, _ in
                continuation.resume(returning: image)
            }
        }
        guard let cg = sample else { return nil }

        let source = CIImage(cgImage: cg)

        // Downsample, blur, upscale — much cheaper than full-res blur.
        let downscale = 0.15
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = source
        lanczos.scale = Float(downscale)
        lanczos.aspectRatio = 1
        guard let small = lanczos.outputImage else { return nil }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = small
        blur.radius = 30
        guard let blurred = blur.outputImage?.cropped(to: small.extent) else { return nil }

        let upscale = CIFilter.lanczosScaleTransform()
        upscale.inputImage = blurred
        upscale.scale = Float(1.0 / downscale)
        upscale.aspectRatio = 1
        guard let big = upscale.outputImage?.cropped(to: source.extent) else { return nil }

        // Slight tint darken so phones don't disappear into the background.
        let darken = CIFilter.colorControls()
        darken.inputImage = big
        darken.brightness = -0.1
        darken.saturation = 0.85
        let final = darken.outputImage ?? big

        let result = ciContext.createCGImage(final, from: final.extent)
        if let result {
            UnsafeCacheBridge.shared.set(value: result, for: url)
        }
        return result
    }
}

private final class UnsafeCacheBridge: @unchecked Sendable {
    nonisolated static let shared = UnsafeCacheBridge()
    private let lock = NSLock()
    nonisolated(unsafe) private var storage: [URL: CGImage] = [:]

    nonisolated func value(for url: URL) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return storage[url]
    }

    nonisolated func set(value: CGImage, for url: URL) {
        lock.lock()
        storage[url] = value
        lock.unlock()
    }
}
