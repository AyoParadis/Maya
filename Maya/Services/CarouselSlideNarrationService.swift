import AppKit
import AVFoundation
import CoreImage
import Foundation
import Vision

enum CarouselSlideNarrationService {
    struct Source: Sendable {
        let imageURL: URL?
        let badge: String
        let headline: String
        let subtitle: String
        let cta: String

        @MainActor
        init(card: CarouselCard) {
            self.imageURL = card.imageURL
            self.badge = card.badge
            self.headline = card.headline
            self.subtitle = card.subtitle
            self.cta = card.cta
        }
    }

    struct Result: Sendable {
        let detectedText: String
        let script: String
        let audioURL: URL
        let audioDuration: Double
    }

    nonisolated static func generate(
        from source: Source,
        engine: NarrationEngine,
        voice: String,
        editedScript: String? = nil
    ) async throws -> Result? {
        let detectedText = try await detectedText(for: source)
        let script = cleanedSpokenScript(from: editedScript ?? detectedText)
        guard !script.isEmpty else { return nil }

        let audioURL = try await NarrationService.generate(
            NarrationRequest(engine: engine, text: script, voice: voice)
        )
        let duration = try await audioDuration(for: audioURL)
        return Result(
            detectedText: detectedText,
            script: script,
            audioURL: audioURL,
            audioDuration: duration
        )
    }

    nonisolated static func generateAudio(
        script: String,
        engine: NarrationEngine,
        voice: String
    ) async throws -> (url: URL, duration: Double)? {
        let script = cleanedSpokenScript(from: script)
        guard !script.isEmpty else { return nil }
        let audioURL = try await NarrationService.generate(
            NarrationRequest(engine: engine, text: script, voice: voice)
        )
        let duration = try await audioDuration(for: audioURL)
        return (audioURL, duration)
    }

    nonisolated static func detectedText(for source: Source) async throws -> String {
        let fieldText = [
            source.badge,
            source.headline,
            source.subtitle,
            source.cta
        ]
        .map(cleanLine)
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        if !fieldText.isEmpty {
            return fieldText
        }

        guard let imageURL = source.imageURL else { return "" }
        return try await recognizeText(in: imageURL, useCache: true)
    }

    nonisolated static func redetectImageText(for source: Source) async throws -> String {
        if let imageURL = source.imageURL {
            return try await recognizeText(in: imageURL, useCache: false)
        }
        return try await detectedText(for: source)
    }

    nonisolated static func cleanedSpokenScript(from text: String) -> String {
        spokenScript(from: text)
    }

    nonisolated static func audioDuration(for url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return max(0, CMTimeGetSeconds(duration))
    }

    nonisolated private static func recognizeText(in url: URL, useCache: Bool) async throws -> String {
        try await PerformanceMetrics.measure(.carouselOCR, detail: url.lastPathComponent) {
            let key = ocrCacheKey(for: url)
            if useCache, let cached = await CarouselOCRCache.shared.value(for: key) {
                return cached
            }

            guard let cgImage = await ImageDecodeCache.shared.cgImage(for: url, maxPixelSize: 2400) else {
                return ""
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.012

            let handler = VNImageRequestHandler(cgImage: preprocessedImage(from: cgImage), options: [:])
            try handler.perform([request])

            let observations = (request.results ?? [])
                .sorted {
                    if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.03 {
                        return $0.boundingBox.midY > $1.boundingBox.midY
                    }
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }

            let lines = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }

            let result = lines
                .map(cleanLine)
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { partial, line in
                    appendOCRLine(line, to: &partial)
                }
                .joined(separator: "\n")
            await CarouselOCRCache.shared.set(result, for: key)
            return result
        }
    }

    nonisolated private static func preprocessedImage(from cgImage: CGImage) -> CGImage {
        let ciImage = CIImage(cgImage: cgImage)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 2, y: 2))
        let contrast = CIFilter(name: "CIColorControls")
        contrast?.setValue(scaled, forKey: kCIInputImageKey)
        contrast?.setValue(0, forKey: kCIInputSaturationKey)
        contrast?.setValue(1.35, forKey: kCIInputContrastKey)
        let sharpen = CIFilter(name: "CISharpenLuminance")
        sharpen?.setValue(contrast?.outputImage ?? scaled, forKey: kCIInputImageKey)
        sharpen?.setValue(0.35, forKey: kCIInputSharpnessKey)
        let output = sharpen?.outputImage ?? contrast?.outputImage ?? scaled
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(output, from: output.extent) ?? cgImage
    }

    nonisolated private static func ocrCacheKey(for url: URL) -> String {
        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        return "\(url.path)#\(modifiedAt)"
    }

    nonisolated private static func spokenScript(from text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .flatMap(sentenceFragments)
            .map(cleanSpeechSegment)
            .filter { line in
                line.count > 1
                    && !line.localizedCaseInsensitiveContains(".jpg")
                    && !line.localizedCaseInsensitiveContains(".png")
                    && !line.localizedCaseInsensitiveContains(".jpeg")
            }
            .map(punctuatedSentence)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func cleanLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{fffd}", with: "")
            .replacingOccurrences(of: #"(?i)\byou\s*['?]\s*re\b"#, with: "you're", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bthere\s*['?]\s*s\b"#, with: "there's", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bit\s*['?]\s*s\b"#, with: "it's", options: .regularExpression)
            .replacingOccurrences(of: #"[_•|]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(tiktok|instagram|reels)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"@\w+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bIMG[_-]?\d+\.(jpg|jpeg|png|heic)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([a-z])([A-Z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"([a-zA-Z])(\d)"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"(\d)([a-zA-Z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[.]{2,}"#, with: ".", options: .regularExpression)
            .replacingOccurrences(of: #"[!?]{2,}"#, with: "?", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func appendOCRLine(_ line: String, to lines: inout [String]) {
        guard !line.isEmpty else { return }
        guard let previous = lines.last else {
            lines.append(line)
            return
        }

        let previousEndsSentence = previous.range(of: #"[.!?:]$"#, options: .regularExpression) != nil
        let currentStartsLowercase = line.first.map { String($0).range(of: #"[a-z]"#, options: .regularExpression) != nil } ?? false
        let previousIsShortFragment = previous.count < 18 && previous.range(of: #"[.!?]$"#, options: .regularExpression) == nil

        if !previousEndsSentence && (currentStartsLowercase || previousIsShortFragment) {
            lines[lines.count - 1] = cleanLine("\(previous) \(line)")
        } else {
            lines.append(line)
        }
    }

    nonisolated private static func cleanSpeechSegment(_ text: String) -> String {
        var result = cleanLine(text)
            .replacingOccurrences(of: #"@\w+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\bTikTok\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while result.hasSuffix(",") || result.hasSuffix(":") || result.hasSuffix(";") {
            result.removeLast()
        }
        return result
    }

    nonisolated private static func sentenceFragments(from text: String) -> [String] {
        let cleaned = cleanLine(text)
        guard !cleaned.isEmpty else { return [] }

        let protected = cleaned
            .replacingOccurrences(of: #"(?i)\bstage\s+(\d+)\s*:"#,
                                  with: "Stage $1: ",
                                  options: .regularExpression)
        let fragments = protected
            .replacingOccurrences(of: #"([.!?])\s+"#, with: "$1\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .flatMap(splitLongClause)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return fragments.isEmpty ? [cleaned] : fragments
    }

    nonisolated private static func splitLongClause(_ text: String) -> [String] {
        guard text.count > 140 else { return [text] }
        let split = text
            .replacingOccurrences(of: #",\s+(and|but|so|because|perhaps)\s+"#,
                                  with: ". $1 ",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #";\s+"#, with: ". ", options: .regularExpression)
            .replacingOccurrences(of: #"([.!?])\s+"#, with: "$1\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return split.isEmpty ? [text] : split
    }

    nonisolated private static func punctuatedSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let last = trimmed.last, ".!?".contains(last) {
            return trimmed
        }
        return "\(trimmed)."
    }
}

private actor CarouselOCRCache {
    static let shared = CarouselOCRCache()

    private var values: [String: String] = [:]

    func value(for key: String) -> String? {
        values[key]
    }

    func set(_ value: String, for key: String) {
        values[key] = value
    }
}
