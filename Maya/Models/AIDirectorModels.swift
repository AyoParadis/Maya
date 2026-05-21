import Foundation

enum AIDirectorPacing: String, Codable, CaseIterable, Identifiable, Sendable {
    case calm
    case balanced
    case fast

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calm: "Calm"
        case .balanced: "Balanced"
        case .fast: "Fast"
        }
    }
}

enum AIDirectorZoomIntensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case subtle
    case standard
    case dramatic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .subtle: "Barely There"
        case .standard: "Standard"
        case .dramatic: "Dramatic"
        }
    }
}

struct AIDirectorSettings: Codable, Equatable, Sendable {
    var targetLength: Double = 14
    var pacing: AIDirectorPacing = .balanced
    var zoomIntensity: AIDirectorZoomIntensity = .standard
    var hookStrength: Double = 0.75
    var endingEmphasis: Double = 0.75
    var revisionNotes: String = ""
}

enum AIDirectorStatus: Equatable, Sendable {
    case idle
    case analyzing
    case generating
    case applied
    case failed

    var label: String {
        switch self {
        case .idle: "Idle"
        case .analyzing: "Analyzing"
        case .generating: "Generating"
        case .applied: "Applied"
        case .failed: "Failed"
        }
    }

    var isWorking: Bool {
        self == .analyzing || self == .generating
    }

    var workingTitle: String {
        switch self {
        case .analyzing: "Analyzing recording"
        case .generating: "Asking local Codex CLI"
        case .applied: "Preview ready"
        case .failed: "Needs attention"
        case .idle: "Ready"
        }
    }

    var workingDetail: String {
        switch self {
        case .analyzing: "Sampling frames and reading the current timeline."
        case .generating: "Using your local Codex account to generate an edit plan."
        case .applied: "The generated edit is applied and ready to preview."
        case .failed: "Review the message, adjust settings, then retry."
        case .idle: "Load a recording and create a video when you are ready."
        }
    }
}

struct AIDirectorRun: Identifiable, Equatable {
    let id: UUID
    var status: AIDirectorStatus
    var settings: AIDirectorSettings
    var versions: [AIDirectorPlan]
    var selectedVersionID: UUID?
    var error: String?
    var runDirectory: URL?
    var originalEdit: AIDirectorAppliedEdit?

    init(settings: AIDirectorSettings = AIDirectorSettings()) {
        self.id = UUID()
        self.status = .idle
        self.settings = settings
        self.versions = []
        self.selectedVersionID = nil
        self.error = nil
        self.runDirectory = nil
        self.originalEdit = nil
    }

    var selectedPlan: AIDirectorPlan? {
        guard let selectedVersionID else { return versions.last }
        return versions.first { $0.id == selectedVersionID } ?? versions.last
    }
}

struct AIDirectorAppliedEdit: Equatable {
    var trimStart: Double
    var trimEnd: Double
    var clipTimelineStart: Double
    var animations: [ZoomSegment]
    var selectedAnimationID: ZoomSegment.ID?
}

struct AIDirectorPlan: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var schemaVersion: Int
    var targetUseCase: String
    var rationale: String
    var trimStart: Double
    var trimEnd: Double
    var zoomSegments: [AIDirectorPlanZoomSegment]
    var warnings: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case targetUseCase
        case rationale
        case trimStart
        case trimEnd
        case zoomSegments
        case warnings
    }
}

struct AIDirectorPlanZoomSegment: Codable, Equatable, Sendable {
    var startTime: Double
    var duration: Double
    var scale: Double
    var focus: String
    var transitionIn: Double
    var transitionOut: Double
    var curve: String
    var reason: String?
}
