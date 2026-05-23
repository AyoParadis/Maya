import CoreGraphics
import Foundation
import Observation

enum NarratedCaptionStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case boldCenter
    case lowerCenter
    case softSubtitle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .boldCenter: "Bold Center"
        case .lowerCenter: "Lower Center"
        case .softSubtitle: "Soft Subtitle"
        }
    }
}

enum NarratedCaptionAlignmentSource: String, Codable, Sendable {
    case estimated
    case forcedAligned
    case manual

    var label: String {
        switch self {
        case .estimated: "Estimated"
        case .forcedAligned: "Voice-aligned"
        case .manual: "Manual edits"
        }
    }
}

struct NarratedCaptionWordTiming: Codable, Hashable, Sendable {
    var word: String
    var startTime: Double
    var endTime: Double
}

struct NarratedCaptionBeat: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var text: String
    var startTime: Double
    var endTime: Double
    var style: NarratedCaptionStyle
    var alignmentSource: NarratedCaptionAlignmentSource
    var wordTimings: [NarratedCaptionWordTiming]

    nonisolated init(
        id: UUID = UUID(),
        text: String,
        startTime: Double,
        endTime: Double,
        style: NarratedCaptionStyle = .boldCenter,
        alignmentSource: NarratedCaptionAlignmentSource = .estimated,
        wordTimings: [NarratedCaptionWordTiming] = []
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.style = style
        self.alignmentSource = alignmentSource
        self.wordTimings = wordTimings
    }
}

enum NarratedImageSceneNarrationStatus: String, Sendable {
    case idle
    case generating
    case generated
    case failed

    var label: String {
        switch self {
        case .idle: "Not generated"
        case .generating: "Generating"
        case .generated: "Generated"
        case .failed: "Failed"
        }
    }
}

enum NarratedCaptionAlignmentStatus: String, Sendable {
    case idle
    case aligning
    case aligned
    case estimated
    case failed

    var label: String {
        switch self {
        case .idle: "Not aligned"
        case .aligning: "Aligning"
        case .aligned: "Voice-aligned"
        case .estimated: "Estimated"
        case .failed: "Alignment failed"
        }
    }
}

@Observable
final class NarratedImageScene: Identifiable, Hashable {
    var id: UUID
    var imageURL: URL?
    var displayName: String
    var script: String
    var captionBeats: [NarratedCaptionBeat]
    var narrationAudioURL: URL?
    var narrationAudioDuration: Double?
    var narrationStatus: NarratedImageSceneNarrationStatus
    var narrationError: String?
    var duration: Double
    var motionPreset: CarouselMotionPreset
    var captionAnchor: CGPoint
    var captionBoxWidth: Double
    var captionFontScale: Double
    var captionFontFamily: String?
    var selectedCaptionBeatID: UUID?
    var captionAlignmentStatus: NarratedCaptionAlignmentStatus
    var captionAlignmentError: String?

    init(
        id: UUID = UUID(),
        imageURL: URL? = nil,
        displayName: String,
        script: String = "",
        captionBeats: [NarratedCaptionBeat] = [],
        narrationAudioURL: URL? = nil,
        narrationAudioDuration: Double? = nil,
        narrationStatus: NarratedImageSceneNarrationStatus = .idle,
        narrationError: String? = nil,
        duration: Double = 2.4,
        motionPreset: CarouselMotionPreset = .subtleZoom,
        captionAnchor: CGPoint = CGPoint(x: 0.5, y: 0.58),
        captionBoxWidth: Double = 0.92,
        captionFontScale: Double = 1.08,
        captionFontFamily: String? = nil,
        selectedCaptionBeatID: UUID? = nil,
        captionAlignmentStatus: NarratedCaptionAlignmentStatus = .idle,
        captionAlignmentError: String? = nil
    ) {
        self.id = id
        self.imageURL = imageURL
        self.displayName = displayName
        self.script = script
        self.captionBeats = captionBeats
        self.narrationAudioURL = narrationAudioURL
        self.narrationAudioDuration = narrationAudioDuration
        self.narrationStatus = narrationStatus
        self.narrationError = narrationError
        self.duration = duration
        self.motionPreset = motionPreset
        self.captionAnchor = captionAnchor
        self.captionBoxWidth = captionBoxWidth
        self.captionFontScale = captionFontScale
        self.captionFontFamily = captionFontFamily
        self.selectedCaptionBeatID = selectedCaptionBeatID
        self.captionAlignmentStatus = captionAlignmentStatus
        self.captionAlignmentError = captionAlignmentError
    }

    static func == (lhs: NarratedImageScene, rhs: NarratedImageScene) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Observable
final class NarratedImageProject: Identifiable {
    var id: UUID
    var title: String
    var scenes: [NarratedImageScene]
    var selectedSceneID: UUID?
    var canvasAspect: CanvasAspectRatio
    var exportQuality: CarouselExportQuality
    var narrationEngine: NarrationEngine
    var voice: String
    var narrationEngineInstallationStatus: NarrationEngineInstallationStatus
    var isGeneratingNarration: Bool
    var isInstallingVoiceEngine: Bool
    var isInstallingCaptionAligner: Bool
    var captionAlignerInstallationStatus: NarrationEngineInstallationStatus
    var isCachingVoicePreviews: Bool
    var isPreviewingVoice: Bool
    var narrationMessage: String?
    var captionAlignmentMessage: String?

    init(id: UUID = UUID(), title: String = "Untitled Narrated Images", scenes: [NarratedImageScene] = []) {
        self.id = id
        self.title = title
        self.scenes = scenes
        self.selectedSceneID = scenes.first?.id
        self.canvasAspect = .square
        self.exportQuality = .draft
        self.narrationEngine = .defaultEngine
        self.voice = NarrationEngine.defaultEngine.defaultVoice
        self.narrationEngineInstallationStatus = .notInstalled
        self.isGeneratingNarration = false
        self.isInstallingVoiceEngine = false
        self.isInstallingCaptionAligner = false
        self.captionAlignerInstallationStatus = .notInstalled
        self.isCachingVoicePreviews = false
        self.isPreviewingVoice = false
        self.narrationMessage = nil
        self.captionAlignmentMessage = nil
    }

    deinit {
        for scene in scenes {
            NarrationService.cleanupGeneratedNarration(at: scene.narrationAudioURL)
        }
    }

    var selectedScene: NarratedImageScene? {
        guard let selectedSceneID else { return scenes.first }
        return scenes.first { $0.id == selectedSceneID } ?? scenes.first
    }

    var totalDuration: Double {
        scenes.reduce(0) { $0 + normalizedDuration(for: $1) }
    }

    func normalizedDuration(for scene: NarratedImageScene) -> Double {
        max(0.5, scene.duration)
    }

    func startTime(for sceneID: UUID) -> Double {
        var time = 0.0
        for scene in scenes {
            if scene.id == sceneID { return time }
            time += normalizedDuration(for: scene)
        }
        return 0
    }

    func timelineSample(at time: Double) -> (scene: NarratedImageScene, localTime: Double, startTime: Double)? {
        guard !scenes.isEmpty else { return nil }
        let clamped = max(0, min(time, max(0, totalDuration - 0.001)))
        var cursor = 0.0
        for scene in scenes {
            let duration = normalizedDuration(for: scene)
            if clamped < cursor + duration {
                return (scene, clamped - cursor, cursor)
            }
            cursor += duration
        }
        guard let last = scenes.last else { return nil }
        return (last, max(0, last.duration - 0.001), max(0, totalDuration - normalizedDuration(for: last)))
    }

    func timelineMetrics(for scene: NarratedImageScene) -> (start: Double, duration: Double, startFraction: Double, durationFraction: Double) {
        let duration = normalizedDuration(for: scene)
        let total = max(totalDuration, 0.001)
        let start = startTime(for: scene.id)
        return (start, duration, start / total, duration / total)
    }

    func selectScene(at time: Double) {
        if let sample = timelineSample(at: time) {
            selectedSceneID = sample.scene.id
        }
    }

    func select(_ scene: NarratedImageScene) {
        selectedSceneID = scene.id
    }

    func addScenes(_ newScenes: [NarratedImageScene]) {
        scenes.append(contentsOf: newScenes)
        if selectedSceneID == nil {
            selectedSceneID = scenes.first?.id
        }
    }

    func removeScene(id: UUID) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        NarrationService.cleanupGeneratedNarration(at: scenes[index].narrationAudioURL)
        scenes.remove(at: index)
        if selectedSceneID == id {
            selectedSceneID = scenes.isEmpty ? nil : scenes[max(0, min(index, scenes.count - 1))].id
        }
    }

    func moveScene(from source: UUID, toPositionOf target: UUID) {
        guard source != target,
              let sourceIndex = scenes.firstIndex(where: { $0.id == source }),
              let targetIndex = scenes.firstIndex(where: { $0.id == target }) else {
            return
        }
        let scene = scenes.remove(at: sourceIndex)
        scenes.insert(scene, at: max(0, min(targetIndex, scenes.count)))
        selectedSceneID = source
    }

    func activeCaption(for scene: NarratedImageScene, at localTime: Double) -> NarratedCaptionBeat? {
        let clamped = max(0, localTime)
        return scene.captionBeats.first { beat in
            let start = max(0, beat.startTime)
            let end = max(start + 0.05, beat.endTime)
            return clamped >= start && clamped < end && !beat.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func generateCaptions(for scene: NarratedImageScene) {
        scene.captionBeats = Self.captionBeats(from: scene.script, duration: normalizedDuration(for: scene))
        scene.selectedCaptionBeatID = scene.captionBeats.first?.id
        scene.captionAlignmentStatus = .estimated
        scene.captionAlignmentError = nil
        applyShortFormCaptionDefaults(to: scene)
    }

    func applyAlignedCaptions(_ beats: [NarratedCaptionBeat], to scene: NarratedImageScene) {
        scene.captionBeats = beats
        scene.selectedCaptionBeatID = scene.captionBeats.first?.id
        scene.captionAlignmentStatus = .aligned
        scene.captionAlignmentError = nil
        applyShortFormCaptionDefaults(to: scene)
    }

    func applyShortFormCaptionDefaults(to scene: NarratedImageScene) {
        scene.captionAnchor = CGPoint(x: 0.5, y: 0.58)
        scene.captionBoxWidth = 0.92
        scene.captionFontScale = scene.captionBeats.contains { $0.text.count > 22 } ? 0.96 : 1.08
        for index in scene.captionBeats.indices {
            if scene.captionBeats[index].style == .softSubtitle {
                scene.captionBeats[index].style = .boldCenter
            }
        }
    }

    func retimeCaptionsToSceneDuration(for scene: NarratedImageScene, markManual: Bool = false) {
        let oldDuration = max(scene.captionBeats.map(\.endTime).max() ?? scene.duration, 0.1)
        let newDuration = normalizedDuration(for: scene)
        for index in scene.captionBeats.indices {
            let startFraction = scene.captionBeats[index].startTime / oldDuration
            let endFraction = scene.captionBeats[index].endTime / oldDuration
            scene.captionBeats[index].startTime = max(0, min(newDuration, startFraction * newDuration))
            scene.captionBeats[index].endTime = max(
                scene.captionBeats[index].startTime + 0.08,
                min(newDuration, endFraction * newDuration)
            )
            if markManual {
                scene.captionBeats[index].alignmentSource = .manual
            }
        }
        if markManual {
            scene.captionAlignmentStatus = .aligned
        }
    }

    func updateCaptionBeatTiming(scene: NarratedImageScene, beatID: UUID, start: Double? = nil, end: Double? = nil) {
        guard let index = scene.captionBeats.firstIndex(where: { $0.id == beatID }) else { return }
        let previousEnd = index > 0 ? scene.captionBeats[index - 1].endTime : 0
        let nextStart = index < scene.captionBeats.count - 1 ? scene.captionBeats[index + 1].startTime : normalizedDuration(for: scene)
        let minimumGap = 0.08
        let currentStart = scene.captionBeats[index].startTime
        let currentEnd = scene.captionBeats[index].endTime

        if let start {
            scene.captionBeats[index].startTime = max(previousEnd, min(start, currentEnd - minimumGap))
            scene.captionBeats[index].alignmentSource = .manual
        }
        if let end {
            scene.captionBeats[index].endTime = min(nextStart, max(end, currentStart + minimumGap))
            scene.captionBeats[index].alignmentSource = .manual
        }
    }

    static func captionBeats(from script: String, duration: Double) -> [NarratedCaptionBeat] {
        let words = script
            .replacingOccurrences(of: #"[\n\r]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[.,!?;:]+(\s|$)"#, with: " ", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }

        let chunkSize: Int
        switch words.count {
        case 1...4:
            chunkSize = min(2, words.count)
        case 5...14:
            chunkSize = 2
        case 15...32:
            chunkSize = 3
        default:
            chunkSize = 4
        }
        let chunks = stride(from: 0, to: words.count, by: chunkSize).map { index in
            words[index..<min(index + chunkSize, words.count)].joined(separator: " ")
        }
        let safeDuration = max(0.8, duration)
        let slot = safeDuration / Double(chunks.count)
        return chunks.enumerated().map { index, chunk in
            let start = Double(index) * slot
            let end = index == chunks.count - 1 ? safeDuration : Double(index + 1) * slot
            return NarratedCaptionBeat(text: chunk.uppercased(), startTime: start, endTime: end)
        }
    }
}

@Observable
final class NarratedImagesWorkspace {
    var projects: [NarratedImageProject]
    var selectedProjectID: UUID?
    var isExporting = false
    var exportProgress = 0.0
    var exportStatus = ""
    var exportDetail = ""
    var exportDestinationName = ""
    var activeExportTask: Task<Void, Never>?
    var lastMessage: String?
    var lastError: String?

    init() {
        let first = NarratedImageProject(title: "Narrated Images")
        self.projects = [first]
        self.selectedProjectID = first.id
    }

    var selectedProject: NarratedImageProject {
        get {
            if let selectedProjectID,
               let project = projects.first(where: { $0.id == selectedProjectID }) {
                return project
            }
            if let first = projects.first {
                selectedProjectID = first.id
                return first
            }
            let project = NarratedImageProject(title: "Narrated Images")
            projects.append(project)
            selectedProjectID = project.id
            return project
        }
        set {
            if let index = projects.firstIndex(where: { $0.id == newValue.id }) {
                projects[index] = newValue
            } else {
                projects.append(newValue)
            }
            selectedProjectID = newValue.id
        }
    }

    func addProject() {
        let project = NarratedImageProject(title: "Narrated Images \(projects.count + 1)")
        projects.append(project)
        selectedProjectID = project.id
    }

    func closeSelectedProject() {
        guard let selectedProjectID else { return }
        projects.removeAll { $0.id == selectedProjectID }
        if projects.isEmpty {
            let project = NarratedImageProject(title: "Narrated Images")
            projects.append(project)
            self.selectedProjectID = project.id
        } else {
            self.selectedProjectID = projects.first?.id
        }
    }

    func cancelExport() {
        activeExportTask?.cancel()
        activeExportTask = nil
        isExporting = false
        exportProgress = 0
        exportStatus = ""
        exportDetail = ""
        exportDestinationName = ""
        lastMessage = "Export canceled."
        lastError = nil
    }
}
