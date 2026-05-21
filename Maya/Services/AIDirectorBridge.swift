import AVFoundation
import AppKit
import Foundation

enum AIDirectorBridge {
    nonisolated static let schemaVersion = 1
    nonisolated static let targetUseCase = "socialDemo"
    nonisolated static let allowedEditScope = "trimAndZooms"
    nonisolated static let bundleFileName = "maya-ai-bundle.json"
    nonisolated static let promptFileName = "PROMPT.md"
    nonisolated static let editPlanFileName = "maya-edit-plan.json"
    nonisolated static let maxFrameCount = 12
    nonisolated static let helperScriptName = "maya-ai-director-helper.sh"
    nonisolated private static let minTrimDuration = 0.5
    nonisolated private static let allowedZoomScaleRange = 1.0...2.5
    nonisolated private static let allowedZoomDurationRange = 0.4...10.0
    nonisolated private static let allowedZoomTransitionRange = 0.05...2.0

    struct GeneratedPlanResult: Sendable {
        let plan: AIDirectorPlan
        let runDirectory: URL
        let usedFallback: Bool
    }

    struct GenerationContext: Sendable {
        let videoURL: URL
        let durationSeconds: Double
        let videoNaturalSize: CGSize
        let trimStartTime: Double
        let trimEndTime: Double
        let settings: AIDirectorSettings
        let previousPlan: AIDirectorPlan?
    }

    enum ZoomMotionProfileKind: Sendable {
        case barelyThere
        case standard
        case dramatic
    }

    struct ZoomMotionProfile: Sendable {
        let kind: ZoomMotionProfileKind
        let displayName: String
        let isBarelyThere: Bool
        let scaleRange: ClosedRange<Double>
        let durationRange: ClosedRange<Double>
        let transitionRange: ClosedRange<Double>
        let allowedCurves: Set<AnimationCurve>
        let preferredCurve: AnimationCurve
        let focusSequence: [ZoomFocus]
        let maxZoomCount: Int
    }

    static func createDirectedEdit(for project: Project) throws -> String {
        guard project.videoURL != nil, project.durationSeconds > 0 else {
            throw AIDirectorError.noVideo
        }

        let plan = fallbackPlan(for: project, settings: AIDirectorSettings())
        try apply(plan: plan, to: project, shouldPlay: true)

        let zoomCount = plan.zoomSegments.count
        let zoomLabel = zoomCount == 1 ? "1 zoom" : "\(zoomCount) zooms"
        return "AI Director created a \(format(plan.trimEnd - plan.trimStart))s social edit with \(zoomLabel)."
    }

    static func generatePlan(
        for project: Project,
        settings: AIDirectorSettings,
        previousPlan: AIDirectorPlan?
    ) async throws -> GeneratedPlanResult {
        guard let videoURL = project.videoURL, project.durationSeconds > 0 else {
            throw AIDirectorError.noVideo
        }

        let context = GenerationContext(
            videoURL: videoURL,
            durationSeconds: project.durationSeconds,
            videoNaturalSize: project.videoNaturalSize,
            trimStartTime: project.trimStartTime,
            trimEndTime: project.trimEndTime,
            settings: settings,
            previousPlan: previousPlan
        )

        return try await generatePlan(from: context)
    }

    nonisolated static func generatePlan(from context: GenerationContext) async throws -> GeneratedPlanResult {
        let runDirectory = try makeRunDirectory()
        let frameDirectory = runDirectory.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: frameDirectory, withIntermediateDirectories: true)

        let frames = try await writeFrames(from: context.videoURL, duration: context.durationSeconds, to: frameDirectory)
        let metadata = AIDirectorRunMetadata(
            schemaVersion: schemaVersion,
            targetUseCase: targetUseCase,
            allowedEditScope: allowedEditScope,
            sourceDuration: rounded(context.durationSeconds),
            videoWidth: rounded(Double(context.videoNaturalSize.width)),
            videoHeight: rounded(Double(context.videoNaturalSize.height)),
            currentTrimStart: rounded(context.trimStartTime),
            currentTrimEnd: rounded(context.trimEndTime),
            settings: context.settings,
            previousPlan: context.previousPlan,
            frames: frames
        )

        try writeJSONObject(metadataJSONObject(metadata), to: runDirectory.appendingPathComponent("metadata.json"))
        try outputSchema.write(
            to: runDirectory.appendingPathComponent("output-schema.json"),
            atomically: true,
            encoding: .utf8
        )
        try prompt(for: metadata).write(
            to: runDirectory.appendingPathComponent("prompt.txt"),
            atomically: true,
            encoding: .utf8
        )
        try frames
            .map { runDirectory.appendingPathComponent($0.fileName).path }
            .joined(separator: "\n")
            .write(to: runDirectory.appendingPathComponent("frame-args.txt"), atomically: true, encoding: .utf8)

        do {
            try await runHelper(in: runDirectory)
            let generatedPlan = try readGeneratedPlan(from: runDirectory.appendingPathComponent("generated-plan.json"))
            let plan = soften(generatedPlan, for: context.settings)
            try validate(plan: plan, duration: context.durationSeconds)
            try writeJSONObject(planJSONObject(plan), to: runDirectory.appendingPathComponent("validated-plan.json"))
            return GeneratedPlanResult(plan: plan, runDirectory: runDirectory, usedFallback: false)
        } catch {
            let plan = fallbackPlan(for: context, warning: error.localizedDescription)
            try writeJSONObject(planJSONObject(plan), to: runDirectory.appendingPathComponent("fallback-plan.json"))
            return GeneratedPlanResult(plan: plan, runDirectory: runDirectory, usedFallback: true)
        }
    }

    static func apply(plan: AIDirectorPlan, to project: Project, shouldPlay: Bool) throws {
        try validate(plan: plan, duration: project.durationSeconds)
        let segments = try plan.zoomSegments.map { zoom -> ZoomSegment in
            guard let focus = ZoomFocus(rawValue: zoom.focus) else {
                throw AIDirectorError.invalidFocus(zoom.focus)
            }
            guard let curve = AnimationCurve(rawValue: zoom.curve) else {
                throw AIDirectorError.invalidCurve(zoom.curve)
            }
            var segment = ZoomSegment(
                startTime: zoom.startTime,
                duration: zoom.duration,
                scale: CGFloat(zoom.scale),
                focus: focus,
                transitionIn: zoom.transitionIn,
                transitionOut: zoom.transitionOut,
                curve: curve
            )
            segment.normalize()
            return segment
        }

        project.trimStartTime = plan.trimStart
        project.trimEndTime = plan.trimEnd
        project.clipTimelineStart = 0
        project.animations = segments
        project.selectedAnimationID = segments.first?.id
        project.seek(to: 0)
        if shouldPlay {
            project.setPlayback(true)
        }
    }

    static func exportBundle(project: Project, to destination: URL) async throws {
        guard let videoURL = project.videoURL else {
            throw AIDirectorError.noVideo
        }

        let frameDirectory = destination.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: frameDirectory.path) {
            try FileManager.default.removeItem(at: frameDirectory)
        }
        try FileManager.default.createDirectory(at: frameDirectory, withIntermediateDirectories: true)

        let frames = try await writeFrames(from: videoURL, duration: project.durationSeconds, to: frameDirectory)
        let bundle = AIBundle(
            schemaVersion: schemaVersion,
            appName: "Maya AI Studio",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            targetUseCase: targetUseCase,
            allowedEditScope: allowedEditScope,
            source: AIBundle.Source(
                displayName: project.displayName,
                durationSeconds: rounded(project.durationSeconds),
                videoWidth: rounded(Double(project.videoNaturalSize.width)),
                videoHeight: rounded(Double(project.videoNaturalSize.height))
            ),
            timeline: AIBundle.Timeline(
                trimStart: rounded(project.trimStartTime),
                trimEnd: rounded(project.trimEndTime),
                clipTimelineStart: rounded(project.clipTimelineStart),
                timelineDuration: rounded(project.timelineDuration)
            ),
            currentZoomSegments: project.animations.map(AIBundle.ZoomSegmentSnapshot.init(segment:)),
            frames: frames
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(bundle)
        try data.write(to: destination.appendingPathComponent(bundleFileName), options: .atomic)
        try prompt(for: bundle).write(
            to: destination.appendingPathComponent(promptFileName),
            atomically: true,
            encoding: .utf8
        )
    }

    static func importPlan(from url: URL, into project: Project) throws -> String {
        guard project.videoURL != nil else {
            throw AIDirectorError.noVideo
        }

        let data = try Data(contentsOf: url)
        let plan: AIEditPlan
        do {
            plan = try JSONDecoder().decode(AIEditPlan.self, from: data)
        } catch {
            throw AIDirectorError.invalidJSON
        }

        guard plan.schemaVersion == schemaVersion else {
            throw AIDirectorError.unsupportedSchema(plan.schemaVersion)
        }
        guard plan.targetUseCase == targetUseCase else {
            throw AIDirectorError.unsupportedUseCase(plan.targetUseCase)
        }

        let duration = project.durationSeconds
        guard duration > 0 else {
            throw AIDirectorError.noVideo
        }

        let trimStart = plan.trimStart
        let trimEnd = plan.trimEnd
        guard trimStart >= 0, trimEnd <= duration, trimEnd > trimStart else {
            throw AIDirectorError.invalidTrim
        }
        guard trimEnd - trimStart >= Project.minTrimDuration else {
            throw AIDirectorError.trimTooShort
        }

        let sortedZooms = plan.zoomSegments.sorted { $0.startTime < $1.startTime }
        var previousEnd = -Double.infinity
        var importedSegments: [ZoomSegment] = []

        for zoom in sortedZooms {
            guard zoom.startTime >= trimStart, zoom.startTime + zoom.duration <= trimEnd else {
                throw AIDirectorError.zoomOutOfRange
            }
            guard zoom.startTime >= previousEnd else {
                throw AIDirectorError.overlappingZooms
            }
            guard let focus = ZoomFocus(rawValue: zoom.focus) else {
                throw AIDirectorError.invalidFocus(zoom.focus)
            }
            guard let curve = AnimationCurve(rawValue: zoom.curve) else {
                throw AIDirectorError.invalidCurve(zoom.curve)
            }
            guard ZoomSegment.scaleRange.contains(CGFloat(zoom.scale)),
                  ZoomSegment.durationRange.contains(zoom.duration),
                  ZoomSegment.transitionRange.contains(zoom.transitionIn),
                  ZoomSegment.transitionRange.contains(zoom.transitionOut),
                  zoom.transitionIn <= zoom.duration / 2,
                  zoom.transitionOut <= zoom.duration / 2 else {
                throw AIDirectorError.invalidZoomValues
            }

            var segment = ZoomSegment(
                startTime: zoom.startTime,
                duration: zoom.duration,
                scale: CGFloat(zoom.scale),
                focus: focus,
                transitionIn: zoom.transitionIn,
                transitionOut: zoom.transitionOut,
                curve: curve
            )
            segment.normalize()
            importedSegments.append(segment)
            previousEnd = segment.endTime
        }

        guard trimStart != project.trimStartTime || trimEnd != project.trimEndTime || !importedSegments.isEmpty else {
            throw AIDirectorError.emptyPlan
        }

        project.trimStartTime = trimStart
        project.trimEndTime = trimEnd
        project.clipTimelineStart = 0
        project.animations = importedSegments
        project.selectedAnimationID = importedSegments.first?.id
        project.seek(to: 0)

        let zoomCount = importedSegments.count
        let zoomLabel = zoomCount == 1 ? "1 zoom" : "\(zoomCount) zooms"
        return "Imported AI Director plan: \(format(trimEnd - trimStart))s trim, \(zoomLabel)."
    }

    static func snapshot(of project: Project) -> AIDirectorAppliedEdit {
        AIDirectorAppliedEdit(
            trimStart: project.trimStartTime,
            trimEnd: project.trimEndTime,
            clipTimelineStart: project.clipTimelineStart,
            animations: project.animations,
            selectedAnimationID: project.selectedAnimationID
        )
    }

    static func restore(_ edit: AIDirectorAppliedEdit, to project: Project) {
        project.trimStartTime = edit.trimStart
        project.trimEndTime = edit.trimEnd
        project.clipTimelineStart = edit.clipTimelineStart
        project.animations = edit.animations
        project.selectedAnimationID = edit.selectedAnimationID
        project.seek(to: project.clipTimelineStart)
    }

    nonisolated static func validate(plan: AIDirectorPlan, duration: Double) throws {
        guard plan.schemaVersion == schemaVersion else {
            throw AIDirectorError.unsupportedSchema(plan.schemaVersion)
        }
        guard plan.targetUseCase == targetUseCase else {
            throw AIDirectorError.unsupportedUseCase(plan.targetUseCase)
        }
        guard plan.trimStart >= 0, plan.trimEnd <= duration, plan.trimEnd > plan.trimStart else {
            throw AIDirectorError.invalidTrim
        }
        guard plan.trimEnd - plan.trimStart >= minTrimDuration else {
            throw AIDirectorError.trimTooShort
        }

        let sortedZooms = plan.zoomSegments.sorted { $0.startTime < $1.startTime }
        var previousEnd = -Double.infinity
        for zoom in sortedZooms {
            guard zoom.startTime >= plan.trimStart, zoom.startTime + zoom.duration <= plan.trimEnd else {
                throw AIDirectorError.zoomOutOfRange
            }
            guard zoom.startTime >= previousEnd else {
                throw AIDirectorError.overlappingZooms
            }
            guard ZoomFocus(rawValue: zoom.focus) != nil else {
                throw AIDirectorError.invalidFocus(zoom.focus)
            }
            guard AnimationCurve(rawValue: zoom.curve) != nil else {
                throw AIDirectorError.invalidCurve(zoom.curve)
            }
            guard allowedZoomScaleRange.contains(zoom.scale),
                  allowedZoomDurationRange.contains(zoom.duration),
                  allowedZoomTransitionRange.contains(zoom.transitionIn),
                  allowedZoomTransitionRange.contains(zoom.transitionOut),
                  zoom.transitionIn <= zoom.duration / 2,
                  zoom.transitionOut <= zoom.duration / 2 else {
                throw AIDirectorError.invalidZoomValues
            }
            previousEnd = zoom.startTime + zoom.duration
        }
    }

    nonisolated private static func soften(_ plan: AIDirectorPlan, for settings: AIDirectorSettings) -> AIDirectorPlan {
        let profile = motionProfile(for: settings)
        var softened = plan
        var changed = false

        var zooms = softened.zoomSegments.sorted { $0.startTime < $1.startTime }
        if zooms.count > profile.maxZoomCount {
            zooms = Array(zooms.prefix(profile.maxZoomCount))
            changed = true
        }

        softened.zoomSegments = zooms.map { zoom in
            var z = zoom
            let original = z

            z.scale = clamp(z.scale, to: profile.scaleRange)

            let availableDuration = max(0, softened.trimEnd - z.startTime)
            let maxDuration = min(profile.durationRange.upperBound, availableDuration)
            if maxDuration >= profile.durationRange.lowerBound {
                z.duration = clamp(z.duration, to: profile.durationRange.lowerBound...maxDuration)
            } else {
                z.duration = min(z.duration, availableDuration)
            }

            let maxTransition = min(profile.transitionRange.upperBound, z.duration / 2)
            if maxTransition >= profile.transitionRange.lowerBound {
                z.transitionIn = clamp(z.transitionIn, to: profile.transitionRange.lowerBound...maxTransition)
                z.transitionOut = clamp(z.transitionOut, to: profile.transitionRange.lowerBound...maxTransition)
            } else {
                z.transitionIn = min(z.transitionIn, maxTransition)
                z.transitionOut = min(z.transitionOut, maxTransition)
            }

            if let curve = AnimationCurve(rawValue: z.curve) {
                if !profile.allowedCurves.contains(curve) {
                    z.curve = profile.preferredCurve.rawValue
                }
            } else {
                z.curve = profile.preferredCurve.rawValue
            }

            if profile.isBarelyThere {
                z.focus = ZoomFocus.center.rawValue
            } else if ZoomFocus(rawValue: z.focus) == nil {
                z.focus = ZoomFocus.center.rawValue
            }

            if abs(original.scale - z.scale) > 0.001 ||
                abs(original.duration - z.duration) > 0.001 ||
                abs(original.transitionIn - z.transitionIn) > 0.001 ||
                abs(original.transitionOut - z.transitionOut) > 0.001 ||
                original.curve != z.curve ||
                original.focus != z.focus {
                changed = true
            }

            return z
        }

        if changed {
            let warning = "Softened zooms to match \(profile.displayName) intensity."
            if !softened.warnings.contains(warning) {
                softened.warnings.append(warning)
            }
        }

        return softened
    }

    nonisolated private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        max(range.lowerBound, min(value, range.upperBound))
    }

    nonisolated private static func recommendedTrimStart(for duration: Double) -> Double {
        switch duration {
        case ..<4:
            return 0
        case ..<10:
            return min(0.35, max(0, duration - minTrimDuration))
        default:
            return min(0.75, max(0, duration - minTrimDuration))
        }
    }

    nonisolated private static func recommendedTrimEnd(for duration: Double, trimStart: Double) -> Double {
        let targetLength: Double
        switch duration {
        case ..<8:
            targetLength = duration - trimStart
        case ..<20:
            targetLength = min(14, duration - trimStart)
        default:
            targetLength = 18
        }
        return min(duration, trimStart + max(minTrimDuration, targetLength))
    }

    nonisolated private static func recommendedZoomSegments(
        trimStart: Double,
        trimEnd: Double,
        settings: AIDirectorSettings
    ) -> [AIDirectorPlanZoomSegment] {
        let editDuration = trimEnd - trimStart
        guard editDuration >= 1.2 else { return [] }
        let profile = motionProfile(for: settings)

        let fractions: [Double] = {
            if profile.maxZoomCount <= 2 {
                return editDuration < 7 ? [0.52] : [0.24, 0.74]
            }
            if editDuration < 10 {
                return [0.18, 0.56]
            }
            return [0.14, 0.42, 0.72].prefix(profile.maxZoomCount).map { $0 }
        }()

        var segments: [AIDirectorPlanZoomSegment] = []
        var previousEnd = trimStart
        for (index, fraction) in fractions.enumerated() {
            let desiredDuration = min(profile.durationRange.upperBound, max(profile.durationRange.lowerBound, editDuration * 0.22))
            let duration = min(desiredDuration, max(0.7, editDuration * 0.35))
            let desiredStart = trimStart + editDuration * fraction
            let latestStart = max(trimStart, trimEnd - duration)
            let spacing = profile.isBarelyThere ? 0.45 : 0.2
            let start = max(previousEnd + spacing, min(desiredStart, latestStart))
            guard start + duration <= trimEnd else { continue }

            let scaleProgress = fractions.count <= 1 ? 0.5 : Double(index) / Double(max(fractions.count - 1, 1))
            let scale = profile.scaleRange.lowerBound + (profile.scaleRange.upperBound - profile.scaleRange.lowerBound) * scaleProgress
            let transition = min(profile.transitionRange.upperBound, max(profile.transitionRange.lowerBound, duration * 0.34))
            let focus = profile.focusSequence[index % profile.focusSequence.count]

            let segment = AIDirectorPlanZoomSegment(
                startTime: rounded(start),
                duration: rounded(duration),
                scale: rounded(scale),
                focus: focus.rawValue,
                transitionIn: rounded(min(transition, duration / 2)),
                transitionOut: rounded(min(transition, duration / 2)),
                curve: profile.preferredCurve.rawValue,
                reason: profile.isBarelyThere ? "Soft attention cue." : "Focus attention on a key product moment."
            )
            segments.append(segment)
            previousEnd = start + duration
        }

        return segments
    }

    nonisolated private static func motionProfile(for settings: AIDirectorSettings) -> ZoomMotionProfile {
        if settings.pacing == .calm {
            return barelyThereMotionProfile
        }

        switch settings.zoomIntensity {
        case .subtle:
            return barelyThereMotionProfile
        case .standard:
            return standardMotionProfile
        case .dramatic:
            return dramaticMotionProfile
        }
    }

    nonisolated private static var barelyThereMotionProfile: ZoomMotionProfile {
        ZoomMotionProfile(
            kind: .barelyThere,
            displayName: "Barely There",
            isBarelyThere: true,
            scaleRange: 1.04...1.08,
            durationRange: 3.0...4.5,
            transitionRange: 0.9...1.4,
            allowedCurves: [.smooth, .gentle],
            preferredCurve: .gentle,
            focusSequence: [.center, .center],
            maxZoomCount: 2
        )
    }

    nonisolated private static var standardMotionProfile: ZoomMotionProfile {
        ZoomMotionProfile(
            kind: .standard,
            displayName: "Standard",
            isBarelyThere: false,
            scaleRange: 1.08...1.16,
            durationRange: 2.2...3.4,
            transitionRange: 0.65...1.1,
            allowedCurves: [.smooth, .gentle],
            preferredCurve: .smooth,
            focusSequence: [.center, .top, .center],
            maxZoomCount: 3
        )
    }

    nonisolated private static var dramaticMotionProfile: ZoomMotionProfile {
        ZoomMotionProfile(
            kind: .dramatic,
            displayName: "Dramatic",
            isBarelyThere: false,
            scaleRange: 1.18...1.45,
            durationRange: 1.2...2.8,
            transitionRange: 0.25...0.7,
            allowedCurves: [.smooth, .gentle, .snappy, .spring, .bouncy],
            preferredCurve: .snappy,
            focusSequence: [.center, .top, .bottom, .center],
            maxZoomCount: 4
        )
    }

    private static func fallbackPlan(
        for project: Project,
        settings: AIDirectorSettings,
        previousPlan: AIDirectorPlan? = nil,
        warning: String? = nil
    ) -> AIDirectorPlan {
        let context = GenerationContext(
            videoURL: project.videoURL ?? URL(fileURLWithPath: "/"),
            durationSeconds: project.durationSeconds,
            videoNaturalSize: project.videoNaturalSize,
            trimStartTime: project.trimStartTime,
            trimEndTime: project.trimEndTime,
            settings: settings,
            previousPlan: previousPlan
        )
        return fallbackPlan(for: context, warning: warning)
    }

    nonisolated private static func fallbackPlan(
        for context: GenerationContext,
        warning: String? = nil
    ) -> AIDirectorPlan {
        let duration = context.durationSeconds
        let trimStart = recommendedTrimStart(for: duration)
        let targetEnd = min(duration, trimStart + max(minTrimDuration, context.settings.targetLength))
        let trimEnd = min(recommendedTrimEnd(for: duration, trimStart: trimStart), targetEnd)
        let segments = recommendedZoomSegments(trimStart: trimStart, trimEnd: trimEnd, settings: context.settings)
        let warningText = warning.map { ["Used local fallback because Codex could not generate a plan: \($0)"] } ?? []
        let isRetry = context.previousPlan != nil
        return AIDirectorPlan(
            schemaVersion: schemaVersion,
            targetUseCase: targetUseCase,
            rationale: isRetry
                ? "Regenerated a concise fallback edit with calmer zoom motion from the updated AI Director controls."
                : "Created a concise social-demo edit with an early hook and soft attention cues.",
            trimStart: rounded(trimStart),
            trimEnd: rounded(trimEnd),
            zoomSegments: segments,
            warnings: warningText
        )
    }

    nonisolated private static func makeRunDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let runs = base
            .appendingPathComponent("Maya AI Studio", isDirectory: true)
            .appendingPathComponent("AI Director", isDirectory: true)
            .appendingPathComponent("Runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
        let dir = runs.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static func writeJSONObject(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    nonisolated private static func jsonString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    nonisolated private static func metadataJSONObject(_ metadata: AIDirectorRunMetadata) -> [String: Any] {
        var object: [String: Any] = [
            "schemaVersion": metadata.schemaVersion,
            "targetUseCase": metadata.targetUseCase,
            "allowedEditScope": metadata.allowedEditScope,
            "sourceDuration": metadata.sourceDuration,
            "videoWidth": metadata.videoWidth,
            "videoHeight": metadata.videoHeight,
            "currentTrimStart": metadata.currentTrimStart,
            "currentTrimEnd": metadata.currentTrimEnd,
            "settings": settingsJSONObject(metadata.settings),
            "frames": metadata.frames.map(frameJSONObject)
        ]
        if let previousPlan = metadata.previousPlan {
            object["previousPlan"] = planJSONObject(previousPlan)
        }
        return object
    }

    nonisolated private static func settingsJSONObject(_ settings: AIDirectorSettings) -> [String: Any] {
        [
            "targetLength": rounded(settings.targetLength),
            "pacing": settings.pacing.rawValue,
            "zoomIntensity": settings.zoomIntensity.rawValue,
            "hookStrength": rounded(settings.hookStrength),
            "endingEmphasis": rounded(settings.endingEmphasis),
            "revisionNotes": settings.revisionNotes
        ]
    }

    nonisolated private static func frameJSONObject(_ frame: AIBundle.Frame) -> [String: Any] {
        [
            "fileName": frame.fileName,
            "timeSeconds": frame.timeSeconds
        ]
    }

    nonisolated private static func planJSONObject(_ plan: AIDirectorPlan) -> [String: Any] {
        [
            "schemaVersion": plan.schemaVersion,
            "targetUseCase": plan.targetUseCase,
            "rationale": plan.rationale,
            "trimStart": plan.trimStart,
            "trimEnd": plan.trimEnd,
            "zoomSegments": plan.zoomSegments.map(zoomJSONObject),
            "warnings": plan.warnings
        ]
    }

    nonisolated private static func zoomJSONObject(_ zoom: AIDirectorPlanZoomSegment) -> [String: Any] {
        var object: [String: Any] = [
            "startTime": zoom.startTime,
            "duration": zoom.duration,
            "scale": zoom.scale,
            "focus": zoom.focus,
            "transitionIn": zoom.transitionIn,
            "transitionOut": zoom.transitionOut,
            "curve": zoom.curve
        ]
        if let reason = zoom.reason {
            object["reason"] = reason
        }
        return object
    }

    nonisolated private static func parsePlan(from data: Data) throws -> AIDirectorPlan {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIDirectorError.invalidJSON
        }

        return AIDirectorPlan(
            schemaVersion: try intValue("schemaVersion", in: object),
            targetUseCase: try stringValue("targetUseCase", in: object),
            rationale: try stringValue("rationale", in: object),
            trimStart: try doubleValue("trimStart", in: object),
            trimEnd: try doubleValue("trimEnd", in: object),
            zoomSegments: try zoomSegmentsValue("zoomSegments", in: object),
            warnings: try stringArrayValue("warnings", in: object)
        )
    }

    nonisolated private static func zoomSegmentsValue(_ key: String, in object: [String: Any]) throws -> [AIDirectorPlanZoomSegment] {
        guard let array = object[key] as? [[String: Any]] else {
            throw AIDirectorError.invalidJSON
        }
        return try array.map { zoom in
            AIDirectorPlanZoomSegment(
                startTime: try doubleValue("startTime", in: zoom),
                duration: try doubleValue("duration", in: zoom),
                scale: try doubleValue("scale", in: zoom),
                focus: try stringValue("focus", in: zoom),
                transitionIn: try doubleValue("transitionIn", in: zoom),
                transitionOut: try doubleValue("transitionOut", in: zoom),
                curve: try stringValue("curve", in: zoom),
                reason: zoom["reason"] as? String
            )
        }
    }

    nonisolated private static func stringArrayValue(_ key: String, in object: [String: Any]) throws -> [String] {
        guard let array = object[key] as? [String] else {
            throw AIDirectorError.invalidJSON
        }
        return array
    }

    nonisolated private static func stringValue(_ key: String, in object: [String: Any]) throws -> String {
        guard let value = object[key] as? String else {
            throw AIDirectorError.invalidJSON
        }
        return value
    }

    nonisolated private static func intValue(_ key: String, in object: [String: Any]) throws -> Int {
        switch object[key] {
        case let value as Int:
            return value
        case let value as Double where value.rounded() == value:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        default:
            throw AIDirectorError.invalidJSON
        }
    }

    nonisolated private static func doubleValue(_ key: String, in object: [String: Any]) throws -> Double {
        switch object[key] {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        default:
            throw AIDirectorError.invalidJSON
        }
    }

    nonisolated private static func runHelper(in runDirectory: URL) async throws {
        guard let helperURL = helperURL() else {
            throw AIDirectorError.helperUnavailable
        }
        guard let codexPath = codexPath() else {
            throw AIDirectorError.codexNotFound
        }

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
                throw AIDirectorError.codexLoginRequired
            }
            throw AIDirectorError.helperFailed(stderr.isEmpty ? stdout : stderr)
        }
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

    nonisolated private static func readGeneratedPlan(from url: URL) throws -> AIDirectorPlan {
        let data = try Data(contentsOf: url)
        do {
            return try parsePlan(from: data)
        } catch {
            guard let text = String(data: data, encoding: .utf8),
                  let jsonRange = text.range(of: #"\{[\s\S]*\}"#, options: .regularExpression) else {
                throw AIDirectorError.invalidJSON
            }
            let json = String(text[jsonRange])
            guard let jsonData = json.data(using: .utf8) else {
                throw AIDirectorError.invalidJSON
            }
            return try parsePlan(from: jsonData)
        }
    }

    nonisolated private static func prompt(for metadata: AIDirectorRunMetadata) throws -> String {
        let metadataJSON = try jsonString(metadataJSONObject(metadata))
        return """
        You are Maya AI Studio AI Director. Generate a single strict JSON edit plan for a polished short social product demo.

        Use behavioral science:
        - Strong hook in the first 1-2 seconds.
        - Remove dead setup time.
        - Use zooms as soft attention cues, not visual effects.
        - Keep cognitive load low.
        - End on the clearest visible payoff.

        Motion rules:
        \(motionRules(for: metadata.settings))

        Metadata:
        \(metadataJSON)

        Return only JSON matching the provided schema. Do not include Markdown.
        """
    }

    nonisolated private static func motionRules(for settings: AIDirectorSettings) -> String {
        let profile = motionProfile(for: settings)
        switch profile.kind {
        case .barelyThere:
            return """
            - Zoom intensity is Barely There: use only 1.04x-1.08x scale.
            - Use 3.0-4.5 second zoom durations with 0.9-1.4 second transitions.
            - Use only "smooth" or "gentle" curves. Never use "spring", "bouncy", or "snappy".
            - Prefer center focus. Avoid rapid top/bottom focus moves.
            - Use fewer zooms; keep them as calm attention nudges.
            """
        case .standard:
            return """
            - Zoom intensity is Standard: use only 1.08x-1.16x scale.
            - Use 2.2-3.4 second zoom durations with 0.65-1.1 second transitions.
            - Use only "smooth" or "gentle" curves.
            - Use limited focus movement; avoid punchy zooms.
            """
        case .dramatic:
            return """
            - Zoom intensity is Dramatic: stronger zooms are allowed, but keep them purposeful.
            - Use rapid or spring-like motion only for clearly high-salience moments.
            - Avoid stacking too many zooms in a short edit.
            """
        }
    }

    nonisolated private static var outputSchema: String {
        """
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["schemaVersion", "targetUseCase", "rationale", "trimStart", "trimEnd", "zoomSegments", "warnings"],
          "properties": {
            "schemaVersion": { "type": "integer", "const": 1 },
            "targetUseCase": { "type": "string", "const": "socialDemo" },
            "rationale": { "type": "string" },
            "trimStart": { "type": "number" },
            "trimEnd": { "type": "number" },
            "zoomSegments": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["startTime", "duration", "scale", "focus", "transitionIn", "transitionOut", "curve", "reason"],
                "properties": {
                  "startTime": { "type": "number" },
                  "duration": { "type": "number" },
                  "scale": { "type": "number" },
                  "focus": { "type": "string", "enum": ["top", "center", "bottom"] },
                  "transitionIn": { "type": "number" },
                  "transitionOut": { "type": "number" },
                  "curve": { "type": "string", "enum": ["spring", "bouncy", "smooth", "snappy", "gentle", "linear"] },
                  "reason": { "type": "string" }
                }
              }
            },
            "warnings": { "type": "array", "items": { "type": "string" } }
          }
        }
        """
    }

    nonisolated private static func writeFrames(from videoURL: URL, duration: Double, to directory: URL) async throws -> [AIBundle.Frame] {
        guard duration > 0 else { return [] }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let frameCount = min(maxFrameCount, max(1, Int(ceil(duration / 1.5))))
        var frames: [AIBundle.Frame] = []

        for index in 0..<frameCount {
            let fraction = Double(index) / Double(max(frameCount - 1, 1))
            let sampleEnd = max(0, duration - 0.05)
            let seconds = min(sampleEnd, max(0, fraction * sampleEnd))
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            let cgImage = try await generateFrame(using: generator, at: time)
            let fileName = String(format: "frame-%03d.jpg", index)
            let url = directory.appendingPathComponent(fileName)
            try writeJPEG(cgImage, to: url)
            frames.append(AIBundle.Frame(fileName: "frames/\(fileName)", timeSeconds: rounded(seconds)))
        }

        return frames
    }

    nonisolated private static func generateFrame(using generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, error in
                if let cgImage {
                    continuation.resume(returning: cgImage)
                } else {
                    continuation.resume(throwing: error ?? AIDirectorError.frameEncodingFailed)
                }
            }
        }
    }

    nonisolated private static func writeJPEG(_ cgImage: CGImage, to url: URL) throws {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            throw AIDirectorError.frameEncodingFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private static func prompt(for bundle: AIBundle) -> String {
        let frameList = bundle.frames
            .map { "- \($0.fileName) at \(format($0.timeSeconds))s" }
            .joined(separator: "\n")

        return """
        # Maya AI Studio AI Director

        You are creating a behavioral-science-informed edit plan for a short social product demo.

        Read `\(bundleFileName)` and inspect these sampled frames:
        \(frameList)

        Optimize for:
        - Hook within the first 1-2 seconds.
        - Remove idle setup and dead time.
        - Zoom only on high-salience moments: clicks, results, transformations, success states, pricing, or key copy.
        - Keep cognitive load low: fewer, clearer zooms are better than constant movement.
        - Preserve a problem -> action -> result arc.
        - Make the ending land on the strongest visible outcome.

        Write strict JSON only to `\(editPlanFileName)`. Do not include Markdown, comments, or prose.

        Required schema:

        {
          "schemaVersion": 1,
          "targetUseCase": "socialDemo",
          "rationale": "One short sentence explaining the edit.",
          "trimStart": 0.0,
          "trimEnd": 12.0,
          "zoomSegments": [
            {
              "startTime": 1.5,
              "duration": 1.2,
              "scale": 1.35,
              "focus": "center",
              "transitionIn": 0.25,
              "transitionOut": 0.35,
              "curve": "snappy",
              "reason": "Focus attention on the first visible payoff."
            }
          ]
        }

        Constraints:
        - `schemaVersion` must be 1.
        - `targetUseCase` must be "socialDemo".
        - `trimStart` and all zoom times are source-video seconds.
        - `trimEnd` must be greater than `trimStart` and at least 0.5 seconds later.
        - Zooms must sit fully inside the trim range and must not overlap.
        - `focus` must be one of: "top", "center", "bottom".
        - `curve` must be one of: "spring", "bouncy", "smooth", "snappy", "gentle", "linear".
        - `duration` must be 0.4 through 10.0.
        - `scale` must be 1.0 through 2.5.
        - `transitionIn` and `transitionOut` must be 0.05 through 2.0 and fit inside the zoom duration.
        """
    }

    nonisolated fileprivate static func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

struct AIBundle: Codable {
    struct Source: Codable {
        let displayName: String?
        let durationSeconds: Double
        let videoWidth: Double
        let videoHeight: Double
    }

    struct Timeline: Codable {
        let trimStart: Double
        let trimEnd: Double
        let clipTimelineStart: Double
        let timelineDuration: Double
    }

    struct ZoomSegmentSnapshot: Codable {
        let startTime: Double
        let duration: Double
        let scale: Double
        let focus: String
        let transitionIn: Double
        let transitionOut: Double
        let curve: String

        init(segment: ZoomSegment) {
            startTime = AIDirectorBridge.rounded(segment.startTime)
            duration = AIDirectorBridge.rounded(segment.duration)
            scale = AIDirectorBridge.rounded(Double(segment.scale))
            focus = segment.focus.rawValue
            transitionIn = AIDirectorBridge.rounded(segment.transitionIn)
            transitionOut = AIDirectorBridge.rounded(segment.transitionOut)
            curve = segment.curve.rawValue
        }
    }

    struct Frame: Codable, Sendable {
        let fileName: String
        let timeSeconds: Double
    }

    let schemaVersion: Int
    let appName: String
    let appVersion: String
    let targetUseCase: String
    let allowedEditScope: String
    let source: Source
    let timeline: Timeline
    let currentZoomSegments: [ZoomSegmentSnapshot]
    let frames: [Frame]
}

struct AIDirectorRunMetadata: Codable, Sendable {
    let schemaVersion: Int
    let targetUseCase: String
    let allowedEditScope: String
    let sourceDuration: Double
    let videoWidth: Double
    let videoHeight: Double
    let currentTrimStart: Double
    let currentTrimEnd: Double
    let settings: AIDirectorSettings
    let previousPlan: AIDirectorPlan?
    let frames: [AIBundle.Frame]
}

extension AIDirectorPlanZoomSegment {
    nonisolated init(segment: ZoomSegment) {
        startTime = AIDirectorBridge.rounded(segment.startTime)
        duration = AIDirectorBridge.rounded(segment.duration)
        scale = AIDirectorBridge.rounded(Double(segment.scale))
        focus = segment.focus.rawValue
        transitionIn = AIDirectorBridge.rounded(segment.transitionIn)
        transitionOut = AIDirectorBridge.rounded(segment.transitionOut)
        curve = segment.curve.rawValue
        reason = nil
    }
}

struct AIEditPlan: Decodable {
    let schemaVersion: Int
    let targetUseCase: String
    let rationale: String?
    let trimStart: Double
    let trimEnd: Double
    let zoomSegments: [AIPlanZoomSegment]
}

struct AIPlanZoomSegment: Decodable {
    let startTime: Double
    let duration: Double
    let scale: Double
    let focus: String
    let transitionIn: Double
    let transitionOut: Double
    let curve: String
    let reason: String?
}

enum AIDirectorError: LocalizedError {
    case noVideo
    case helperUnavailable
    case helperFailed(String)
    case codexNotFound
    case codexLoginRequired
    case invalidJSON
    case unsupportedSchema(Int)
    case unsupportedUseCase(String)
    case invalidTrim
    case trimTooShort
    case zoomOutOfRange
    case overlappingZooms
    case invalidFocus(String)
    case invalidCurve(String)
    case invalidZoomValues
    case emptyPlan
    case frameEncodingFailed

    var errorDescription: String? {
        switch self {
        case .noVideo:
            return "Load a recording before using AI Director."
        case .helperUnavailable:
            return "AI Director helper unavailable."
        case .helperFailed(let detail):
            return "AI Director helper failed: \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .codexNotFound:
            return "Codex CLI was not found. Install Codex CLI and sign in, or use the local fallback."
        case .codexLoginRequired:
            return "Codex login required. Run `codex login` in Terminal, then retry."
        case .invalidJSON:
            return "The edit plan is not valid Maya AI Director JSON."
        case .unsupportedSchema(let version):
            return "Unsupported AI Director schema version \(version)."
        case .unsupportedUseCase(let useCase):
            return "Unsupported target use case: \(useCase)."
        case .invalidTrim:
            return "The edit plan trim range is outside this recording."
        case .trimTooShort:
            return "The edit plan trim is shorter than 0.5 seconds."
        case .zoomOutOfRange:
            return "A zoom in the edit plan is outside the trim range."
        case .overlappingZooms:
            return "The edit plan has overlapping zooms."
        case .invalidFocus(let focus):
            return "Unsupported zoom focus: \(focus)."
        case .invalidCurve(let curve):
            return "Unsupported zoom curve: \(curve)."
        case .invalidZoomValues:
            return "A zoom has scale, duration, or transition values Maya cannot apply."
        case .emptyPlan:
            return "The edit plan does not contain a valid change."
        case .frameEncodingFailed:
            return "Could not encode one of the AI Director frame samples."
        }
    }
}
