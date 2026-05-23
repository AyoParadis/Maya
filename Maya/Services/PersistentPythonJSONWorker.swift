import Foundation

actor PersistentPythonJSONWorker {
    struct Configuration: Sendable {
        var executable: String
        var arguments: [String]
        var workingDirectory: URL
        var environment: [String: String]
        var script: String
    }

    private struct ResponseEnvelope: Decodable {
        var id: String
        var ok: Bool
        var payload: String?
        var error: String?
    }

    private let configuration: Configuration
    private var process: Process?
    private var stdin: Pipe?
    private var outputBuffer = ""
    private var pending: [String: CheckedContinuation<String, Error>] = [:]

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func warm() async throws {
        try startIfNeeded()
    }

    func request(_ payload: [String: String]) async throws -> String {
        try startIfNeeded()
        guard let stdin else { throw PiperNarrationError.commandFailed("Python worker is not running.") }
        let id = UUID().uuidString
        var envelope = payload
        envelope["id"] = id
        let data = try JSONEncoder().encode(envelope)
        let line = data + Data([0x0A])
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try stdin.fileHandleForWriting.write(contentsOf: line)
            } catch {
                pending[id] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func stop() {
        for (_, continuation) in pending {
            continuation.resume(throwing: CancellationError())
        }
        pending.removeAll()
        process?.terminate()
        process = nil
        stdin = nil
        outputBuffer = ""
    }

    private func startIfNeeded() throws {
        if let process, process.isRunning { return }
        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.executable)
        process.arguments = configuration.arguments + ["-u", "-c", configuration.script]
        process.currentDirectoryURL = configuration.workingDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(configuration.environment) { _, new in new }

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { await self?.handleOutput(text) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { await self?.handleStderr(text) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination() }
        }

        try process.run()
        self.process = process
        self.stdin = stdin
    }

    private func handleOutput(_ text: String) {
        outputBuffer += text
        while let newline = outputBuffer.firstIndex(of: "\n") {
            let line = String(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            handleLine(line)
        }
    }

    private func handleLine(_ line: String) {
        let prefix = "MAYA_JSON:"
        guard line.hasPrefix(prefix) else { return }
        let json = String(line.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(ResponseEnvelope.self, from: data),
              let continuation = pending.removeValue(forKey: response.id) else { return }
        if response.ok {
            continuation.resume(returning: response.payload ?? "")
        } else {
            continuation.resume(throwing: PiperNarrationError.commandFailed(response.error ?? "Python worker failed."))
        }
    }

    private func handleStderr(_ text: String) {
        guard text.localizedCaseInsensitiveContains("Traceback") else { return }
        let error = PiperNarrationError.commandFailed(text.trimmingCharacters(in: .whitespacesAndNewlines))
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
    }

    private func handleTermination() {
        process = nil
        stdin = nil
        let error = PiperNarrationError.commandFailed("Python worker stopped.")
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
    }
}
