import Foundation

enum CarouselNarrationCleanupService {
    nonisolated private static let helperScriptName = "maya-ai-director-helper.sh"

    struct Result: Sendable {
        let cleanedScript: String
        let runDirectory: URL
    }

    nonisolated static func clean(script: String, detectedText: String, slideName: String) async throws -> Result {
        let source = script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? detectedText : script
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CleanupError.emptyScript
        }

        let runDirectory = try makeRunDirectory()
        let metadata: [String: Any] = [
            "slideName": slideName,
            "detectedText": detectedText,
            "currentScript": script
        ]
        try writeJSONObject(metadata, to: runDirectory.appendingPathComponent("metadata.json"))
        try outputSchema.write(to: runDirectory.appendingPathComponent("output-schema.json"), atomically: true, encoding: .utf8)
        try prompt(source: source, detectedText: detectedText, slideName: slideName)
            .write(to: runDirectory.appendingPathComponent("prompt.txt"), atomically: true, encoding: .utf8)
        try "".write(to: runDirectory.appendingPathComponent("frame-args.txt"), atomically: true, encoding: .utf8)

        try await runHelper(in: runDirectory)
        let cleaned = try readCleanedScript(from: runDirectory.appendingPathComponent("generated-plan.json"))
        let final = CarouselSlideNarrationService.cleanedSpokenScript(from: cleaned)
        guard !final.isEmpty else { throw CleanupError.emptyResult }
        return Result(cleanedScript: final, runDirectory: runDirectory)
    }

    nonisolated private static func prompt(source: String, detectedText: String, slideName: String) -> String {
        """
        You clean OCR-damaged narration text for Maya AI Studio carousel voiceovers.

        Return JSON only, matching the provided schema.

        Task:
        - Fix grammar, punctuation, casing, spacing, broken words, and weird OCR characters.
        - Restore obvious apostrophes and contractions.
        - Remove OCR noise, repeated punctuation, watermarks, social handles, filenames, and UI artifacts.
        - Preserve the original meaning and order of the visible slide text.
        - Do not invent new marketing copy, facts, claims, calls to action, or extra sentences.
        - Keep the result natural for text-to-speech, with short sentence-like lines.

        Slide: \(slideName)

        Detected text reference:
        \(detectedText)

        Script to clean:
        \(source)
        """
    }

    nonisolated private static var outputSchema: String {
        """
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["cleanedScript"],
          "properties": {
            "cleanedScript": {
              "type": "string",
              "description": "The cleaned narration script only. Preserve meaning; do not add new copy."
            }
          }
        }
        """
    }

    private static func runHelper(in runDirectory: URL) async throws {
        guard let helperURL = helperURL() else { throw CleanupError.helperUnavailable }
        guard let codexPath = codexPath() else { throw CleanupError.codexNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [helperURL.path, runDirectory.path, codexPath]
        process.currentDirectoryURL = runDirectory
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        try stdout.write(to: runDirectory.appendingPathComponent("helper-stdout.log"), atomically: true, encoding: .utf8)
        try stderr.write(to: runDirectory.appendingPathComponent("helper-stderr.log"), atomically: true, encoding: .utf8)

        guard process.terminationStatus == 0 else {
            if stderr.localizedCaseInsensitiveContains("login") || stdout.localizedCaseInsensitiveContains("login") {
                throw CleanupError.codexLoginRequired
            }
            throw CleanupError.helperFailed(stderr.isEmpty ? stdout : stderr)
        }
    }

    nonisolated private static func makeRunDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let runs = base
            .appendingPathComponent("Maya AI Studio", isDirectory: true)
            .appendingPathComponent("Carousel Narration Cleanup", isDirectory: true)
            .appendingPathComponent("Runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
        let dir = runs.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static func helperURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent == helperScriptName {
            return url
        }
        return nil
    }

    nonisolated private static func codexPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated private static func readCleanedScript(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        do {
            return try parseCleanedScript(from: data)
        } catch {
            guard let text = String(data: data, encoding: .utf8),
                  let jsonRange = text.range(of: #"\{[\s\S]*\}"#, options: .regularExpression),
                  let jsonData = String(text[jsonRange]).data(using: .utf8) else {
                throw CleanupError.invalidJSON
            }
            return try parseCleanedScript(from: jsonData)
        }
    }

    nonisolated private static func parseCleanedScript(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cleanedScript = object["cleanedScript"] as? String else {
            throw CleanupError.invalidJSON
        }
        return cleanedScript
    }

    nonisolated private static func writeJSONObject(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}

private enum CleanupError: LocalizedError {
    case emptyScript
    case emptyResult
    case helperUnavailable
    case codexNotFound
    case codexLoginRequired
    case helperFailed(String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .emptyScript:
            "Add or detect script text before cleaning it."
        case .emptyResult:
            "Codex returned an empty cleaned script."
        case .helperUnavailable:
            "Maya could not find the local Codex helper."
        case .codexNotFound:
            "Codex CLI was not found. Install or link the `codex` command, then try Clean up again."
        case .codexLoginRequired:
            "Codex login required. Run `codex login` in Terminal, then try Clean up again."
        case .helperFailed(let detail):
            detail.isEmpty ? "Codex could not clean this script." : detail
        case .invalidJSON:
            "Codex returned a response Maya could not read."
        }
    }
}
