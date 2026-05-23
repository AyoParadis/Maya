import CryptoKit
import Foundation

enum NarratedCaptionAlignmentService {
    private static let workerBox = CaptionAlignmentWorkerBox()

    struct Word: Codable, Hashable, Sendable {
        var word: String
        var start: Double
        var end: Double
    }

    struct Result: Sendable {
        var words: [Word]
        var beats: [NarratedCaptionBeat]
    }

    nonisolated private struct DiskCacheResult: Codable {
        var words: [Word]
        var beats: [DiskCacheBeat]
    }

    nonisolated private struct DiskCacheBeat: Codable {
        var text: String
        var startTime: Double
        var endTime: Double
        var style: String
        var alignmentSource: String
        var wordTimings: [NarratedCaptionWordTiming]
    }

    nonisolated static func installationStatus() async -> NarrationEngineInstallationStatus {
        guard let environmentDirectory = try? environmentDirectory() else { return .notInstalled }
        let python = environmentDirectory.appendingPathComponent("bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return .notInstalled }
        guard isSupportedPython(at: python.path) else { return .incompatible }
        return canImportPythonPackage("whisperx", python: python.path) ? .installed : .notInstalled
    }

    nonisolated static func warm() async throws {
        let python = try pythonPath()
        guard FileManager.default.isExecutableFile(atPath: python) else {
            throw PiperNarrationError.engineNotInstalled("Caption aligner")
        }
        let worker = await workerBox.worker(configuration: workerConfiguration(python: python))
        try await worker.warm()
    }

    nonisolated static func install(progress: (@Sendable (String) -> Void)? = nil) async throws {
        let environmentDirectory = try environmentDirectory()
        var python = environmentDirectory.appendingPathComponent("bin/python")
        if FileManager.default.isExecutableFile(atPath: python.path),
           !isSupportedPython(at: python.path) {
            progress?("Installing caption aligner: replacing incompatible Python environment...")
            try FileManager.default.removeItem(at: environmentDirectory)
            python = environmentDirectory.appendingPathComponent("bin/python")
        }

        if !FileManager.default.isExecutableFile(atPath: python.path) {
            let pythonExecutable = try compatiblePythonExecutable()
            progress?("Installing caption aligner: creating Python environment...")
            try await runProcess(
                pythonExecutable,
                arguments: ["-m", "venv", environmentDirectory.path],
                workingDirectory: try applicationSupportDirectory(),
                progress: progress
            )
        }
        guard isSupportedPython(at: python.path) else {
            throw PiperNarrationError.commandFailed(
                "Caption alignment requires Python 3.10, 3.11, or 3.12. Install one of those Python versions and retry."
            )
        }

        progress?("Installing caption aligner: upgrading pip tools...")
        try await runProcess(
            python.path,
            arguments: ["-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"],
            workingDirectory: environmentDirectory,
            progress: progress
        )
        progress?("Installing caption aligner: downloading WhisperX packages...")
        try await runProcess(
            python.path,
            arguments: ["-m", "pip", "install", "--upgrade", "whisperx"],
            workingDirectory: environmentDirectory,
            progress: progress
        )
    }

    nonisolated static func align(audioURL: URL, script: String, duration: Double) async throws -> Result {
        let cleanedScript = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedScript.isEmpty else { throw PiperNarrationError.emptyScript }
        let cacheKey = alignmentCacheKey(audioURL: audioURL, script: cleanedScript, duration: duration)
        if let cached = await NarratedCaptionAlignmentCache.shared.value(for: cacheKey) {
            return cached
        }
        if let cached = try? diskCachedResult(for: cacheKey) {
            await NarratedCaptionAlignmentCache.shared.set(cached, for: cacheKey)
            return cached
        }
        let python = try pythonPath()
        guard FileManager.default.isExecutableFile(atPath: python) else {
            throw PiperNarrationError.engineNotInstalled("Caption aligner")
        }

        do {
            let worker = await workerBox.worker(configuration: workerConfiguration(python: python))
            let payload = try await worker.request([
                "audio": audioURL.path,
                "script": cleanedScript,
                "duration": "\(duration)"
            ])
            let words = try JSONDecoder().decode([Word].self, from: Data(payload.utf8))
                .filter { !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.end > $0.start }
            guard !words.isEmpty else {
                throw PiperNarrationError.commandFailed("Caption aligner did not return word timestamps.")
            }
            let result = Result(words: words, beats: beats(from: words, duration: duration))
            await NarratedCaptionAlignmentCache.shared.set(result, for: cacheKey)
            try? writeDiskCachedResult(result, for: cacheKey)
            PerformanceMetrics.event(.captionAlignment, detail: "worker aligned \(words.count) words")
            return result
        } catch {
            PerformanceMetrics.event(.pythonWorker, detail: "Caption worker fallback: \(error.localizedDescription)")
            await workerBox.reset()
        }

        let outputURL = try alignmentOutputURL()
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        try await runProcess(
            python,
            arguments: ["-c", alignmentScript, audioURL.path, cleanedScript, "\(duration)", outputURL.path],
            workingDirectory: try applicationSupportDirectory(),
            environment: [
                "PYTORCH_ENABLE_MPS_FALLBACK": "1",
                "TOKENIZERS_PARALLELISM": "false"
            ]
        )

        let data = try Data(contentsOf: outputURL)
        try? FileManager.default.removeItem(at: outputURL)
        let words = try JSONDecoder().decode([Word].self, from: data)
            .filter { !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.end > $0.start }
        guard !words.isEmpty else {
            throw PiperNarrationError.commandFailed("Caption aligner did not return word timestamps.")
        }
        let result = Result(words: words, beats: beats(from: words, duration: duration))
        await NarratedCaptionAlignmentCache.shared.set(result, for: cacheKey)
        try? writeDiskCachedResult(result, for: cacheKey)
        return result
    }

    nonisolated static func beats(from words: [Word], duration: Double) -> [NarratedCaptionBeat] {
        var beats: [NarratedCaptionBeat] = []
        var index = 0
        while index < words.count {
            let remaining = words.count - index
            let groupSize: Int
            if remaining <= 2 {
                groupSize = remaining
            } else if remaining == 3 {
                groupSize = 3
            } else if words[index].word.count <= 2 {
                groupSize = 3
            } else {
                groupSize = min(4, max(2, remaining >= 8 ? 3 : 2))
            }

            let group = Array(words[index..<min(index + groupSize, words.count)])
            let start = max(0, group.first?.start ?? 0)
            let end = min(max(duration, 0.5), max(start + 0.08, group.last?.end ?? start + 0.4))
            let text = group.map(\.word).joined(separator: " ").uppercased()
            beats.append(
                NarratedCaptionBeat(
                    text: text,
                    startTime: start,
                    endTime: end,
                    alignmentSource: .forcedAligned,
                    wordTimings: group.map {
                        NarratedCaptionWordTiming(word: $0.word, startTime: $0.start, endTime: $0.end)
                    }
                )
            )
            index += group.count
        }
        return clampedNonOverlapping(beats, duration: duration)
    }

    nonisolated private static func clampedNonOverlapping(_ beats: [NarratedCaptionBeat], duration: Double) -> [NarratedCaptionBeat] {
        var result = beats
        let safeDuration = max(0.5, duration)
        for index in result.indices {
            let previousEnd = index > 0 ? result[index - 1].endTime : 0
            result[index].startTime = max(previousEnd, min(result[index].startTime, safeDuration))
            result[index].endTime = max(result[index].startTime + 0.08, min(result[index].endTime, safeDuration))
        }
        return result
    }

    nonisolated private static var alignmentScript: String {
        """
        import json
        import sys

        audio_path, transcript, duration, output_path = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
        import torch
        import whisperx

        device = "mps" if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available() else "cpu"
        audio = whisperx.load_audio(audio_path)
        model_a, metadata = whisperx.load_align_model(language_code="en", device=device)
        segments = [{"start": 0.0, "end": max(duration, 0.5), "text": transcript}]
        aligned = whisperx.align(segments, model_a, metadata, audio, device, return_char_alignments=False)
        raw_words = aligned.get("word_segments") or []
        words = []
        for item in raw_words:
            word = str(item.get("word", "")).strip()
            if not word or "start" not in item or "end" not in item:
                continue
            words.append({
                "word": word,
                "start": float(item["start"]),
                "end": float(item["end"])
            })
        with open(output_path, "w", encoding="utf-8") as handle:
            json.dump(words, handle)
        """
    }

    nonisolated private static func workerConfiguration(python: String) -> PersistentPythonJSONWorker.Configuration {
        PersistentPythonJSONWorker.Configuration(
            executable: python,
            arguments: [],
            workingDirectory: (try? applicationSupportDirectory()) ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            environment: [
                "PYTORCH_ENABLE_MPS_FALLBACK": "1",
                "TOKENIZERS_PARALLELISM": "false"
            ],
            script: workerScript
        )
    }

    nonisolated private static var workerScript: String {
        """
        import json
        import sys
        import traceback
        import torch
        import whisperx

        device = "mps" if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available() else "cpu"
        model_a, metadata = whisperx.load_align_model(language_code="en", device=device)

        def respond(request_id, ok, payload="", error=""):
            print("MAYA_JSON:" + json.dumps({
                "id": request_id,
                "ok": ok,
                "payload": payload,
                "error": error
            }), flush=True)

        for line in sys.stdin:
            try:
                request = json.loads(line)
                request_id = request.get("id", "")
                audio_path = str(request.get("audio", ""))
                transcript = str(request.get("script", ""))
                duration = float(request.get("duration", "0") or 0)
                audio = whisperx.load_audio(audio_path)
                segments = [{"start": 0.0, "end": max(duration, 0.5), "text": transcript}]
                aligned = whisperx.align(segments, model_a, metadata, audio, device, return_char_alignments=False)
                raw_words = aligned.get("word_segments") or []
                words = []
                for item in raw_words:
                    word = str(item.get("word", "")).strip()
                    if not word or "start" not in item or "end" not in item:
                        continue
                    words.append({
                        "word": word,
                        "start": float(item["start"]),
                        "end": float(item["end"])
                    })
                respond(request_id, True, json.dumps(words))
            except Exception as exc:
                respond(request.get("id", "") if "request" in locals() else "", False, "", str(exc) + "\\n" + traceback.format_exc())
        """
    }

    nonisolated private static func pythonPath() throws -> String {
        try environmentDirectory().appendingPathComponent("bin/python").path
    }

    nonisolated private static func compatiblePythonExecutable() throws -> String {
        for candidate in ["python3.12", "python3.11", "python3.10"] {
            if let path = executablePath(named: candidate), isSupportedPython(at: path) {
                return path
            }
        }
        throw PiperNarrationError.commandFailed(
            "Caption alignment requires Python 3.10, 3.11, or 3.12. Install one of those Python versions and retry."
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

    nonisolated private static func environmentDirectory() throws -> URL {
        try applicationSupportDirectory()
            .appendingPathComponent("CaptionAlignmentEnvironment", isDirectory: true)
    }

    nonisolated private static func alignmentOutputURL() throws -> URL {
        let directory = try applicationSupportDirectory()
            .appendingPathComponent("CaptionAlignment", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
            .appendingPathComponent("\(UUID().uuidString)-words.json")
    }

    nonisolated private static func alignmentCacheKey(audioURL: URL, script: String, duration: Double) -> String {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)) ?? [:]
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let byteCount = attributes[.size] as? Int64 ?? 0
        return "\(audioURL.path)#\(modifiedAt)#\(byteCount)#\(duration)#\(script)"
    }

    nonisolated private static func diskCachedResult(for cacheKey: String) throws -> Result? {
        let url = try diskCacheURL(for: cacheKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let cached = try JSONDecoder().decode(DiskCacheResult.self, from: data)
        return Result(
            words: cached.words,
            beats: cached.beats.map { beat in
                NarratedCaptionBeat(
                    text: beat.text,
                    startTime: beat.startTime,
                    endTime: beat.endTime,
                    style: NarratedCaptionStyle(rawValue: beat.style) ?? .boldCenter,
                    alignmentSource: NarratedCaptionAlignmentSource(rawValue: beat.alignmentSource) ?? .forcedAligned,
                    wordTimings: beat.wordTimings
                )
            }
        )
    }

    nonisolated private static func writeDiskCachedResult(_ result: Result, for cacheKey: String) throws {
        let url = try diskCacheURL(for: cacheKey)
        let cached = DiskCacheResult(
            words: result.words,
            beats: result.beats.map { beat in
                DiskCacheBeat(
                    text: beat.text,
                    startTime: beat.startTime,
                    endTime: beat.endTime,
                    style: beat.style.rawValue,
                    alignmentSource: beat.alignmentSource.rawValue,
                    wordTimings: beat.wordTimings
                )
            }
        )
        let data = try JSONEncoder().encode(cached)
        try data.write(to: url, options: .atomic)
    }

    nonisolated private static func diskCacheURL(for cacheKey: String) throws -> URL {
        let directory = try applicationSupportDirectory()
            .appendingPathComponent("CaptionAlignmentCache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data(cacheKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent("\(digest).json")
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        let buffer = NarratedAlignmentProcessOutputBuffer()
        let progressReporter = NarratedAlignmentProcessProgressReporter(progress: progress)
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
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            let stdout = buffer.stdout
            let stderr = buffer.stderr
            let message = (stderr.isEmpty ? stdout : stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw PiperNarrationError.commandFailed(message.isEmpty ? "Caption aligner failed." : message)
        }
    }
}

private actor NarratedCaptionAlignmentCache {
    static let shared = NarratedCaptionAlignmentCache()
    private var values: [String: NarratedCaptionAlignmentService.Result] = [:]

    func value(for key: String) -> NarratedCaptionAlignmentService.Result? {
        values[key]
    }

    func set(_ value: NarratedCaptionAlignmentService.Result, for key: String) {
        values[key] = value
    }
}

private actor CaptionAlignmentWorkerBox {
    private var worker: PersistentPythonJSONWorker?
    private var signature: String?

    func worker(configuration: PersistentPythonJSONWorker.Configuration) async -> PersistentPythonJSONWorker {
        let nextSignature = [
            configuration.executable,
            configuration.arguments.joined(separator: "\u{1F}"),
            configuration.workingDirectory.path
        ].joined(separator: "\u{1E}")
        if let worker, signature == nextSignature {
            return worker
        }
        await worker?.stop()
        let worker = PersistentPythonJSONWorker(configuration: configuration)
        self.worker = worker
        signature = nextSignature
        return worker
    }

    func reset() async {
        await worker?.stop()
        worker = nil
        signature = nil
    }
}

nonisolated private final class NarratedAlignmentProcessOutputBuffer: @unchecked Sendable {
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

nonisolated private final class NarratedAlignmentProcessProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastMessage = ""
    private let progress: (@Sendable (String) -> Void)?

    init(progress: (@Sendable (String) -> Void)?) {
        self.progress = progress
    }

    func report(_ text: String) {
        guard let progress else { return }
        for line in text.components(separatedBy: .newlines) {
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            lock.lock()
            let shouldReport = cleaned != lastMessage
            if shouldReport {
                lastMessage = cleaned
            }
            lock.unlock()
            if shouldReport {
                progress(cleaned)
            }
        }
    }
}
