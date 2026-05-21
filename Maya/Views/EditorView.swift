import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @AppStorage("hasAcceptedAIDirectorCodexDisclosure") private var hasAcceptedAIDirectorCodexDisclosure = false
    @State private var project = Project()
    @State private var blurPoster: NSImage?
    @State private var exporter = ExportService()
    @State private var aiDirectorMessage: AIDirectorMessage?
    @State private var isRunningAIDirector = false
    @State private var aiDirectorRun = AIDirectorRun()
    @State private var isAIDirectorPanelVisible = false
    @State private var isShowingAIDirectorCodexDisclosure = false
    @State private var pendingAIDirectorRetry = false

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(
                project: project,
                onExport: runExport,
                onOpenAIDirector: openAIDirectorPanel,
                onCreateAIVideo: createAIVideo,
                onExportAIBundle: exportAIBundle,
                onImportAIPlan: importAIPlan,
                aiDirectorMessage: aiDirectorMessage,
                isRunningAIDirector: isRunningAIDirector,
                aiDirectorStatus: aiDirectorRun.status,
                isAIDirectorPanelVisible: isAIDirectorPanelVisible
            )
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    CanvasView(project: project, blurPoster: blurPoster, onOpenRecording: openVideoPicker)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .dropDestination(for: URL.self) { urls, _ in
                            guard let url = urls.first else { return false }
                            importVideo(from: url)
                            return true
                        }

                    if project.videoURL != nil {
                        TimelineView(project: project) { segment in
                            project.selectedAnimationID = segment.id
                        }
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .background(keyboardShortcuts)

                if isAIDirectorPanelVisible {
                    Divider()
                    AIDirectorPanel(
                        run: $aiDirectorRun,
                        onCreate: { requestAIDirectorRun(shouldRetry: false) },
                        onRetry: { requestAIDirectorRun(shouldRetry: true) },
                        onApply: applyAIPlan,
                        onRevert: revertAIDirector,
                        onClose: { isAIDirectorPanelVisible = false }
                    )
                    .frame(width: 360)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if let selectedID = project.selectedAnimationID,
                   project.animations.contains(where: { $0.id == selectedID }) {
                    Divider()
                    AnimationEditorPanel(project: project, segmentID: selectedID) {
                        project.selectedAnimationID = nil
                    }
                    .frame(width: 340)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: project.selectedAnimationID)
        }
        .navigationTitle(AppChrome.title)
        .navigationSubtitle(AppChrome.versionLabel)
        .sheet(isPresented: $isShowingAIDirectorCodexDisclosure) {
            AIDirectorCodexDisclosureSheet(
                onContinue: {
                    hasAcceptedAIDirectorCodexDisclosure = true
                    isShowingAIDirectorCodexDisclosure = false
                    runAIDirector(shouldRetry: pendingAIDirectorRetry)
                },
                onCancel: {
                    isShowingAIDirectorCodexDisclosure = false
                    pendingAIDirectorRetry = false
                }
            )
        }
        .onChange(of: project.videoURL) { _, _ in updateBlurPoster() }
        .onChange(of: project.background) { _, _ in updateBlurPoster() }
    }

    /// Hidden buttons attach app-wide shortcuts without needing focus management.
    /// macOS automatically routes the key to the first responder first — so text
    /// fields keep typing spaces, deletes, etc., and these only fire when nothing
    /// else claims the event.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { project.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { deleteSelectedSegment() }
                .keyboardShortcut(.delete, modifiers: [])
            Button("") { duplicateSelectedSegment() }
                .keyboardShortcut("d", modifiers: .command)
            Button("") { scrub(-0.25) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { scrub(+0.25) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { scrub(-1.0) }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
            Button("") { scrub(+1.0) }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
            Button("") { project.toggleMute() }
                .keyboardShortcut("m", modifiers: [])

            // Trim shortcuts (Final Cut / iMovie convention).
            Button("") { markTrimIn() }
                .keyboardShortcut("i", modifiers: [])
            Button("") { markTrimOut() }
                .keyboardShortcut("o", modifiers: [])
            Button("") { resetTrim() }
                .keyboardShortcut(.delete, modifiers: .option)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func markTrimIn() {
        guard project.videoURL != nil else { return }
        // currentSeconds is in timeline coords; convert to source for the trim handle, and
        // anchor the clip's right edge so the trim doesn't push the rest of the clip around.
        let newSource = project.timelineToSource(project.currentSeconds)
        let delta = newSource - project.trimStartTime
        project.setTrimStart(newSource)
        project.clipTimelineStart += delta
    }

    private func markTrimOut() {
        guard project.videoURL != nil else { return }
        let newSource = project.timelineToSource(project.currentSeconds)
        project.setTrimEnd(newSource)
    }

    private func resetTrim() {
        guard project.videoURL != nil else { return }
        project.trimStartTime = 0
        project.trimEndTime = project.durationSeconds
        project.clipTimelineStart = 0
    }

    private func deleteSelectedSegment() {
        guard let id = project.selectedAnimationID else { return }
        project.removeZoomSegment(id: id)
    }

    private func duplicateSelectedSegment() {
        guard let id = project.selectedAnimationID else { return }
        _ = project.duplicateZoomSegment(id: id)
    }

    private func scrub(_ delta: Double) {
        guard project.videoURL != nil else { return }
        project.seek(to: project.currentSeconds + delta)
    }

    private func updateBlurPoster() {
        guard case .videoBlur = project.background,
              let url = project.videoURL else {
            blurPoster = nil
            return
        }
        Task {
            let image = await BlurPosterCache.shared.poster(for: url)
            await MainActor.run { self.blurPoster = image }
        }
    }

    private func importVideo(from url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        do {
            let adopted = try Project.adoptIntoSandbox(url)
            if didStart { url.stopAccessingSecurityScopedResource() }
            Task {
                project.displayName = adopted.displayName
                await project.loadVideo(url: adopted.sandboxURL)
            }
        } catch {
            if didStart { url.stopAccessingSecurityScopedResource() }
            project.lastExportError = "Could not import video: \(error.localizedDescription)"
        }
    }

    private func openVideoPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            importVideo(from: url)
        }
    }

    private func runExport() {
        let isTransparent = project.background.isTransparent
        let suggestedName = isTransparent ? "Maya-AI-Studio-export.mov" : "Maya-AI-Studio-export.mp4"
        let types: [UTType] = isTransparent ? [.quickTimeMovie] : [.mpeg4Movie]

        runSavePanel(suggestedName: suggestedName, allowedTypes: types) { url in
            Task {
                project.isExporting = true
                project.lastExportError = nil
                project.exportProgress = 0
                do {
                    if isTransparent {
                        try await exporter.exportTransparent(
                            project: project,
                            to: url,
                            progress: { p in Task { @MainActor in project.exportProgress = p } }
                        )
                    } else {
                        try await exporter.exportWithBackground(
                            project: project,
                            to: url,
                            progress: { p in Task { @MainActor in project.exportProgress = p } }
                        )
                    }
                } catch {
                    await MainActor.run { project.lastExportError = error.localizedDescription }
                }
                project.isExporting = false
            }
        }
    }

    private func runSavePanel(suggestedName: String, allowedTypes: [UTType], onPick: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = allowedTypes
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }

    private func exportAIBundle() {
        guard project.videoURL != nil else {
            aiDirectorMessage = .failure("Load a recording before exporting an AI bundle.")
            return
        }

        let panel = NSOpenPanel()
        panel.message = "Choose a folder for the Maya AI Director bundle."
        panel.prompt = "Export Bundle"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await MainActor.run {
                    isRunningAIDirector = true
                    aiDirectorMessage = nil
                }

                do {
                    try await AIDirectorBridge.exportBundle(project: project, to: url)
                    await MainActor.run {
                        aiDirectorMessage = .success("Exported AI bundle to \(url.lastPathComponent).")
                    }
                } catch {
                    await MainActor.run {
                        aiDirectorMessage = .failure(error.localizedDescription)
                    }
                }

                await MainActor.run {
                    isRunningAIDirector = false
                }
            }
        }
    }

    private func createAIVideo() {
        guard project.videoURL != nil else {
            aiDirectorMessage = .failure("Load a recording before using AI Director.")
            return
        }

        isAIDirectorPanelVisible = true
        requestAIDirectorRun(shouldRetry: aiDirectorRun.selectedPlan != nil)
    }

    private func openAIDirectorPanel() {
        isAIDirectorPanelVisible = true
    }

    private func requestAIDirectorRun(shouldRetry: Bool) {
        guard project.videoURL != nil else {
            aiDirectorMessage = .failure("Load a recording before using AI Director.")
            aiDirectorRun.status = .failed
            aiDirectorRun.error = "Load a recording before using AI Director."
            return
        }

        isAIDirectorPanelVisible = true
        pendingAIDirectorRetry = shouldRetry

        guard hasAcceptedAIDirectorCodexDisclosure else {
            isShowingAIDirectorCodexDisclosure = true
            return
        }

        runAIDirector(shouldRetry: shouldRetry)
    }

    private func runAIDirector(shouldRetry: Bool) {
        guard project.videoURL != nil else {
            aiDirectorMessage = .failure("Load a recording before using AI Director.")
            aiDirectorRun.status = .failed
            aiDirectorRun.error = "Load a recording before using AI Director."
            return
        }

        if aiDirectorRun.originalEdit == nil {
            aiDirectorRun.originalEdit = AIDirectorBridge.snapshot(of: project)
        }

        isAIDirectorPanelVisible = true
        isRunningAIDirector = true
        aiDirectorRun.status = .analyzing
        aiDirectorRun.error = nil
        aiDirectorMessage = nil

        let settings = aiDirectorRun.settings
        let previousPlan = shouldRetry ? aiDirectorRun.selectedPlan : nil

        Task {
            do {
                await MainActor.run { aiDirectorRun.status = .generating }
                let result = try await AIDirectorBridge.generatePlan(
                    for: project,
                    settings: settings,
                    previousPlan: previousPlan
                )
                await MainActor.run {
                    aiDirectorRun.versions.append(result.plan)
                    aiDirectorRun.selectedVersionID = result.plan.id
                    aiDirectorRun.runDirectory = result.runDirectory
                    applyAIPlan(result.plan)
                    let fallbackNote = result.usedFallback ? " Used local fallback because Codex was unavailable." : ""
                    aiDirectorMessage = .success("AI Director created a preview.\(fallbackNote)")
                    aiDirectorRun.status = .applied
                    isRunningAIDirector = false
                }
            } catch {
                await MainActor.run {
                    aiDirectorRun.status = .failed
                    aiDirectorRun.error = error.localizedDescription
                    aiDirectorMessage = .failure(error.localizedDescription)
                    isRunningAIDirector = false
                }
            }
        }
    }

    private func applyAIPlan(_ plan: AIDirectorPlan) {
        do {
            try AIDirectorBridge.apply(plan: plan, to: project, shouldPlay: true)
            aiDirectorRun.selectedVersionID = plan.id
            aiDirectorRun.status = .applied
            aiDirectorRun.error = nil
        } catch {
            aiDirectorRun.status = .failed
            aiDirectorRun.error = error.localizedDescription
            aiDirectorMessage = .failure(error.localizedDescription)
        }
    }

    private func revertAIDirector() {
        guard let originalEdit = aiDirectorRun.originalEdit else { return }
        AIDirectorBridge.restore(originalEdit, to: project)
        aiDirectorRun.status = .idle
        aiDirectorMessage = .success("Reverted AI Director edit.")
    }

    private func importAIPlan() {
        guard project.videoURL != nil else {
            aiDirectorMessage = .failure("Load a recording before importing an edit plan.")
            return
        }

        let panel = NSOpenPanel()
        panel.message = "Choose the Codex-generated maya-edit-plan.json file."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let message = try AIDirectorBridge.importPlan(from: url, into: project)
                aiDirectorMessage = .success(message)
            } catch {
                aiDirectorMessage = .failure(error.localizedDescription)
            }
        }
    }
}

struct AIDirectorMessage: Equatable {
    enum Kind {
        case success
        case failure
    }

    let kind: Kind
    let text: String

    static func success(_ text: String) -> AIDirectorMessage {
        AIDirectorMessage(kind: .success, text: text)
    }

    static func failure(_ text: String) -> AIDirectorMessage {
        AIDirectorMessage(kind: .failure, text: text)
    }
}

struct AIDirectorCodexDisclosureSheet: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Director uses your local Codex")
                        .font(.title3.weight(.semibold))
                    Text("Before Maya creates an AI edit, it uses the Codex CLI installed on this Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                disclosureRow(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Uses your Codex account",
                    detail: "Usage is tied to your local Codex login and subscription, not a Maya-hosted account."
                )
                disclosureRow(
                    icon: "photo.on.rectangle.angled",
                    title: "Sends sampled frames and metadata",
                    detail: "Maya passes selected frame images plus timing and project metadata to the local `codex` CLI."
                )
                disclosureRow(
                    icon: "video.slash",
                    title: "Does not send the full video file",
                    detail: "AI Director only applies trim and zoom edits. Canvas, device, background, and export settings stay under your control."
                )
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    onContinue()
                } label: {
                    Text("Continue with local Codex")
                        .frame(minWidth: 190)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func disclosureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
