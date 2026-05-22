import Foundation
import os

enum PerformanceOperation: String, Sendable {
    case appLaunch = "App Launch"
    case videoImport = "Video Import"
    case videoLoad = "Video Load"
    case thumbnailGeneration = "Thumbnail Generation"
    case blurPosterGeneration = "Blur Poster Generation"
    case editorExportBackground = "Editor Export Background"
    case editorExportTransparent = "Editor Export Transparent"
    case carouselExportVideo = "Carousel Export Video"
    case carouselExportImages = "Carousel Export Images"
    case carouselRenderFrame = "Carousel Render Frame"
    case carouselOCR = "Carousel OCR"
    case narrationInstall = "Narration Install"
    case narrationPreview = "Narration Preview"
    case narrationGenerate = "Narration Generate"
    case pythonProcess = "Python Process"

    nonisolated var signpostName: StaticString {
        switch self {
        case .appLaunch: "App Launch"
        case .videoImport: "Video Import"
        case .videoLoad: "Video Load"
        case .thumbnailGeneration: "Thumbnail Generation"
        case .blurPosterGeneration: "Blur Poster Generation"
        case .editorExportBackground: "Editor Export Background"
        case .editorExportTransparent: "Editor Export Transparent"
        case .carouselExportVideo: "Carousel Export Video"
        case .carouselExportImages: "Carousel Export Images"
        case .carouselRenderFrame: "Carousel Render Frame"
        case .carouselOCR: "Carousel OCR"
        case .narrationInstall: "Narration Install"
        case .narrationPreview: "Narration Preview"
        case .narrationGenerate: "Narration Generate"
        case .pythonProcess: "Python Process"
        }
    }
}

enum PerformanceMetrics {
    nonisolated private static let log = OSLog(subsystem: "com.dlmapps.MayaAIStudio", category: "Performance")
    nonisolated private static let logger = Logger(subsystem: "com.dlmapps.MayaAIStudio", category: "Performance")

    @discardableResult
    nonisolated static func begin(_ operation: PerformanceOperation, detail: String = "") -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: operation.signpostName, signpostID: id)
        if detail.isEmpty {
            logger.debug("Started \(operation.rawValue, privacy: .public)")
        } else {
            logger.debug("Started \(operation.rawValue, privacy: .public): \(detail, privacy: .public)")
        }
        return id
    }

    nonisolated static func end(_ operation: PerformanceOperation, id: OSSignpostID, detail: String = "") {
        os_signpost(.end, log: log, name: operation.signpostName, signpostID: id)
        if detail.isEmpty {
            logger.debug("Finished \(operation.rawValue, privacy: .public)")
        } else {
            logger.debug("Finished \(operation.rawValue, privacy: .public): \(detail, privacy: .public)")
        }
    }

    nonisolated static func event(_ operation: PerformanceOperation, detail: String) {
        os_signpost(.event, log: log, name: operation.signpostName)
        logger.debug("\(operation.rawValue, privacy: .public): \(detail, privacy: .public)")
    }

    nonisolated static func measure<T>(
        _ operation: PerformanceOperation,
        detail: String = "",
        _ work: () throws -> T
    ) rethrows -> T {
        let timer = WallClockTimer()
        let id = begin(operation, detail: detail)
        defer {
            end(operation, id: id, detail: "\(timer.elapsedMilliseconds)ms")
        }
        return try work()
    }

    nonisolated static func measure<T>(
        _ operation: PerformanceOperation,
        detail: String = "",
        _ work: () async throws -> T
    ) async rethrows -> T {
        let timer = WallClockTimer()
        let id = begin(operation, detail: detail)
        defer {
            end(operation, id: id, detail: "\(timer.elapsedMilliseconds)ms")
        }
        return try await work()
    }
}

struct WallClockTimer: Sendable {
    private let start = ContinuousClock.now

    nonisolated init() {}

    nonisolated var elapsedMilliseconds: Int {
        let duration = start.duration(to: ContinuousClock.now)
        return Int(Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1_000_000_000_000_000)
    }
}
