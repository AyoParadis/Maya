import CryptoKit
import Foundation

enum NarrationEngine: String, CaseIterable, Hashable, Identifiable, Sendable {
    case piper
    case kokoro

    nonisolated static let defaultEngine: NarrationEngine = .kokoro

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .piper:
            "Piper"
        case .kokoro:
            "Kokoro"
        }
    }

    nonisolated var shortDescription: String {
        switch self {
        case .piper:
            "Fast local voices"
        case .kokoro:
            "Premium local voices"
        }
    }

    nonisolated var defaultVoice: String {
        switch self {
        case .piper:
            PiperNarrationService.defaultVoice
        case .kokoro:
            "af_heart"
        }
    }

    nonisolated var installHelp: String {
        switch self {
        case .piper:
            "Create Maya's local Piper environment and install piper-tts"
        case .kokoro:
            "Create Maya's local Kokoro environment and install kokoro with audio dependencies"
        }
    }
}

enum NarrationEngineInstallationStatus: String, Sendable {
    case notInstalled
    case installed
    case incompatible
}

struct NarrationEngineStorage: Identifiable, Sendable {
    let engine: NarrationEngine
    let byteCount: Int64
    let installationStatus: NarrationEngineInstallationStatus

    var id: NarrationEngine { engine }
    var hasDeletableAssets: Bool { byteCount > 0 }
    var formattedSize: String { ByteCountFormatter.mayaVoiceStorage.string(fromByteCount: byteCount) }
}

struct NarrationStorageSummary: Sendable {
    let engines: [NarrationEngineStorage]

    var totalBytes: Int64 {
        engines.reduce(0) { $0 + $1.byteCount }
    }

    var formattedTotalSize: String {
        ByteCountFormatter.mayaVoiceStorage.string(fromByteCount: totalBytes)
    }

    func storage(for engine: NarrationEngine) -> NarrationEngineStorage {
        engines.first { $0.engine == engine } ?? NarrationEngineStorage(
            engine: engine,
            byteCount: 0,
            installationStatus: .notInstalled
        )
    }
}

struct NarrationRequest: Sendable {
    let engine: NarrationEngine
    let text: String
    let voice: String
}

struct NarrationPreviewResult: Sendable {
    let url: URL
    let usedCache: Bool
}

enum NarrationService {
    nonisolated static let previewText = "This is a Maya AI Studio voice preview. Listen for clarity, warmth, pacing, breath, and whether the voice still feels natural after a few full sentences."

    nonisolated static func generate(_ request: NarrationRequest) async throws -> URL {
        try await PerformanceMetrics.measure(.narrationGenerate, detail: request.engine.displayName) {
            switch request.engine {
            case .piper:
                return try await PiperNarrationService.generate(.init(text: request.text, voice: request.voice))
            case .kokoro:
                let outputURL = try narrationDirectory()
                    .appendingPathComponent("\(UUID().uuidString)-narration.wav")
                try await PythonNarrationEngineService.synthesize(request, outputURL: outputURL)
                return outputURL
            }
        }
    }

    nonisolated static func preview(_ request: NarrationRequest) async throws -> NarrationPreviewResult {
        try await PerformanceMetrics.measure(.narrationPreview, detail: "\(request.engine.displayName) \(request.voice)") {
            if request.engine == .piper {
                let result = try await PiperNarrationService.preview(.init(text: request.text, voice: request.voice))
                return NarrationPreviewResult(url: result.url, usedCache: result.usedCache)
            }

            let outputURL = try previewURL(for: request)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                return NarrationPreviewResult(url: outputURL, usedCache: true)
            }

            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await PythonNarrationEngineService.synthesize(request, outputURL: outputURL)
            return NarrationPreviewResult(url: outputURL, usedCache: false)
        }
    }

    nonisolated static func install(
        _ engine: NarrationEngine,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws {
        try await PerformanceMetrics.measure(.narrationInstall, detail: engine.displayName) {
            switch engine {
            case .piper:
                progress?("Installing Piper: preparing local Python environment...")
                try await PiperNarrationService.installPiper()
            case .kokoro:
                try await PythonNarrationEngineService.install(engine, progress: progress)
            }
        }
    }

    nonisolated static func installationStatus(for engine: NarrationEngine) async -> NarrationEngineInstallationStatus {
        switch engine {
        case .piper:
            await PiperNarrationService.installationStatus()
        case .kokoro:
            await PythonNarrationEngineService.installationStatus(for: engine)
        }
    }

    nonisolated static func storageSummary() async -> NarrationStorageSummary {
        var engineStorage: [NarrationEngineStorage] = []
        for engine in NarrationEngine.allCases {
            let urls = assetURLs(for: engine)
            let bytes = urls.reduce(Int64(0)) { partial, url in
                partial + FileManager.default.mayaAllocatedSize(of: url)
            }
            let status = await installationStatus(for: engine)
            engineStorage.append(
                NarrationEngineStorage(
                    engine: engine,
                    byteCount: bytes,
                    installationStatus: status
                )
            )
        }
        return NarrationStorageSummary(engines: engineStorage)
    }

    nonisolated static func deleteAssets(for engine: NarrationEngine) async throws {
        for url in assetURLs(for: engine) {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    nonisolated static func warmPreviewsIfNeeded(for engine: NarrationEngine) async {
        if engine == .piper {
            await PiperNarrationService.warmEnglishVoicePreviewsIfNeeded()
        } else {
            try? await cacheVoicePreviews(for: engine)
        }
    }

    nonisolated static func cacheVoicePreviews(
        for engine: NarrationEngine,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws {
        if engine == .piper {
            progress?("Preparing Piper previews...")
            try await PiperNarrationService.cacheEnglishVoicePreviews()
            return
        }

        let voices = NarrationVoiceCatalog.voices(for: engine)
        guard !voices.isEmpty else { return }
        for (index, voice) in voices.enumerated() {
            let request = NarrationRequest(engine: engine, text: previewText, voice: voice.id)
            if (try? previewURL(for: request).checkResourceIsReachable()) == true {
                continue
            }
            progress?("Preparing \(engine.displayName) preview \(index + 1) of \(voices.count): \(voice.name)")
            _ = try await preview(request)
        }
    }

    nonisolated static func cleanupGeneratedNarration(at url: URL?) {
        PiperNarrationService.cleanupGeneratedNarration(at: url)
    }

    nonisolated private static func narrationDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Narration", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static func previewDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("PremiumVoicePreviews", isDirectory: true)
    }

    nonisolated private static func previewURL(for request: NarrationRequest) throws -> URL {
        let key = [
            request.engine.rawValue,
            request.voice.trimmingCharacters(in: .whitespacesAndNewlines),
            request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return try previewDirectory().appendingPathComponent("\(digest)-preview.wav")
    }

    nonisolated private static func assetURLs(for engine: NarrationEngine) -> [URL] {
        switch engine {
        case .piper:
            return PiperNarrationService.assetURLs()
        case .kokoro:
            return PythonNarrationEngineService.assetURLs(for: engine) + premiumPreviewURLs(for: engine)
        }
    }

    nonisolated private static func premiumPreviewURLs(for engine: NarrationEngine) -> [URL] {
        NarrationVoiceCatalog.voices(for: engine).compactMap { voice in
            try? previewURL(for: NarrationRequest(engine: engine, text: previewText, voice: voice.id))
        }
    }
}

private enum PythonNarrationEngineService {
    nonisolated static func installationStatus(for engine: NarrationEngine) async -> NarrationEngineInstallationStatus {
        guard let environmentDirectory = try? environmentDirectory(for: engine) else { return .notInstalled }
        let python = environmentDirectory.appendingPathComponent("bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return .notInstalled }
        guard isSupportedPython(at: python.path) else { return .incompatible }
        return canImportPythonPackage(packageName(for: engine), python: python.path) ? .installed : .notInstalled
    }

    nonisolated static func install(
        _ engine: NarrationEngine,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let environmentDirectory = try environmentDirectory(for: engine)
        var python = environmentDirectory.appendingPathComponent("bin/python")
        if FileManager.default.isExecutableFile(atPath: python.path),
           !isSupportedPython(at: python.path) {
            progress?("Installing \(engine.displayName): replacing incompatible Python environment...")
            try FileManager.default.removeItem(at: environmentDirectory)
            python = environmentDirectory.appendingPathComponent("bin/python")
        }

        if !FileManager.default.isExecutableFile(atPath: python.path) {
            let pythonExecutable = try compatiblePythonExecutable()
            progress?("Installing \(engine.displayName): creating Python environment with \(URL(fileURLWithPath: pythonExecutable).lastPathComponent)...")
            try await runProcess(
                pythonExecutable,
                arguments: ["-m", "venv", environmentDirectory.path],
                workingDirectory: try applicationSupportDirectory(),
                progress: progress
            )
        }
        guard isSupportedPython(at: python.path) else {
            throw PiperNarrationError.commandFailed(
                "\(engine.displayName) requires Python 3.10, 3.11, or 3.12. Install one of those Python versions and retry Install selected engine."
            )
        }

        progress?("Installing \(engine.displayName): upgrading pip tools...")
        try await runProcess(
            python.path,
            arguments: ["-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"],
            workingDirectory: environmentDirectory,
            progress: progress
        )
        progress?("Installing \(engine.displayName): downloading voice engine packages...")
        try await runProcess(
            python.path,
            arguments: ["-m", "pip", "install", "--upgrade"] + packages(for: engine),
            workingDirectory: environmentDirectory,
            progress: progress
        )
    }

    nonisolated static func synthesize(_ request: NarrationRequest, outputURL: URL) async throws {
        let cleanedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            throw PiperNarrationError.emptyScript
        }

        let python = try pythonPath(for: request.engine)
        guard FileManager.default.isExecutableFile(atPath: python) else {
            throw PiperNarrationError.engineNotInstalled(request.engine.displayName)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let voice = request.voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? request.engine.defaultVoice
            : request.voice.trimmingCharacters(in: .whitespacesAndNewlines)
        try await runProcess(
            python,
            arguments: ["-c", script(for: request.engine), cleanedText, voice, outputURL.path],
            workingDirectory: try applicationSupportDirectory(),
            environment: [
                "PYTORCH_ENABLE_MPS_FALLBACK": "1",
                "TOKENIZERS_PARALLELISM": "false"
            ]
        )

        PerformanceMetrics.event(.narrationGenerate, detail: "\(request.engine.displayName) validating output")
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw PiperNarrationError.outputMissing
        }
    }

    nonisolated static func assetURLs(for engine: NarrationEngine) -> [URL] {
        guard let environmentDirectory = try? environmentDirectory(for: engine) else { return [] }
        return [environmentDirectory]
    }

    nonisolated private static func packages(for engine: NarrationEngine) -> [String] {
        switch engine {
        case .piper:
            ["piper-tts"]
        case .kokoro:
            ["kokoro>=0.9.4", "soundfile", "misaki[en]"]
        }
    }

    nonisolated private static func packageName(for engine: NarrationEngine) -> String {
        switch engine {
        case .piper:
            "piper"
        case .kokoro:
            "kokoro"
        }
    }

    nonisolated private static func script(for engine: NarrationEngine) -> String {
        switch engine {
        case .piper:
            ""
        case .kokoro:
            """
            import sys
            import soundfile as sf
            from kokoro import KPipeline

            text, voice, output = sys.argv[1], sys.argv[2], sys.argv[3]
            voice = voice or "af_heart"
            lang_code = voice[:1] if voice else "a"
            pipeline = KPipeline(lang_code=lang_code)
            generator = pipeline(text, voice=voice)
            chunks = []
            for _, _, audio in generator:
                chunks.append(audio)
            if not chunks:
                raise RuntimeError("Kokoro did not generate audio.")
            try:
                import numpy as np
                audio = np.concatenate(chunks)
            except Exception:
                audio = chunks[0]
            sf.write(output, audio, 24000)
            """
        }
    }

    nonisolated private static func pythonPath(for engine: NarrationEngine) throws -> String {
        try environmentDirectory(for: engine).appendingPathComponent("bin/python").path
    }

    nonisolated private static func compatiblePythonExecutable() throws -> String {
        for candidate in ["python3.12", "python3.11", "python3.10"] {
            if let path = executablePath(named: candidate), isSupportedPython(at: path) {
                return path
            }
        }
        throw PiperNarrationError.commandFailed(
            "Premium voice engines require Python 3.10, 3.11, or 3.12. Install one of those Python versions and retry Install selected engine."
        )
    }

    nonisolated private static func executablePath(named name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let path = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    nonisolated private static func isSupportedPython(at path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [
            "-c",
            "import sys; raise SystemExit(0 if (3, 10) <= sys.version_info[:2] < (3, 13) else 1)"
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        return process.terminationStatus == 0
    }

    nonisolated private static func canImportPythonPackage(_ package: String, python: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [
            "-c",
            "import importlib.util, sys; raise SystemExit(0 if importlib.util.find_spec(sys.argv[1]) else 1)",
            package
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        return process.terminationStatus == 0
    }

    nonisolated private static func environmentDirectory(for engine: NarrationEngine) throws -> URL {
        try applicationSupportDirectory()
            .appendingPathComponent("\(engine.rawValue.capitalized)Environment", isDirectory: true)
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

    nonisolated private static func runProcess(
        _ executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String] = [:],
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let signpost = PerformanceMetrics.begin(.pythonProcess, detail: URL(fileURLWithPath: executable).lastPathComponent)
        let timer = WallClockTimer()
        defer {
            PerformanceMetrics.end(.pythonProcess, id: signpost, detail: "\(timer.elapsedMilliseconds)ms")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        let buffer = ProcessOutputBuffer()
        let progressReporter = ProcessProgressReporter(progress: progress)
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            buffer.appendStdout(text)
            progressReporter.report(text)
        }
        error.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            buffer.appendStderr(text)
            progressReporter.report(text)
        }

        try process.run()
        PerformanceMetrics.event(.pythonProcess, detail: "\(URL(fileURLWithPath: executable).lastPathComponent) started")
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil

        let stdout = buffer.stdout
        let stderr = buffer.stderr

        PerformanceMetrics.event(.pythonProcess, detail: "\(URL(fileURLWithPath: executable).lastPathComponent) exited \(process.terminationStatus)")
        guard process.terminationStatus == 0 else {
            let message = (stderr.isEmpty ? stdout : stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw PiperNarrationError.commandFailed(message.isEmpty ? "Voice engine failed." : message)
        }
    }
}

nonisolated private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutText = ""
    private var stderrText = ""

    var stdout: String {
        lock.lock()
        defer { lock.unlock() }
        return stdoutText
    }

    var stderr: String {
        lock.lock()
        defer { lock.unlock() }
        return stderrText
    }

    func appendStdout(_ text: String) {
        lock.lock()
        stdoutText += text
        lock.unlock()
    }

    func appendStderr(_ text: String) {
        lock.lock()
        stderrText += text
        lock.unlock()
    }
}

nonisolated private final class ProcessProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastMessage = ""
    private let progress: (@Sendable (String) -> Void)?

    init(progress: (@Sendable (String) -> Void)?) {
        self.progress = progress
    }

    func report(_ text: String) {
        guard let progress else { return }
        for line in progressLines(from: text) {
            lock.lock()
            let shouldReport = line != lastMessage
            if shouldReport {
                lastMessage = line
            }
            lock.unlock()
            if shouldReport {
                progress(line)
            }
        }
    }

    private func progressLines(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty
                    && !line.localizedCaseInsensitiveContains("[notice]")
                    && !line.localizedCaseInsensitiveContains("already satisfied")
            }
    }
}

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

    nonisolated static func installationStatus() async -> NarrationEngineInstallationStatus {
        if let piperPython = try? piperEnvironmentDirectory().appendingPathComponent("bin/python").path,
           FileManager.default.isExecutableFile(atPath: piperPython) {
            return canImportPiper(python: piperPython, arguments: []) ? .installed : .notInstalled
        }
        return canImportPiper(python: "/usr/bin/env", arguments: ["python3"]) ? .installed : .notInstalled
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

    nonisolated static func assetURLs() -> [URL] {
        [
            try? piperEnvironmentDirectory(),
            try? voicesDirectory(),
            try? previewDirectory()
        ].compactMap(\.self)
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
        let signpost = PerformanceMetrics.begin(.pythonProcess, detail: URL(fileURLWithPath: executable).lastPathComponent)
        let timer = WallClockTimer()
        defer {
            PerformanceMetrics.end(.pythonProcess, id: signpost, detail: "\(timer.elapsedMilliseconds)ms")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

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

    nonisolated private static func canImportPiper(python: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = arguments + [
            "-c",
            "import importlib.util; raise SystemExit(0 if importlib.util.find_spec('piper') else 1)"
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        return process.terminationStatus == 0
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
    case engineNotInstalled(String)
    case outputMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyScript:
            "Enter a narration script before generating audio."
        case .piperNotInstalled:
            "Piper is not installed. Use Install Piper to create Maya's local Piper environment, then try again."
        case .engineNotInstalled(let engine):
            "\(engine) is not installed. Use Install selected engine, then try again."
        case .outputMissing:
            "The voice engine finished but did not create a narration file."
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

private extension FileManager {
    nonisolated func mayaAllocatedSize(of url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if isDirectory.boolValue {
            return mayaDirectoryAllocatedSize(at: url)
        }
        return mayaFileAllocatedSize(at: url)
    }

    nonisolated func mayaDirectoryAllocatedSize(at url: URL) -> Int64 {
        guard let enumerator = enumerator(
            at: url,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey
            ],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += mayaFileAllocatedSize(at: fileURL)
        }
        return total
    }

    nonisolated func mayaFileAllocatedSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]), values.isRegularFile == true else {
            return 0
        }
        let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
        return Int64(size)
    }
}

private extension ByteCountFormatter {
    static let mayaVoiceStorage: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}
