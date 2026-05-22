import CryptoKit
import Foundation

enum PiperNarrationService {
    nonisolated static let defaultVoice = "en_US-lessac-medium"

    struct Request: Sendable {
        let text: String
        let voice: String
    }

    struct PreviewResult: Sendable {
        let url: URL
        let usedCache: Bool
    }

    nonisolated static func generate(_ request: Request) async throws -> URL {
        let outputURL = try narrationDirectory()
            .appendingPathComponent("\(UUID().uuidString)-narration.wav")
        try await synthesize(request, outputURL: outputURL)
        return outputURL
    }

    nonisolated static func preview(_ request: Request) async throws -> PreviewResult {
        let outputURL = try previewURL(for: request)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return PreviewResult(url: outputURL, usedCache: true)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await synthesize(request, outputURL: outputURL)
        return PreviewResult(url: outputURL, usedCache: false)
    }

    nonisolated private static func synthesize(_ request: Request, outputURL: URL) async throws {
        let cleanedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            throw PiperNarrationError.emptyScript
        }

        let voice = request.voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultVoice
            : request.voice.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceDirectory = try voicesDirectory()
        try FileManager.default.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)

        try await downloadVoiceIfNeeded(voice, dataDirectory: voiceDirectory)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let python = try await pythonInvocation()
        try await runPython(
            python.executable,
            arguments: python.arguments + [
                "-m", "piper",
                "-m", voice,
                "--data-dir", voiceDirectory.path,
                "-f", outputURL.path,
                "--",
                cleanedText
            ],
            workingDirectory: voiceDirectory
        )

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw PiperNarrationError.outputMissing
        }
    }

    nonisolated static func installPiper() async throws {
        let environmentDirectory = try piperEnvironmentDirectory()
        let python = environmentDirectory.appendingPathComponent("bin/python")
        if !FileManager.default.isExecutableFile(atPath: python.path) {
            try await runPython(
                "/usr/bin/env",
                arguments: ["python3", "-m", "venv", environmentDirectory.path],
                workingDirectory: try applicationSupportDirectory()
            )
        }
        try await runPython(
            python.path,
            arguments: [
                "-m", "pip",
                "install",
                "--upgrade",
                "piper-tts"
            ],
            workingDirectory: environmentDirectory
        )
        Task.detached(priority: .utility) {
            await warmEnglishVoicePreviewsIfNeeded()
        }
    }

    nonisolated static func cacheEnglishVoicePreviews() async throws {
        let voices = PiperVoiceCatalog.englishVoiceIDs
        guard !voices.isEmpty else { return }

        let voiceDirectory = try voicesDirectory()
        try FileManager.default.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        try await downloadVoicesIfNeeded(voices, dataDirectory: voiceDirectory)

        for voice in voices {
            _ = try await preview(Request(text: PiperVoiceCatalog.previewText, voice: voice))
        }
    }

    nonisolated static func warmEnglishVoicePreviewsIfNeeded() async {
        await PiperPreviewCacheWarmup.shared.warmIfNeeded()
    }

    nonisolated static func hasCachedPreview(_ request: Request) -> Bool {
        guard let url = try? previewURL(for: request) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    nonisolated static func cleanupGeneratedNarration(at url: URL?) {
        guard let url else { return }
        let dir = (try? narrationDirectory().path) ?? ""
        guard !dir.isEmpty, url.path.hasPrefix(dir) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated private static func downloadVoiceIfNeeded(_ voice: String, dataDirectory: URL) async throws {
        let modelURL = dataDirectory.appendingPathComponent("\(voice).onnx")
        let configURL = dataDirectory.appendingPathComponent("\(voice).onnx.json")
        if FileManager.default.fileExists(atPath: modelURL.path),
           FileManager.default.fileExists(atPath: configURL.path) {
            return
        }

        let python = try await pythonInvocation()
        try await runPython(
            python.executable,
            arguments: python.arguments + [
                "-m", "piper.download_voices",
                "--data-dir", dataDirectory.path,
                voice
            ],
            workingDirectory: dataDirectory
        )
    }

    nonisolated private static func downloadVoicesIfNeeded(_ voices: [String], dataDirectory: URL) async throws {
        let missingVoices = voices.filter { voice in
            let modelURL = dataDirectory.appendingPathComponent("\(voice).onnx")
            let configURL = dataDirectory.appendingPathComponent("\(voice).onnx.json")
            return !FileManager.default.fileExists(atPath: modelURL.path)
                || !FileManager.default.fileExists(atPath: configURL.path)
        }
        guard !missingVoices.isEmpty else { return }

        let python = try await pythonInvocation()
        try await runPython(
            python.executable,
            arguments: python.arguments + [
                "-m", "piper.download_voices",
                "--data-dir", dataDirectory.path
            ] + missingVoices,
            workingDirectory: dataDirectory
        )
    }

    nonisolated private static func pythonInvocation() async throws -> (executable: String, arguments: [String]) {
        let piperPython = try piperEnvironmentDirectory().appendingPathComponent("bin/python").path
        if FileManager.default.isExecutableFile(atPath: piperPython) {
            return (piperPython, [])
        }
        return ("/usr/bin/env", ["python3"])
    }

    nonisolated private static func runPython(
        _ executable: String,
        arguments: [String],
        workingDirectory: URL
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = stderr.isEmpty ? stdout : stderr
            if message.localizedCaseInsensitiveContains("No module named piper")
                || message.localizedCaseInsensitiveContains("No module named 'piper'") {
                throw PiperNarrationError.piperNotInstalled
            }
            throw PiperNarrationError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    nonisolated private static func voicesDirectory() throws -> URL {
        try applicationSupportDirectory()
            .appendingPathComponent("PiperVoices", isDirectory: true)
    }

    nonisolated private static func narrationDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Narration", isDirectory: true)
    }

    nonisolated private static func previewDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("PiperPreviews", isDirectory: true)
    }

    nonisolated private static func previewURL(for request: Request) throws -> URL {
        let key = [
            request.voice.trimmingCharacters(in: .whitespacesAndNewlines),
            request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return try previewDirectory().appendingPathComponent("\(digest)-preview.wav")
    }

    nonisolated private static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Maya AI Studio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static func piperEnvironmentDirectory() throws -> URL {
        try applicationSupportDirectory()
            .appendingPathComponent("PiperEnvironment", isDirectory: true)
    }
}

enum PiperNarrationError: LocalizedError {
    case emptyScript
    case piperNotInstalled
    case outputMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyScript:
            "Enter a narration script before generating audio."
        case .piperNotInstalled:
            "Piper is not installed. Use Install Piper to create Maya's local Piper environment, then try again."
        case .outputMissing:
            "Piper finished but did not create a narration file."
        case .commandFailed(let message):
            message.isEmpty ? "Piper failed." : message
        }
    }
}

private actor PiperPreviewCacheWarmup {
    static let shared = PiperPreviewCacheWarmup()

    private var hasStarted = false

    func warmIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true
        try? await PiperNarrationService.cacheEnglishVoicePreviews()
    }
}
