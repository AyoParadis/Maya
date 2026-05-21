import Foundation

enum CarouselAIDirectorBridge {
    nonisolated static let schemaVersion = 2
    nonisolated static let targetUseCase = "conversionCarousel"
    nonisolated static let helperScriptName = "maya-ai-director-helper.sh"

    struct GeneratedPlanResult: Sendable {
        let plan: CarouselCreativePlan
        let runDirectory: URL
        let usedFallback: Bool
    }

    static func createOutline(for project: CarouselProject) async throws -> GeneratedPlanResult {
        let runDirectory = try makeRunDirectory()
        let metadata = outlineMetadata(for: project)

        try writeJSONObject(metadata, to: runDirectory.appendingPathComponent("metadata.json"))
        try outputSchema.write(to: runDirectory.appendingPathComponent("output-schema.json"), atomically: true, encoding: .utf8)
        try outlinePrompt(metadata: metadata).write(to: runDirectory.appendingPathComponent("prompt.txt"), atomically: true, encoding: .utf8)
        try "".write(to: runDirectory.appendingPathComponent("frame-args.txt"), atomically: true, encoding: .utf8)

        do {
            try await runHelper(in: runDirectory)
            let plan = try readGeneratedPlan(from: runDirectory.appendingPathComponent("generated-plan.json"))
            try validate(plan: plan, project: project)
            try writeJSONObject(planObject(plan), to: runDirectory.appendingPathComponent("validated-plan.json"))
            return GeneratedPlanResult(plan: plan, runDirectory: runDirectory, usedFallback: false)
        } catch {
            let plan = fallbackPlan(for: project, warning: error.localizedDescription)
            try writeJSONObject(planObject(plan), to: runDirectory.appendingPathComponent("fallback-plan.json"))
            return GeneratedPlanResult(plan: plan, runDirectory: runDirectory, usedFallback: true)
        }
    }

    static func draftSlide(for project: CarouselProject, cardID: UUID) async throws -> GeneratedPlanResult {
        guard project.cards.contains(where: { $0.id == cardID }) else { throw CarouselAIDirectorError.invalidCardIDs }

        let runDirectory = try makeRunDirectory()
        let metadata = slideMetadata(for: project, activeCardID: cardID)

        try writeJSONObject(metadata, to: runDirectory.appendingPathComponent("metadata.json"))
        try outputSchema.write(to: runDirectory.appendingPathComponent("output-schema.json"), atomically: true, encoding: .utf8)
        try slidePrompt(metadata: metadata).write(to: runDirectory.appendingPathComponent("prompt.txt"), atomically: true, encoding: .utf8)
        try "".write(to: runDirectory.appendingPathComponent("frame-args.txt"), atomically: true, encoding: .utf8)

        do {
            try await runHelper(in: runDirectory)
            let plan = try readGeneratedPlan(from: runDirectory.appendingPathComponent("generated-plan.json"))
            try validate(plan: plan, project: project)
            guard plan.cards.contains(where: { $0.id == cardID }) else { throw CarouselAIDirectorError.invalidCardIDs }
            try writeJSONObject(planObject(plan), to: runDirectory.appendingPathComponent("validated-plan.json"))
            return GeneratedPlanResult(plan: plan, runDirectory: runDirectory, usedFallback: false)
        } catch {
            let plan = fallbackDraftPlan(for: project, cardID: cardID, warning: error.localizedDescription)
            try writeJSONObject(planObject(plan), to: runDirectory.appendingPathComponent("fallback-plan.json"))
            return GeneratedPlanResult(plan: plan, runDirectory: runDirectory, usedFallback: true)
        }
    }

    static func fallbackPlan(for project: CarouselProject, warning: String?) -> CarouselCreativePlan {
        let roles = project.formula.roles
        let orderedIDs = recommendedOrder(for: project)
        let orderedCards: [CarouselCard]
        if project.cards.isEmpty {
            orderedCards = roles.enumerated().map { index, role in
                CarouselCard(id: UUID(), displayName: "Slide \(index + 1)", role: role, duration: project.defaultCardDuration)
            }
        } else {
            orderedCards = orderedIDs.compactMap { id in project.cards.first { $0.id == id } }
        }
        let cardPlans = orderedCards.enumerated().map { index, card in
            let role = roles[index % roles.count]
            return CarouselCardPlan(
                id: card.id,
                role: role,
                headline: card.headline.isEmpty ? fallbackHeadline(role: role, index: index) : card.headline,
                subtitle: card.subtitle.isEmpty ? fallbackSubtitle(role: role) : card.subtitle,
                cta: card.cta.isEmpty && index == orderedCards.count - 1 ? "Try it today" : card.cta,
                badge: card.badge.isEmpty && index == 0 ? "New" : card.badge,
                visualPrompt: card.visualPrompt.isEmpty ? fallbackVisualPrompt(role: role, project: project) : card.visualPrompt,
                status: card.headline.isEmpty ? .planned : card.status,
                duration: max(0.8, min(4.0, card.duration)),
                motion: card.motionOverride ?? (role.localizedCaseInsensitiveContains("CTA") ? .subtleZoom : project.motionPreset),
                focalX: card.focalPoint.x,
                focalY: card.focalPoint.y,
                reason: "Fallback \(role.lowercased()) card based on the selected carousel template."
            )
        }

        var warnings: [String] = []
        if let warning {
            warnings.insert("Used local fallback because Codex could not generate a carousel plan: \(warning)", at: 0)
        }

        return CarouselCreativePlan(
            schemaVersion: schemaVersion,
            targetUseCase: targetUseCase,
            rationale: "Built a conversion-focused carousel flow from the selected template and current card order.",
            orderedCardIDs: orderedCards.map(\.id),
            cards: cardPlans,
            warnings: Array(warnings.prefix(8))
        )
    }

    static func fallbackDraftPlan(for project: CarouselProject, cardID: UUID, warning: String?) -> CarouselCreativePlan {
        var plan = project.plan ?? fallbackPlan(for: project, warning: nil)
        guard let card = project.cards.first(where: { $0.id == cardID }) else { return plan }
        let index = project.cards.firstIndex(where: { $0.id == cardID }) ?? 0
        let role = card.role.isEmpty ? project.formula.roles[index % project.formula.roles.count] : card.role
        let draft = CarouselCardPlan(
            id: card.id,
            role: role,
            headline: card.headline.isEmpty ? fallbackHeadline(role: role, index: index) : card.headline,
            subtitle: card.subtitle.isEmpty ? fallbackSubtitle(role: role) : card.subtitle,
            cta: role.localizedCaseInsensitiveContains("CTA") && card.cta.isEmpty ? "Save this for later" : card.cta,
            badge: index == 0 && card.badge.isEmpty ? "Start here" : card.badge,
            visualPrompt: card.visualPrompt.isEmpty ? fallbackVisualPrompt(role: role, project: project) : card.visualPrompt,
            status: .drafted,
            duration: max(0.8, min(4.0, card.duration)),
            motion: card.motionOverride ?? project.motionPreset,
            focalX: card.focalPoint.x,
            focalY: card.focalPoint.y,
            reason: "Drafted the \(role.lowercased()) slide from the current carousel brief."
        )
        if let existing = plan.cards.firstIndex(where: { $0.id == cardID }) {
            plan.cards[existing] = draft
        } else {
            plan.cards.append(draft)
            plan.orderedCardIDs.append(cardID)
        }
        if let warning {
            plan.warnings.insert("Used local fallback because Codex could not draft this slide: \(warning)", at: 0)
        }
        return plan
    }

    private static func recommendedOrder(for project: CarouselProject) -> [UUID] {
        let withText = project.cards.filter { !$0.headline.isEmpty || !$0.badge.isEmpty }
        let withoutText = project.cards.filter { $0.headline.isEmpty && $0.badge.isEmpty }
        return (withText + withoutText).map(\.id)
    }

    private static func fallbackHeadline(role: String, index: Int) -> String {
        if role.localizedCaseInsensitiveContains("CTA") { return "Ready to make it easier?" }
        if role.localizedCaseInsensitiveContains("Proof") { return "Built for the moments that matter" }
        if role.localizedCaseInsensitiveContains("Feature") { return "A clearer way to get it done" }
        if role.localizedCaseInsensitiveContains("Problem") { return "Still doing this the hard way?" }
        if index == 0 { return "Start with the payoff" }
        return role
    }

    private static func fallbackSubtitle(role: String) -> String {
        if role.localizedCaseInsensitiveContains("CTA") { return "Give viewers one simple next step." }
        if role.localizedCaseInsensitiveContains("Proof") { return "Show the result, not just the interface." }
        return "Keep the message short, visual, and easy to scan."
    }

    private static func fallbackVisualPrompt(role: String, project: CarouselProject) -> String {
        let brand = project.brandName.isEmpty ? "the product" : project.brandName
        return "Use a clean \(project.canvasAspect.shortLabel) composition for \(brand), focused on the \(role.lowercased()) message with readable overlay text and strong product visibility."
    }

    private static func validate(plan: CarouselCreativePlan, project: CarouselProject) throws {
        guard plan.schemaVersion == schemaVersion else { throw CarouselAIDirectorError.unsupportedSchema(plan.schemaVersion) }
        guard plan.targetUseCase == targetUseCase else { throw CarouselAIDirectorError.unsupportedUseCase(plan.targetUseCase) }
        let allowed = Set(project.cards.map(\.id)).union(Set(plan.cards.map(\.id)))
        guard Set(plan.orderedCardIDs).isSubset(of: allowed), !plan.orderedCardIDs.isEmpty else {
            throw CarouselAIDirectorError.invalidCardIDs
        }
        for card in plan.cards {
            guard allowed.contains(card.id) else { throw CarouselAIDirectorError.invalidCardIDs }
            guard card.duration >= 0.5, card.duration <= 8.0 else { throw CarouselAIDirectorError.invalidDuration }
            guard (0...1).contains(card.focalX), (0...1).contains(card.focalY) else {
                throw CarouselAIDirectorError.invalidFocalPoint
            }
        }
    }

    private static func outlineMetadata(for project: CarouselProject) -> [String: Any] {
        let cards = project.cards.isEmpty
            ? project.formula.roles.enumerated().map { index, role in
                ["id": UUID().uuidString, "n": index + 1, "role": role] as [String: Any]
            }
            : project.cards.enumerated().map { index, card in
                [
                    "id": card.id.uuidString,
                    "n": index + 1,
                    "name": card.displayName,
                    "role": card.role,
                    "hasImage": card.imageURL != nil
                ] as [String: Any]
            }
        return [
            "title": project.title,
            "brief": [
                "content": project.brief.sourceContent,
                "audience": project.brief.audience,
                "goal": project.brief.goal,
                "platform": project.brief.platform,
                "brand": project.brief.brandName,
                "formula": project.formula.label,
                "roles": project.formula.roles
            ],
            "aspect": project.canvasAspect.shortLabel,
            "cards": cards
        ]
    }

    private static func slideMetadata(for project: CarouselProject, activeCardID: UUID) -> [String: Any] {
        guard let active = project.cards.first(where: { $0.id == activeCardID }) else {
            return outlineMetadata(for: project)
        }
        let activeIndex = (project.cards.firstIndex { $0.id == activeCardID } ?? 0) + 1
        let approvedContext = project.cards
            .filter { $0.status == .approved }
            .prefix(4)
            .map { approved in
                [
                    "n": (project.cards.firstIndex { card in card.id == approved.id } ?? 0) + 1,
                    "role": approved.role,
                    "headline": approved.headline
                ] as [String: Any]
            }
        return [
            "title": project.title,
            "brief": [
                "content": project.brief.sourceContent,
                "audience": project.brief.audience,
                "goal": project.brief.goal,
                "platform": project.brief.platform,
                "brand": project.brief.brandName
            ],
            "aspect": project.canvasAspect.shortLabel,
            "approved": approvedContext,
            "active": [
                "id": active.id.uuidString,
                "n": activeIndex,
                "role": active.role,
                "headline": active.headline,
                "subtitle": active.subtitle,
                "cta": active.cta,
                "badge": active.badge,
                "visualPrompt": active.visualPrompt,
                "hasImage": active.imageURL != nil
            ] as [String: Any]
        ]
    }

    private static func outlinePrompt(metadata: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return """
        Create a concise carousel outline. Use only the supplied brief and card IDs.
        Return JSON only. Keep copy fields empty unless the user already provided them.
        Include one short visualPrompt and reason per slide. Do not generate images.

        Data:
        \(json)
        """
    }

    private static func slidePrompt(metadata: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return """
        Draft only the active carousel slide. Return JSON only with orderedCardIDs containing only the active ID and cards containing only the active card.
        Keep text short. Preserve existing non-empty text unless improving it clearly helps. Do not generate images.

        Data:
        \(json)
        """
    }

    private static var outputSchema: String {
        """
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["schemaVersion", "targetUseCase", "rationale", "orderedCardIDs", "cards", "warnings"],
          "properties": {
            "schemaVersion": { "type": "integer", "const": 2 },
            "targetUseCase": { "type": "string", "const": "conversionCarousel" },
            "rationale": { "type": "string" },
            "orderedCardIDs": { "type": "array", "items": { "type": "string" } },
            "cards": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["id", "role", "visualPrompt", "reason"],
                "properties": {
                  "id": { "type": "string" },
                  "role": { "type": "string" },
                  "headline": { "type": "string" },
                  "subtitle": { "type": "string" },
                  "cta": { "type": "string" },
                  "badge": { "type": "string" },
                  "visualPrompt": { "type": "string" },
                  "status": { "type": "string", "enum": ["planned", "drafted", "approved"] },
                  "duration": { "type": "number", "minimum": 0.5, "maximum": 8 },
                  "motion": { "type": "string", "enum": ["still", "subtleZoom", "punchZoom", "pan", "auto"] },
                  "focalX": { "type": "number", "minimum": 0, "maximum": 1 },
                  "focalY": { "type": "number", "minimum": 0, "maximum": 1 },
                  "reason": { "type": "string" }
                }
              }
            },
            "warnings": { "type": "array", "items": { "type": "string" } }
          }
        }
        """
    }

    private static func runHelper(in runDirectory: URL) async throws {
        guard let helperURL = helperURL() else { throw CarouselAIDirectorError.helperUnavailable }
        guard let codexPath = codexPath() else { throw CarouselAIDirectorError.codexNotFound }

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
                throw CarouselAIDirectorError.codexLoginRequired
            }
            throw CarouselAIDirectorError.helperFailed(stderr.isEmpty ? stdout : stderr)
        }
    }

    private static func makeRunDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let runs = base
            .appendingPathComponent("Maya AI Studio", isDirectory: true)
            .appendingPathComponent("Carousel Director", isDirectory: true)
            .appendingPathComponent("Runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
        let dir = runs.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func helperURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent == helperScriptName {
            return url
        }
        return nil
    }

    private static func codexPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func readGeneratedPlan(from url: URL) throws -> CarouselCreativePlan {
        let data = try Data(contentsOf: url)
        do {
            return try parsePlan(from: data)
        } catch {
            guard let text = String(data: data, encoding: .utf8),
                  let jsonRange = text.range(of: #"\{[\s\S]*\}"#, options: .regularExpression),
                  let jsonData = String(text[jsonRange]).data(using: .utf8) else {
                throw CarouselAIDirectorError.invalidJSON
            }
            return try parsePlan(from: jsonData)
        }
    }

    private static func parsePlan(from data: Data) throws -> CarouselCreativePlan {
        let decoder = JSONDecoder()
        let raw = try decoder.decode(RawCarouselCreativePlan.self, from: data)
        return try raw.plan()
    }

    private static func writeJSONObject(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    private static func planObject(_ plan: CarouselCreativePlan) -> [String: Any] {
        [
            "schemaVersion": plan.schemaVersion,
            "targetUseCase": plan.targetUseCase,
            "rationale": plan.rationale,
            "orderedCardIDs": plan.orderedCardIDs.map(\.uuidString),
            "cards": plan.cards.map {
                [
                    "id": $0.id.uuidString,
                    "role": $0.role,
                    "headline": $0.headline,
                    "subtitle": $0.subtitle,
                    "cta": $0.cta,
                    "badge": $0.badge,
                    "visualPrompt": $0.visualPrompt,
                    "status": $0.status.rawValue,
                    "duration": $0.duration,
                    "motion": $0.motion.rawValue,
                    "focalX": $0.focalX,
                    "focalY": $0.focalY,
                    "reason": $0.reason
                ] as [String: Any]
            },
            "warnings": plan.warnings
        ]
    }
}

private struct RawCarouselCreativePlan: Decodable {
    var schemaVersion: Int
    var targetUseCase: String
    var rationale: String
    var orderedCardIDs: [String]
    var cards: [RawCardPlan]
    var warnings: [String]

    func plan() throws -> CarouselCreativePlan {
        CarouselCreativePlan(
            schemaVersion: schemaVersion,
            targetUseCase: targetUseCase,
            rationale: rationale,
            orderedCardIDs: try orderedCardIDs.map {
                guard let id = UUID(uuidString: $0) else { throw CarouselAIDirectorError.invalidCardIDs }
                return id
            },
            cards: try cards.map { try $0.cardPlan() },
            warnings: warnings
        )
    }
}

private struct RawCardPlan: Decodable {
    var id: String
    var role: String
    var headline: String?
    var subtitle: String?
    var cta: String?
    var badge: String?
    var visualPrompt: String?
    var status: CarouselSlideStatus?
    var duration: Double?
    var motion: CarouselMotionPreset?
    var focalX: Double?
    var focalY: Double?
    var reason: String

    func cardPlan() throws -> CarouselCardPlan {
        guard let uuid = UUID(uuidString: id) else { throw CarouselAIDirectorError.invalidCardIDs }
        return CarouselCardPlan(
            id: uuid,
            role: role,
            headline: headline ?? "",
            subtitle: subtitle ?? "",
            cta: cta ?? "",
            badge: badge ?? "",
            visualPrompt: visualPrompt ?? "",
            status: status ?? .planned,
            duration: duration ?? 2.0,
            motion: motion ?? .auto,
            focalX: focalX ?? 0.5,
            focalY: focalY ?? 0.5,
            reason: reason
        )
    }
}

enum CarouselAIDirectorError: LocalizedError {
    case helperUnavailable
    case helperFailed(String)
    case codexNotFound
    case codexLoginRequired
    case invalidJSON
    case unsupportedSchema(Int)
    case unsupportedUseCase(String)
    case invalidCardIDs
    case invalidDuration
    case invalidFocalPoint

    var errorDescription: String? {
        switch self {
        case .helperUnavailable: "Carousel Director helper unavailable."
        case .helperFailed(let detail): "Carousel Director helper failed: \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .codexNotFound: "Codex CLI was not found. Maya used the local carousel fallback."
        case .codexLoginRequired: "Codex login required. Run `codex login` in Terminal, then retry."
        case .invalidJSON: "The carousel plan is not valid JSON."
        case .unsupportedSchema(let version): "Unsupported carousel schema version \(version)."
        case .unsupportedUseCase(let useCase): "Unsupported carousel use case: \(useCase)."
        case .invalidCardIDs: "The carousel plan references unknown cards."
        case .invalidDuration: "The carousel plan contains an invalid card duration."
        case .invalidFocalPoint: "The carousel plan contains an invalid focal point."
        }
    }
}
