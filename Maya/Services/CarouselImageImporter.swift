import Foundation

enum CarouselImageImporter {
    static func adoptIntoSandbox(_ sourceURL: URL) throws -> (sandboxURL: URL, displayName: String) {
        let didStart = sourceURL.startAccessingSecurityScopedResource()
        defer { if didStart { sourceURL.stopAccessingSecurityScopedResource() } }

        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Maya AI Studio", isDirectory: true)
        .appendingPathComponent("Carousel Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let displayName = sourceURL.lastPathComponent
        let destination = base.appendingPathComponent("\(UUID().uuidString)-\(displayName)")
        do {
            try FileManager.default.linkItem(at: sourceURL, to: destination)
        } catch {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }
        return (destination, displayName)
    }
}
