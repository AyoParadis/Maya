import AppKit
import Foundation
import Observation

enum CarouselMotionPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case still
    case subtleZoom
    case punchZoom
    case pan
    case auto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .still: "Still"
        case .subtleZoom: "Subtle Zoom"
        case .punchZoom: "Punch Zoom"
        case .pan: "Pan"
        case .auto: "Auto"
        }
    }

    var symbol: String {
        switch self {
        case .still: "rectangle"
        case .subtleZoom: "plus.magnifyingglass"
        case .punchZoom: "scope"
        case .pan: "arrow.left.and.right"
        case .auto: "sparkles"
        }
    }
}

enum CarouselSlideStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case planned
    case drafted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .planned: "Planned"
        case .drafted: "Drafted"
        }
    }

    var symbol: String {
        switch self {
        case .planned: "list.bullet.rectangle"
        case .drafted: "pencil.and.scribble"
        }
    }
}

enum CarouselSlideNarrationStatus: String, Codable, Sendable {
    case idle
    case detecting
    case generating
    case generated
    case skipped
    case failed

    var label: String {
        switch self {
        case .idle: "Not generated"
        case .detecting: "Detecting text"
        case .generating: "Generating"
        case .generated: "Generated"
        case .skipped: "Skipped"
        case .failed: "Failed"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "waveform"
        case .detecting: "text.viewfinder"
        case .generating: "waveform"
        case .generated: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

struct CarouselBrief: Codable, Equatable, Sendable {
    var sourceContent: String
    var audience: String
    var goal: String
    var platform: String
    var brandName: String
    var brandHex: String

    static let empty = CarouselBrief(
        sourceContent: "",
        audience: "",
        goal: "Drive saves and qualified clicks",
        platform: "Instagram / LinkedIn",
        brandName: "",
        brandHex: "#6466FA"
    )
}

enum CarouselSafeZonePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case reelsTikTok
    case feedPortrait
    case square

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .reelsTikTok: "Reels / TikTok"
        case .feedPortrait: "Feed 4:5"
        case .square: "Square"
        }
    }
}

enum CarouselExportQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case draft
    case fast
    case standard
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft: "Draft"
        case .fast: "Fast"
        case .standard: "Standard"
        case .high: "High"
        }
    }

    var detail: String {
        switch self {
        case .draft: "960p max"
        case .fast: "720p-ish"
        case .standard: "1080p"
        case .high: "Full"
        }
    }

    var useCase: String {
        switch self {
        case .draft: "Fastest timing check"
        case .fast: "Quick share preview"
        case .standard: "Recommended export"
        case .high: "Best final quality"
        }
    }

    var fps: Int32 {
        switch self {
        case .draft: 15
        case .fast: 24
        case .standard, .high: 30
        }
    }

    var maxLongEdge: CGFloat {
        switch self {
        case .draft: 960
        case .fast: 1280
        case .standard: 1920
        case .high: 2688
        }
    }
}

@Observable
final class CarouselCard: Identifiable, Hashable {
    var id: UUID
    var imageURL: URL?
    var displayName: String
    var role: String
    var headline: String
    var subtitle: String
    var cta: String
    var badge: String
    var visualPrompt: String
    var rationale: String
    var status: CarouselSlideStatus
    var focalPoint: CGPoint
    var duration: Double
    var motionOverride: CarouselMotionPreset?
    var detectedNarrationText: String
    var narrationScript: String
    var narrationScriptEdited: Bool
    var narrationAudioURL: URL?
    var narrationAudioDuration: Double?
    var narrationStatus: CarouselSlideNarrationStatus
    var narrationError: String?

    init(
        id: UUID = UUID(),
        imageURL: URL? = nil,
        displayName: String,
        role: String = "",
        headline: String = "",
        subtitle: String = "",
        cta: String = "",
        badge: String = "",
        visualPrompt: String = "",
        rationale: String = "",
        status: CarouselSlideStatus = .planned,
        focalPoint: CGPoint = CGPoint(x: 0.5, y: 0.5),
        duration: Double = 2.0,
        motionOverride: CarouselMotionPreset? = nil,
        detectedNarrationText: String = "",
        narrationScript: String = "",
        narrationScriptEdited: Bool = false,
        narrationAudioURL: URL? = nil,
        narrationAudioDuration: Double? = nil,
        narrationStatus: CarouselSlideNarrationStatus = .idle,
        narrationError: String? = nil
    ) {
        self.id = id
        self.imageURL = imageURL
        self.displayName = displayName
        self.role = role
        self.headline = headline
        self.subtitle = subtitle
        self.cta = cta
        self.badge = badge
        self.visualPrompt = visualPrompt
        self.rationale = rationale
        self.status = status
        self.focalPoint = focalPoint
        self.duration = duration
        self.motionOverride = motionOverride
        self.detectedNarrationText = detectedNarrationText
        self.narrationScript = narrationScript
        self.narrationScriptEdited = narrationScriptEdited
        self.narrationAudioURL = narrationAudioURL
        self.narrationAudioDuration = narrationAudioDuration
        self.narrationStatus = narrationStatus
        self.narrationError = narrationError
    }

    static func == (lhs: CarouselCard, rhs: CarouselCard) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Observable
final class CarouselProject: Identifiable {
    var id: UUID
    var title: String
    var cards: [CarouselCard]
    var selectedCardID: UUID?
    var canvasAspect: CanvasAspectRatio
    var motionPreset: CarouselMotionPreset
    var brief: CarouselBrief
    var safeZonePreset: CarouselSafeZonePreset
    var exportQuality: CarouselExportQuality
    var defaultCardDuration: Double
    var showSafeZones: Bool
    var narrationScript: String
    var narrationEngine: NarrationEngine
    var piperVoice: String
    var narrationEngineInstallationStatus: NarrationEngineInstallationStatus
    var narrationAudioURL: URL?
    var narrationDisplayName: String?
    var isGeneratingNarration: Bool
    var isInstallingPiper: Bool
    var isCachingVoicePreviews: Bool
    var isPreviewingVoice: Bool
    var isCleaningNarrationText: Bool
    var narrationMessage: String?

    init(
        id: UUID = UUID(),
        title: String = "Untitled Carousel",
        cards: [CarouselCard] = []
    ) {
        self.id = id
        self.title = title
        self.cards = cards
        self.selectedCardID = cards.first?.id
        self.canvasAspect = .square
        self.motionPreset = .auto
        self.brief = .empty
        self.safeZonePreset = .auto
        self.exportQuality = .draft
        self.defaultCardDuration = 2.0
        self.showSafeZones = false
        self.narrationScript = ""
        self.narrationEngine = .defaultEngine
        self.piperVoice = NarrationEngine.defaultEngine.defaultVoice
        self.narrationEngineInstallationStatus = .notInstalled
        self.narrationAudioURL = nil
        self.narrationDisplayName = nil
        self.isGeneratingNarration = false
        self.isInstallingPiper = false
        self.isCachingVoicePreviews = false
        self.isPreviewingVoice = false
        self.isCleaningNarrationText = false
        self.narrationMessage = nil
    }

    deinit {
        NarrationService.cleanupGeneratedNarration(at: narrationAudioURL)
        for card in cards {
            NarrationService.cleanupGeneratedNarration(at: card.narrationAudioURL)
        }
    }

    var brandName: String {
        get { brief.brandName }
        set { brief.brandName = newValue }
    }

    var brandHex: String {
        get { brief.brandHex }
        set { brief.brandHex = newValue }
    }

    var selectedCard: CarouselCard? {
        guard let selectedCardID else { return cards.first }
        return cards.first { $0.id == selectedCardID } ?? cards.first
    }

    var exportCards: [CarouselCard] {
        cards
    }

    var narratedCards: [CarouselCard] {
        exportCards.filter { $0.narrationAudioURL != nil }
    }

    var hasSlideNarration: Bool {
        !narratedCards.isEmpty
    }

    var totalDuration: Double {
        cards.reduce(0) { $0 + max(0.2, $1.duration) }
    }

    func normalizedDuration(for card: CarouselCard) -> Double {
        max(0.2, card.duration)
    }

    func startTime(for cardID: UUID) -> Double {
        var time = 0.0
        for card in cards {
            if card.id == cardID {
                return time
            }
            time += normalizedDuration(for: card)
        }
        return 0
    }

    func timelineMetrics(for card: CarouselCard) -> (start: Double, duration: Double, startFraction: Double, durationFraction: Double) {
        let duration = normalizedDuration(for: card)
        let total = max(totalDuration, 0.001)
        let start = startTime(for: card.id)
        return (
            start: start,
            duration: duration,
            startFraction: start / total,
            durationFraction: duration / total
        )
    }

    func timelineSample(at time: Double) -> (card: CarouselCard, localTime: Double, startTime: Double)? {
        guard !cards.isEmpty else { return nil }
        let clamped = max(0, min(time, max(0, totalDuration - 0.001)))
        var cursor = 0.0
        for card in cards {
            let duration = normalizedDuration(for: card)
            if clamped < cursor + duration {
                return (card, clamped - cursor, cursor)
            }
            cursor += duration
        }
        guard let last = cards.last else { return nil }
        return (last, max(0, last.duration - 0.001), max(0, totalDuration - normalizedDuration(for: last)))
    }

    func selectCard(at time: Double) {
        if let sample = timelineSample(at: time) {
            selectedCardID = sample.card.id
        }
    }

    func select(_ card: CarouselCard) {
        selectedCardID = card.id
    }

    func addCards(_ newCards: [CarouselCard]) {
        cards.append(contentsOf: newCards)
        if selectedCardID == nil {
            selectedCardID = cards.first?.id
        }
        validate()
    }

    func removeSelectedCard() {
        guard let selectedCardID else { return }
        removeCard(id: selectedCardID)
    }

    func removeCard(id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        NarrationService.cleanupGeneratedNarration(at: cards[index].narrationAudioURL)
        cards.remove(at: index)
        if selectedCardID == id {
            selectedCardID = cards.isEmpty ? nil : cards[max(0, min(index, cards.count - 1))].id
        }
        validate()
    }

    func duplicateSelectedCard() {
        guard let selected = selectedCard else { return }
        duplicateCard(id: selected.id)
    }

    func duplicateCard(id: UUID) {
        guard let selected = cards.first(where: { $0.id == id }) else { return }
        let copy = CarouselCard(
            imageURL: selected.imageURL,
            displayName: "\(selected.displayName) copy",
            role: selected.role,
            headline: selected.headline,
            subtitle: selected.subtitle,
            cta: selected.cta,
            badge: selected.badge,
            visualPrompt: selected.visualPrompt,
            rationale: selected.rationale,
            status: .drafted,
            focalPoint: selected.focalPoint,
            duration: selected.duration,
            motionOverride: selected.motionOverride
        )
        let index = (cards.firstIndex { $0.id == selected.id } ?? cards.count - 1) + 1
        cards.insert(copy, at: min(index, cards.count))
        selectedCardID = copy.id
        validate()
    }

    func removeVoiceover(for cardID: UUID) {
        guard let card = cards.first(where: { $0.id == cardID }) else { return }
        NarrationService.cleanupGeneratedNarration(at: card.narrationAudioURL)
        card.detectedNarrationText = ""
        card.narrationScript = ""
        card.narrationScriptEdited = false
        card.narrationAudioURL = nil
        card.narrationAudioDuration = nil
        card.narrationStatus = .idle
        card.narrationError = nil
        validate()
    }

    func moveCardEarlier(id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }), index > 0 else { return }
        cards.swapAt(index, index - 1)
        selectedCardID = id
        validate()
    }

    func moveCardLater(id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }), index < cards.count - 1 else { return }
        cards.swapAt(index, index + 1)
        selectedCardID = id
        validate()
    }

    func applyDefaultDurationToAllCards() {
        let duration = max(0.5, min(8.0, defaultCardDuration))
        for card in cards {
            card.duration = duration
        }
        validate()
    }

    func moveCard(from source: UUID, before target: UUID) {
        guard source != target,
              let sourceIndex = cards.firstIndex(where: { $0.id == source }),
              let targetIndex = cards.firstIndex(where: { $0.id == target }) else {
            return
        }
        let card = cards.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        cards.insert(card, at: max(0, min(adjustedTarget, cards.count)))
        validate()
    }

    func moveCard(from source: UUID, toPositionOf target: UUID) {
        guard source != target,
              let sourceIndex = cards.firstIndex(where: { $0.id == source }),
              let targetIndex = cards.firstIndex(where: { $0.id == target }) else {
            return
        }
        let card = cards.remove(at: sourceIndex)
        cards.insert(card, at: max(0, min(targetIndex, cards.count)))
        selectedCardID = source
        validate()
    }

    func validate() {
    }
}

@Observable
final class CarouselWorkspace {
    var projects: [CarouselProject]
    var selectedProjectID: UUID?
    var isExporting: Bool = false
    var exportProgress: Double = 0
    var exportStatus: String = ""
    var exportDetail: String = ""
    var exportDestinationName: String = ""
    var activeExportTask: Task<Void, Never>?
    var lastMessage: String?
    var lastError: String?

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

    init() {
        let first = CarouselProject(title: "Launch Carousel")
        self.projects = [first]
        self.selectedProjectID = first.id
    }

    var selectedProject: CarouselProject {
        get {
            if let selectedProjectID,
               let project = projects.first(where: { $0.id == selectedProjectID }) {
                return project
            }
            if let first = projects.first {
                selectedProjectID = first.id
                return first
            }
            let project = CarouselProject(title: "Launch Carousel")
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
        let project = CarouselProject(title: "Carousel \(projects.count + 1)")
        projects.append(project)
        selectedProjectID = project.id
    }

    func closeSelectedProject() {
        guard let selectedProjectID else { return }
        projects.removeAll { $0.id == selectedProjectID }
        if projects.isEmpty {
            let project = CarouselProject(title: "Launch Carousel")
            projects.append(project)
            self.selectedProjectID = project.id
        } else {
            self.selectedProjectID = projects.first?.id
        }
    }

}
