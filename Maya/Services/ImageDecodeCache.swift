@preconcurrency import AppKit
import CoreGraphics
import Foundation
import ImageIO

actor ImageDecodeCache {
    static let shared = ImageDecodeCache()

    struct Key: Hashable {
        let url: URL
        let modifiedAt: TimeInterval
        let maxPixelSize: Int?
    }

    private var cgCache: [Key: CGImage] = [:]
    private var nsCache: [Key: NSImage] = [:]
    private var inflightCG: [Key: Task<CGImage?, Never>] = [:]
    private var inflightNS: [Key: Task<NSImage?, Never>] = [:]
    private var keyOrder: [Key] = []
    private let maxCachedImages = 96

    func cgImage(for url: URL, maxPixelSize: Int? = nil) async -> CGImage? {
        let key = Self.key(for: url, maxPixelSize: maxPixelSize)
        if let cached = cgCache[key] {
            touch(key)
            return cached
        }
        if let task = inflightCG[key] { return await task.value }

        let task = Task.detached(priority: .utility) {
            Self.loadCGImage(from: url, maxPixelSize: maxPixelSize)
        }
        inflightCG[key] = task
        let image = await task.value
        inflightCG[key] = nil
        if let image {
            cgCache[key] = image
            touch(key)
            trimIfNeeded()
        }
        return image
    }

    func nsImage(for url: URL, maxPixelSize: Int? = nil) async -> NSImage? {
        let key = Self.key(for: url, maxPixelSize: maxPixelSize)
        if let cached = nsCache[key] {
            touch(key)
            return cached
        }
        if let task = inflightNS[key] { return await task.value }

        if let cachedCG = cgCache[key] {
            let image = NSImage(cgImage: cachedCG, size: NSSize(width: cachedCG.width, height: cachedCG.height))
            nsCache[key] = image
            touch(key)
            trimIfNeeded()
            return image
        }

        let task: Task<NSImage?, Never> = Task.detached(priority: .utility) {
            guard let cg = Self.loadCGImage(from: url, maxPixelSize: maxPixelSize) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        inflightNS[key] = task
        let image = await task.value
        inflightNS[key] = nil
        if let image {
            nsCache[key] = image
            touch(key)
            trimIfNeeded()
        }
        return image
    }

    private func touch(_ key: Key) {
        keyOrder.removeAll { $0 == key }
        keyOrder.append(key)
    }

    private func trimIfNeeded() {
        while keyOrder.count > maxCachedImages {
            let key = keyOrder.removeFirst()
            cgCache[key] = nil
            nsCache[key] = nil
        }
    }

    nonisolated private static func key(for url: URL, maxPixelSize: Int?) -> Key {
        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        return Key(url: url, modifiedAt: modifiedAt, maxPixelSize: maxPixelSize)
    }

    nonisolated private static func loadCGImage(from url: URL, maxPixelSize: Int?) -> CGImage? {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any]
        if let maxPixelSize, maxPixelSize > 0 {
            options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
        } else {
            options = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }
}
