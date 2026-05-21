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

enum CarouselFormula: String, Codable, CaseIterable, Identifiable, Sendable {
    case problemBenefitProofFeaturesCTA
    case beforeAfterHowItWorksTestimonialOffer
    case hookFeaturesProofCTA
    case appWalkthroughResultObjectionCTA
    case promoValueUrgencyCTA
    case mythTruthFrameworkCTA
    case checklistSaveCTA

    var id: String { rawValue }

    var label: String {
        switch self {
        case .problemBenefitProofFeaturesCTA: "Problem -> Benefit -> Proof -> Features -> CTA"
        case .beforeAfterHowItWorksTestimonialOffer: "Before -> After -> How It Works -> Testimonial -> Offer"
        case .hookFeaturesProofCTA: "Hook -> Features -> Proof -> CTA"
        case .appWalkthroughResultObjectionCTA: "App Walkthrough -> Result -> Objection -> CTA"
        case .promoValueUrgencyCTA: "Promo -> Value -> Urgency -> CTA"
        case .mythTruthFrameworkCTA: "Myth -> Truth -> Framework -> CTA"
        case .checklistSaveCTA: "Checklist -> Save CTA"
        }
    }

    var roles: [String] {
        switch self {
        case .problemBenefitProofFeaturesCTA:
            return ["Problem", "Benefit", "Proof", "Feature", "CTA"]
        case .beforeAfterHowItWorksTestimonialOffer:
            return ["Before", "After", "How it works", "Testimonial", "Offer"]
        case .hookFeaturesProofCTA:
            return ["Hook", "Feature", "Feature", "Feature", "Social proof", "CTA"]
        case .appWalkthroughResultObjectionCTA:
            return ["Walkthrough", "Result", "Objection", "CTA"]
        case .promoValueUrgencyCTA:
            return ["Promo", "Value", "Urgency", "CTA"]
        case .mythTruthFrameworkCTA:
            return ["Hook", "Myth", "Truth", "Framework", "Example", "CTA"]
        case .checklistSaveCTA:
            return ["Hook", "Checklist", "Checklist", "Checklist", "Checklist", "Takeaway", "Save CTA"]
        }
    }
}

enum CarouselSlideStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case planned
    case drafted
    case approved

    var id: String { rawValue }

    var label: String {
        switch self {
        case .planned: "Planned"
        case .drafted: "Drafted"
        case .approved: "Approved"
        }
    }

    var symbol: String {
        switch self {
        case .planned: "list.bullet.rectangle"
        case .drafted: "pencil.and.scribble"
        case .approved: "checkmark.circle.fill"
        }
    }
}

enum CarouselPipelineState: String, Codable, Sendable {
    case needsBrief
    case readyForOutline
    case outlining
    case readyForDraft
    case draftingSlide
    case reviewingSlide
    case complete
}

struct CarouselBrief: Codable, Equatable, Sendable {
    var sourceContent: String
    var audience: String
    var goal: String
    var platform: String
    var brandName: String
    var brandHex: String
    var formula: CarouselFormula

    static let empty = CarouselBrief(
        sourceContent: "",
        audience: "",
        goal: "Drive saves and qualified clicks",
        platform: "Instagram / LinkedIn",
        brandName: "",
        brandHex: "#6466FA",
        formula: .hookFeaturesProofCTA
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

struct CarouselCardPlan: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var role: String
    var headline: String
    var subtitle: String
    var cta: String
    var badge: String
    var visualPrompt: String
    var status: CarouselSlideStatus
    var duration: Double
    var motion: CarouselMotionPreset
    var focalX: Double
    var focalY: Double
    var reason: String
}

struct CarouselCreativePlan: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var schemaVersion: Int
    var targetUseCase: String
    var rationale: String
    var orderedCardIDs: [UUID]
    var cards: [CarouselCardPlan]
    var warnings: [String]
}

struct CarouselValidationIssue: Identifiable, Hashable, Sendable {
    enum Severity: String, Hashable, Sendable {
        case info
        case warning
        case problem
    }

    let id = UUID()
    var severity: Severity
    var cardID: UUID?
    var message: String
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
        motionOverride: CarouselMotionPreset? = nil
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
    var pipelineState: CarouselPipelineState
    var safeZonePreset: CarouselSafeZonePreset
    var defaultCardDuration: Double
    var showSafeZones: Bool
    var plan: CarouselCreativePlan?
    var validationIssues: [CarouselValidationIssue]

    init(
        id: UUID = UUID(),
        title: String = "Untitled Carousel",
        cards: [CarouselCard] = []
    ) {
        self.id = id
        self.title = title
        self.cards = cards
        self.selectedCardID = cards.first?.id
        self.canvasAspect = .vertical9x16
        self.motionPreset = .auto
        self.brief = .empty
        self.pipelineState = .needsBrief
        self.safeZonePreset = .auto
        self.defaultCardDuration = 2.0
        self.showSafeZones = true
        self.plan = nil
        self.validationIssues = []
    }

    var formula: CarouselFormula {
        get { brief.formula }
        set { brief.formula = newValue }
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

    var approvedCards: [CarouselCard] {
        cards.filter { $0.status == .approved }
    }

    var exportCards: [CarouselCard] {
        let approved = approvedCards
        return approved.isEmpty ? cards : approved
    }

    var activePipelineCard: CarouselCard? {
        cards.first { $0.status != .approved } ?? cards.first
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
        cards.removeAll { $0.id == selectedCardID }
        self.selectedCardID = cards.first?.id
        validate()
    }

    func duplicateSelectedCard() {
        guard let selected = selectedCard else { return }
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

    func applyOutline(_ plan: CarouselCreativePlan) {
        let existingByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        var created: [CarouselCard] = []
        for cardPlan in plan.cards where existingByID[cardPlan.id] == nil {
            created.append(
                CarouselCard(
                    id: cardPlan.id,
                    displayName: cardPlan.role.isEmpty ? "Slide \(created.count + 1)" : cardPlan.role,
                    role: cardPlan.role,
                    headline: cardPlan.headline,
                    subtitle: cardPlan.subtitle,
                    cta: cardPlan.cta,
                    badge: cardPlan.badge,
                    visualPrompt: cardPlan.visualPrompt,
                    rationale: cardPlan.reason,
                    status: cardPlan.status,
                    duration: max(0.5, min(8.0, cardPlan.duration)),
                    motionOverride: cardPlan.motion
                )
            )
        }
        let allCards = cards + created
        let allByID = Dictionary(uniqueKeysWithValues: allCards.map { ($0.id, $0) })
        let ordered = plan.orderedCardIDs.compactMap { allByID[$0] }
        let leftovers = allCards.filter { !plan.orderedCardIDs.contains($0.id) }
        cards = ordered + leftovers

        for cardPlan in plan.cards {
            guard let card = cards.first(where: { $0.id == cardPlan.id }) else { continue }
            card.role = cardPlan.role
            card.headline = cardPlan.headline
            card.subtitle = cardPlan.subtitle
            card.cta = cardPlan.cta
            card.badge = cardPlan.badge
            card.visualPrompt = cardPlan.visualPrompt
            card.rationale = cardPlan.reason
            card.status = cardPlan.status
            card.duration = max(0.5, min(8.0, cardPlan.duration))
            card.motionOverride = cardPlan.motion
            card.focalPoint = CGPoint(
                x: max(0, min(1, cardPlan.focalX)),
                y: max(0, min(1, cardPlan.focalY))
            )
        }

        self.plan = plan
        selectedCardID = activePipelineCard?.id ?? cards.first?.id
        pipelineState = cards.isEmpty ? .readyForOutline : .readyForDraft
        validate(extraWarnings: plan.warnings)
    }

    func apply(plan: CarouselCreativePlan) {
        applyOutline(plan)
    }

    func applySlideDraft(_ cardPlan: CarouselCardPlan) {
        guard let card = cards.first(where: { $0.id == cardPlan.id }) else { return }
        card.role = cardPlan.role
        card.headline = cardPlan.headline
        card.subtitle = cardPlan.subtitle
        card.cta = cardPlan.cta
        card.badge = cardPlan.badge
        card.visualPrompt = cardPlan.visualPrompt
        card.rationale = cardPlan.reason
        card.status = .drafted
        card.duration = max(0.5, min(8.0, cardPlan.duration))
        card.motionOverride = cardPlan.motion
        card.focalPoint = CGPoint(x: max(0, min(1, cardPlan.focalX)), y: max(0, min(1, cardPlan.focalY)))
        if var plan {
            if let cardIndex = plan.cards.firstIndex(where: { $0.id == cardPlan.id }) {
                plan.cards[cardIndex] = cardPlan
            } else {
                plan.cards.append(cardPlan)
                plan.orderedCardIDs.append(cardPlan.id)
            }
            self.plan = plan
        }
        selectedCardID = card.id
        pipelineState = .reviewingSlide
        validate()
    }

    func approveSelectedSlide() {
        guard let card = selectedCard else { return }
        card.status = .approved
        if var plan,
           let cardIndex = plan.cards.firstIndex(where: { $0.id == card.id }) {
            plan.cards[cardIndex].status = .approved
            self.plan = plan
        }
        selectedCardID = activePipelineCard?.id ?? card.id
        pipelineState = cards.allSatisfy { $0.status == .approved } ? .complete : .readyForDraft
        validate()
    }

    func validate(extraWarnings: [String] = []) {
        validationIssues = extraWarnings.map {
            CarouselValidationIssue(severity: .info, cardID: nil, message: $0)
        }
    }
}

@Observable
final class CarouselWorkspace {
    var projects: [CarouselProject]
    var selectedProjectID: UUID?
    var isExporting: Bool = false
    var exportProgress: Double = 0
    var lastMessage: String?
    var lastError: String?
    var isGeneratingPlan: Bool = false
    var runDirectory: URL?

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
