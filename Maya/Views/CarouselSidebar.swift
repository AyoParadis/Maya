import AppKit
import SwiftUI

struct CarouselSidebar: View {
    @Bindable var workspace: CarouselWorkspace
    let onNewCarousel: () -> Void
    let onCloseCarousel: () -> Void
    let onImportImages: () -> Void
    let onOpenInspector: () -> Void
    let onExportVideo: () -> Void
    let onExportImages: () -> Void
    let onExportBundle: () -> Void
    let isInspectorVisible: Bool
    @State private var voicePreviewSound: NSSound?
    @State private var voicePreviewTask: Task<Void, Never>?
    @State private var voicePreviewToken: UUID?
    @State private var voiceStorageSummary: NarrationStorageSummary?
    @State private var isDeletingVoiceAssets = false
    @State private var isConfirmingVoiceAssetDeletion = false
    @State private var isProjectsExpanded = true
    @State private var isVoiceoverExpanded = true
    @State private var isBriefExpanded = true
    @State private var isCanvasExpanded = true
    @State private var isInspectorExpanded = true
    @State private var isExportExpanded = true

    var body: some View {
        StudioSidebarScaffold {
            StudioSidebarHeader(title: "Carousel")
            SidebarDisclosureSection(title: "Projects", isExpanded: $isProjectsExpanded) {
                carouselList
            }
            SidebarDisclosureSection(title: "AI Voiceover", isExpanded: $isVoiceoverExpanded) {
                narrationSection
            }
            SidebarDisclosureSection(title: "Brief", isExpanded: $isBriefExpanded) {
                importSection
            }
            SidebarDisclosureSection(title: "Canvas", isExpanded: $isCanvasExpanded) {
                formatSection
            }
            if !isInspectorVisible {
                SidebarDisclosureSection(title: "Inspector", isExpanded: $isInspectorExpanded) {
                    inspectorSection
                }
            }
            SidebarDisclosureSection(title: "Export", isExpanded: $isExportExpanded) {
                exportSection
            }
            if let message = workspace.lastMessage {
                CompactStatusMessage(text: message, icon: "info.circle", tint: .secondary)
            }
            if let error = workspace.lastError {
                CopyableMessageBox(text: error, isError: true)
            }
        }
        .task {
            await refreshVoiceEngineInstallationStatus()
            await refreshVoiceStorageSummary()
            if workspace.selectedProject.narrationEngineInstallationStatus == .installed {
                await NarrationService.warmPreviewsIfNeeded(for: workspace.selectedProject.narrationEngine)
                await refreshVoiceStorageSummary()
            }
        }
        .onChange(of: workspace.selectedProject.narrationEngine) { _, _ in
            Task {
                await refreshVoiceEngineInstallationStatus()
                await refreshVoiceStorageSummary()
            }
        }
        .onChange(of: workspace.selectedProjectID) { _, _ in
            Task {
                await refreshVoiceEngineInstallationStatus()
                await refreshVoiceStorageSummary()
            }
        }
        .confirmationDialog(
            "Delete \(workspace.selectedProject.narrationEngine.displayName) voice assets?",
            isPresented: $isConfirmingVoiceAssetDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete \(workspace.selectedProject.narrationEngine.displayName) assets", role: .destructive) {
                deleteSelectedVoiceEngineAssets()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected engine's installed files, downloaded voice models, and cached previews. Generated project voiceovers are kept.")
        }
    }

    private var inspectorSection: some View {
        Button(action: onOpenInspector) {
            Label("Open inspector", systemImage: "sidebar.trailing")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help("Show carousel slide inspector")
    }

    private var carouselList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(workspace.projects) { project in
                CarouselProjectChip(
                    title: project.title,
                    count: project.cards.count,
                    isSelected: workspace.selectedProjectID == project.id,
                    onNewCarousel: onNewCarousel,
                    onCloseCarousel: onCloseCarousel
                ) {
                    workspace.selectedProjectID = project.id
                }
            }
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Carousel name", text: $workspace.selectedProject.title)
                .textFieldStyle(.roundedBorder)
            TextField("Audience", text: $workspace.selectedProject.brief.audience)
                .textFieldStyle(.roundedBorder)
            TextField("Goal", text: $workspace.selectedProject.brief.goal)
                .textFieldStyle(.roundedBorder)
            TextField("Platform", text: $workspace.selectedProject.brief.platform)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $workspace.selectedProject.brief.sourceContent)
                .font(.callout)
                .frame(minHeight: 92)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25), lineWidth: 1))
            HStack {
                TextField("Brand", text: $workspace.selectedProject.brief.brandName)
                    .textFieldStyle(.roundedBorder)
                TextField("#6466FA", text: $workspace.selectedProject.brief.brandHex)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
            }
            Button(action: onImportImages) {
                Label("Import optional images", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            HStack {
                Text("Default duration")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(workspace.selectedProject.defaultCardDuration, specifier: "%.1f")s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $workspace.selectedProject.defaultCardDuration, in: 0.8...6.0, step: 0.1)
                .tint(.gray)
            Button {
                workspace.selectedProject.applyDefaultDurationToAllCards()
            } label: {
                Label("Set all slides to \(workspace.selectedProject.defaultCardDuration, specifier: "%.1f")s", systemImage: "timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(workspace.selectedProject.cards.isEmpty)
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let columns = [GridItem(.adaptive(minimum: 72), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach([CanvasAspectRatio.square, .vertical9x16, .vertical4x5, .landscape16x9]) { aspect in
                    AspectRatioChip(
                        aspect: aspect,
                        isSelected: workspace.selectedProject.canvasAspect == aspect,
                        minHeight: 66,
                        maxThumbnailDimension: 24
                    ) {
                        workspace.selectedProject.canvasAspect = aspect
                    }
                }
            }

            Text(workspace.selectedProject.canvasAspect.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Motion")
                .font(.caption.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(CarouselMotionPreset.allCases) { motion in
                    CarouselOptionChip(
                        label: motion.label,
                        symbol: motion.symbol,
                        isSelected: workspace.selectedProject.motionPreset == motion
                    ) {
                        workspace.selectedProject.motionPreset = motion
                    }
                }
            }

            Toggle("Show safe zones", isOn: $workspace.selectedProject.showSafeZones)
                .toggleStyle(.switch)
                .tint(.gray)
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if workspace.isExporting {
                VStack(alignment: .leading, spacing: 8) {
                    StudioActionCardButton(
                        title: activeExportTitle,
                        subtitle: activeExportSubtitle,
                        icon: "square.and.arrow.up",
                        isEnabled: false,
                        isWorking: true,
                        progress: workspace.exportProgress,
                        workingLabel: activeExportTitle,
                        accent: Color(hex: "#7C6DFF") ?? .accentColor,
                        accentDark: Color(hex: "#377DFF") ?? .blue,
                        disabledHelp: "Export in progress",
                        enabledHelp: "Exporting",
                        action: {}
                    )
                    if !workspace.exportDetail.isEmpty {
                        Text(workspace.exportDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Button(role: .cancel) {
                        workspace.cancelExport()
                    } label: {
                        Label("Cancel export", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    SidebarFieldLabel("Video quality")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(CarouselExportQuality.allCases) { quality in
                            ExportQualityTile(
                                quality: quality,
                                isSelected: workspace.selectedProject.exportQuality == quality
                            ) {
                                workspace.selectedProject.exportQuality = quality
                            }
                        }
                    }
                    Text(exportQualityDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    SidebarFieldLabel("Export as")
                    ExportOptionButton(
                        title: "Video",
                        subtitle: "MP4 motion carousel",
                        icon: "film",
                        detail: exportDimensions,
                        action: onExportVideo
                    )
                    ExportOptionButton(
                        title: "Images",
                        subtitle: "PNG slide set",
                        icon: "photo.stack",
                        detail: "\(workspace.selectedProject.exportCards.count) slides",
                        action: onExportImages
                    )
                    ExportOptionButton(
                        title: "Bundle",
                        subtitle: "Video, images, copy, and JSON",
                        icon: "folder.badge.gearshape",
                        detail: exportBundleDetail,
                        action: onExportBundle
                    )
                }
            }
            if !workspace.isExporting, let message = workspace.lastMessage, message.localizedCaseInsensitiveContains("export") {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var activeExportTitle: String {
        workspace.exportStatus.isEmpty ? "Preparing export" : workspace.exportStatus
    }

    private var activeExportSubtitle: String {
        let percent = Int((workspace.exportProgress * 100).rounded())
        if workspace.exportDestinationName.isEmpty {
            return "\(percent)% complete"
        }
        return "\(percent)% · \(workspace.exportDestinationName)"
    }

    private var exportQualityDescription: String {
        let quality = workspace.selectedProject.exportQuality
        return "\(exportDimensions) · \(quality.fps)fps · \(quality.useCase)"
    }

    private var narrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioVoiceoverControls(
                engine: $workspace.selectedProject.narrationEngine,
                voice: $workspace.selectedProject.piperVoice,
                isPreviewing: workspace.selectedProject.isPreviewingVoice,
                isGenerating: workspace.selectedProject.isGeneratingNarration,
                isInstalling: workspace.selectedProject.isInstallingPiper,
                isCaching: workspace.selectedProject.isCachingVoicePreviews,
                isDeletingAssets: isDeletingVoiceAssets,
                hasNarration: workspace.selectedProject.narrationAudioURL != nil,
                installationStatus: workspace.selectedProject.narrationEngineInstallationStatus,
                storageSummary: voiceStorageSummary,
                status: narrationStatusMessage,
                errorMessage: narrationErrorMessage,
                onPreview: previewVoice,
                onRemove: removeManualNarration,
                onInstall: installSelectedVoiceEngine,
                onDeleteAssets: { isConfirmingVoiceAssetDeletion = true }
            )

            Divider()

            Button {
                generateSlideVoiceovers()
            } label: {
                Label(workspace.selectedProject.isGeneratingNarration ? "Generating slide voiceovers..." : "Generate slide voiceovers", systemImage: "waveform.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(
                workspace.selectedProject.cards.isEmpty
                    || workspace.selectedProject.isGeneratingNarration
                    || workspace.selectedProject.isInstallingPiper
                    || workspace.selectedProject.isCachingVoicePreviews
                    || workspace.selectedProject.isPreviewingVoice
            )

            if !slideNarrationSummary.isEmpty {
                CompactStatusMessage(text: slideNarrationSummary, icon: "rectangle.stack.badge.play", tint: .secondary)
            }

            DisclosureGroup("Manual narration") {
                VStack(alignment: .leading, spacing: 10) {
                    StudioVoiceoverScriptEditor(
                        title: "Script",
                        placeholder: "Write a single voiceover for the full carousel...",
                        text: $workspace.selectedProject.narrationScript
                    )

                    Button {
                        generateNarration()
                    } label: {
                        Label(workspace.selectedProject.isGeneratingNarration ? "Generating voiceover..." : "Generate manual voiceover", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        workspace.selectedProject.isGeneratingNarration
                            || workspace.selectedProject.isInstallingPiper
                            || workspace.selectedProject.isCachingVoicePreviews
                            || workspace.selectedProject.narrationScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .padding(.top, 6)
            }
            .font(.caption.weight(.medium))
        }
    }

    private var narrationStatusMessage: (text: String, icon: String, tint: Color)? {
        let project = workspace.selectedProject
        if project.isInstallingPiper {
            if let message = project.narrationMessage, !isErrorMessage(message) {
                return (message, "arrow.down.circle", .secondary)
            }
            return ("Setting up \(project.narrationEngine.displayName)...", "arrow.down.circle", .secondary)
        }
        if project.isCachingVoicePreviews {
            if let message = project.narrationMessage, !isErrorMessage(message) {
                return (message, "bolt.circle", .secondary)
            }
            return ("Preparing quick previews in the background...", "bolt.circle", .secondary)
        }
        if project.isGeneratingNarration {
            return ("Generating voiceovers...", "waveform", .secondary)
        }
        if project.isPreviewingVoice {
            return ("Playing preview...", "play.circle", .secondary)
        }
        if project.narrationAudioURL != nil {
            return ("Manual voiceover ready", "checkmark.circle.fill", .green)
        }
        if let message = project.narrationMessage, !isErrorMessage(message) {
            return (message, "info.circle", .secondary)
        }
        return nil
    }

    private var narrationErrorMessage: String? {
        guard let message = workspace.selectedProject.narrationMessage, isErrorMessage(message) else { return nil }
        return message
    }

    private func isErrorMessage(_ message: String) -> Bool {
        if message.localizedCaseInsensitiveContains("complete:") {
            return false
        }
        return message.localizedCaseInsensitiveContains("error")
            || message.localizedCaseInsensitiveContains("failed")
            || message.localizedCaseInsensitiveContains("not installed")
            || message.localizedCaseInsensitiveContains("no module named")
            || message.localizedCaseInsensitiveContains("externally-managed")
    }

    private var slideNarrationSummary: String {
        let cards = workspace.selectedProject.cards
        guard !cards.isEmpty else { return "" }
        let generated = cards.filter { $0.narrationStatus == .generated }.count
        let skipped = cards.filter { $0.narrationStatus == .skipped }.count
        let failed = cards.filter { $0.narrationStatus == .failed }.count
        guard generated + skipped + failed > 0 else { return "" }
        return "\(generated) generated · \(skipped) skipped · \(failed) failed"
    }

    private var exportSubtitle: String {
        let dims = exportDimensions
        let total = workspace.selectedProject.cards.count
        let suffix = total == 1 ? " · 1 slide" : total > 1 ? " · \(total) slides" : ""
        return "\(dims) · \(workspace.selectedProject.exportQuality.label) · MP4 · PNG · copy\(suffix)"
    }

    private var exportBundleDetail: String {
        let total = workspace.selectedProject.cards.count
        guard total > 0 else { return workspace.selectedProject.exportQuality.label }
        return total == 1 ? "1 slide" : "\(total) slides"
    }

    private var exportDimensions: String {
        let size = workspace.selectedProject.canvasAspect.renderSize(for: workspace.selectedProject.exportQuality)
        return "\(Int(size.width))×\(Int(size.height))"
    }

    private func removeManualNarration() {
        NarrationService.cleanupGeneratedNarration(at: workspace.selectedProject.narrationAudioURL)
        workspace.selectedProject.narrationAudioURL = nil
        workspace.selectedProject.narrationDisplayName = nil
        workspace.selectedProject.narrationMessage = nil
    }

    private func generateNarration() {
        let project = workspace.selectedProject
        guard !project.isGeneratingNarration,
              !project.isInstallingPiper,
              !project.isCachingVoicePreviews else { return }
        let request = NarrationRequest(
            engine: project.narrationEngine,
            text: project.narrationScript,
            voice: project.piperVoice
        )
        project.isGeneratingNarration = true
        project.narrationMessage = "Generating local \(project.narrationEngine.displayName) narration..."

        Task {
            do {
                let url = try await NarrationService.generate(request)
                await MainActor.run {
                    NarrationService.cleanupGeneratedNarration(at: project.narrationAudioURL)
                    project.narrationAudioURL = url
                    project.narrationDisplayName = url.lastPathComponent
                    project.narrationMessage = "Voiceover will be included in video exports."
                    project.isGeneratingNarration = false
                }
                await NarrationService.warmPreviewsIfNeeded(for: request.engine)
                await refreshVoiceStorageSummary()
            } catch {
                await MainActor.run {
                    project.narrationMessage = error.localizedDescription
                    updateVoiceEngineInstallationStatusFromError(error, engine: request.engine, project: project)
                    project.isGeneratingNarration = false
                }
            }
        }
    }

    private func generateSlideVoiceovers() {
        let project = workspace.selectedProject
        guard !project.isGeneratingNarration,
              !project.isInstallingPiper,
              !project.isCachingVoicePreviews,
              !project.isPreviewingVoice else { return }
        let cards = project.cards
        let engine = project.narrationEngine
        let voice = project.piperVoice
        guard !cards.isEmpty else { return }

        project.isGeneratingNarration = true
        project.narrationMessage = "Generating 0 of \(cards.count) slide voiceovers..."

        Task {
            var generated = 0
            var skipped = 0
            var failed = 0
            var firstError: String?

            for (index, card) in cards.enumerated() {
                await MainActor.run {
                    card.narrationStatus = .detecting
                    card.narrationError = nil
                    project.narrationMessage = "Generating \(index + 1) of \(cards.count): \(card.displayName)"
                }

                do {
                    let source = await MainActor.run {
                        CarouselSlideNarrationService.Source(card: card)
                    }
                    let editedScript = await MainActor.run {
                        card.narrationScriptEdited ? card.narrationScript : nil
                    }
                    await MainActor.run {
                        card.narrationStatus = .generating
                    }

                    if let editedScript {
                        let audio = try await CarouselSlideNarrationService.generateAudio(
                            script: editedScript,
                            engine: engine,
                            voice: voice
                        )
                        await MainActor.run {
                            if let audio {
                                NarrationService.cleanupGeneratedNarration(at: card.narrationAudioURL)
                                card.narrationScript = CarouselSlideNarrationService.cleanedSpokenScript(from: editedScript)
                                card.narrationScriptEdited = true
                                card.narrationAudioURL = audio.url
                                card.narrationAudioDuration = audio.duration
                                card.narrationStatus = .generated
                                card.duration = max(0.5, min(30.0, audio.duration + 0.4))
                                generated += 1
                            } else {
                                NarrationService.cleanupGeneratedNarration(at: card.narrationAudioURL)
                                card.narrationAudioURL = nil
                                card.narrationAudioDuration = nil
                                card.narrationStatus = .skipped
                                skipped += 1
                            }
                        }
                        continue
                    }

                    let result = try await CarouselSlideNarrationService.generate(from: source, engine: engine, voice: voice)
                    await MainActor.run {
                        if let result {
                            NarrationService.cleanupGeneratedNarration(at: card.narrationAudioURL)
                            card.detectedNarrationText = result.detectedText
                            card.narrationScript = result.script
                            card.narrationScriptEdited = false
                            card.narrationAudioURL = result.audioURL
                            card.narrationAudioDuration = result.audioDuration
                            card.narrationStatus = .generated
                            card.duration = max(0.5, min(30.0, result.audioDuration + 0.4))
                            generated += 1
                        } else {
                            NarrationService.cleanupGeneratedNarration(at: card.narrationAudioURL)
                            card.detectedNarrationText = ""
                            card.narrationScript = ""
                            card.narrationScriptEdited = false
                            card.narrationAudioURL = nil
                            card.narrationAudioDuration = nil
                            card.narrationStatus = .skipped
                            skipped += 1
                        }
                    }
                } catch {
                    await MainActor.run {
                        NarrationService.cleanupGeneratedNarration(at: card.narrationAudioURL)
                        card.narrationAudioURL = nil
                        card.narrationAudioDuration = nil
                        card.narrationStatus = .failed
                        card.narrationError = error.localizedDescription
                        updateVoiceEngineInstallationStatusFromError(error, engine: engine, project: project)
                        firstError = firstError ?? error.localizedDescription
                        failed += 1
                    }
                }
            }

            await MainActor.run {
                project.validate()
                if let firstError, generated == 0, failed > 0 {
                    project.narrationMessage = firstError
                } else {
                    project.narrationMessage = "Slide voiceovers complete: \(generated) generated, \(skipped) skipped, \(failed) failed."
                }
                project.isGeneratingNarration = false
            }
            await NarrationService.warmPreviewsIfNeeded(for: engine)
            await refreshVoiceStorageSummary()
        }
    }

    private func previewVoice() {
        let project = workspace.selectedProject
        guard !project.isGeneratingNarration,
              !project.isInstallingPiper,
              !project.isCachingVoicePreviews else { return }
        if project.isPreviewingVoice {
            stopVoicePreview(for: project, message: "Preview stopped.")
            return
        }
        voicePreviewTask?.cancel()
        voicePreviewSound?.stop()
        voicePreviewSound = nil

        let request = NarrationRequest(
            engine: project.narrationEngine,
            text: NarrationService.previewText,
            voice: project.piperVoice
        )
        let token = UUID()
        voicePreviewToken = token
        project.isPreviewingVoice = true
        project.narrationMessage = "Generating voice preview..."

        voicePreviewTask = Task {
            do {
                let preview = try await NarrationService.preview(request)
                await MainActor.run {
                    guard voicePreviewToken == token else { return }
                    voicePreviewSound?.stop()
                    let sound = NSSound(contentsOf: preview.url, byReference: true)
                    voicePreviewSound = sound
                    voicePreviewSound?.play()
                    project.narrationMessage = preview.usedCache ? "Playing cached preview." : "Preview ready."
                    project.isPreviewingVoice = false
                }
                await NarrationService.warmPreviewsIfNeeded(for: request.engine)
                await refreshVoiceStorageSummary()
            } catch is CancellationError {
                await MainActor.run {
                    guard voicePreviewToken == token else { return }
                    project.isPreviewingVoice = false
                }
            } catch {
                await MainActor.run {
                    guard voicePreviewToken == token else { return }
                    project.narrationMessage = error.localizedDescription
                    updateVoiceEngineInstallationStatusFromError(error, engine: request.engine, project: project)
                    project.isPreviewingVoice = false
                }
            }
        }
    }

    private func stopVoicePreview(for project: CarouselProject, message: String? = nil) {
        voicePreviewTask?.cancel()
        voicePreviewTask = nil
        voicePreviewToken = nil
        voicePreviewSound?.stop()
        voicePreviewSound = nil
        project.isPreviewingVoice = false
        if let message {
            project.narrationMessage = message
        }
    }

    private func installSelectedVoiceEngine() {
        let project = workspace.selectedProject
        guard !project.isInstallingPiper,
              !project.isGeneratingNarration,
              !project.isCachingVoicePreviews else { return }
        project.isInstallingPiper = true
        let engine = project.narrationEngine
        let isRefresh = project.narrationEngineInstallationStatus == .installed
        project.narrationMessage = "\(isRefresh ? "Refreshing" : "Installing") \(engine.displayName): starting..."

        Task {
            do {
                try await NarrationService.install(engine) { message in
                    Task { @MainActor in
                        project.narrationMessage = message
                    }
                }
                await MainActor.run {
                    project.isInstallingPiper = false
                    project.isCachingVoicePreviews = true
                    project.narrationMessage = "\(engine.displayName) installed. Preparing fast previews..."
                }
                try await NarrationService.cacheVoicePreviews(for: engine) { message in
                    Task { @MainActor in
                        project.narrationMessage = message
                    }
                }
                await MainActor.run {
                    project.narrationMessage = "\(engine.displayName) installed. Fast previews are ready."
                    project.narrationEngineInstallationStatus = .installed
                    project.isCachingVoicePreviews = false
                }
                await refreshVoiceStorageSummary()
            } catch {
                await MainActor.run {
                    project.narrationMessage = error.localizedDescription
                    updateVoiceEngineInstallationStatusFromError(error, engine: engine, project: project)
                    project.isInstallingPiper = false
                    project.isCachingVoicePreviews = false
                }
                await refreshVoiceStorageSummary()
            }
        }
    }

    private func refreshVoiceEngineInstallationStatus() async {
        let project = workspace.selectedProject
        let engine = project.narrationEngine
        let status = await NarrationService.installationStatus(for: engine)
        await MainActor.run {
            guard workspace.selectedProject.id == project.id,
                  workspace.selectedProject.narrationEngine == engine else { return }
            workspace.selectedProject.narrationEngineInstallationStatus = status
        }
    }

    private func refreshVoiceStorageSummary() async {
        let summary = await NarrationService.storageSummary()
        await MainActor.run {
            voiceStorageSummary = summary
        }
    }

    private func deleteSelectedVoiceEngineAssets() {
        let project = workspace.selectedProject
        guard !isDeletingVoiceAssets,
              !project.isInstallingPiper,
              !project.isGeneratingNarration,
              !project.isCachingVoicePreviews else { return }
        isDeletingVoiceAssets = true
        let projectID = project.id
        let engine = project.narrationEngine
        project.narrationMessage = "Deleting \(engine.displayName) voice assets..."

        Task {
            do {
                try await NarrationService.deleteAssets(for: engine)
                let summary = await NarrationService.storageSummary()
                await MainActor.run {
                    if workspace.selectedProject.id == projectID,
                       workspace.selectedProject.narrationEngine == engine {
                        workspace.selectedProject.narrationEngineInstallationStatus = .notInstalled
                    }
                    voiceStorageSummary = summary
                    project.narrationMessage = "\(engine.displayName) voice assets deleted. Generated project voiceovers were kept."
                    isDeletingVoiceAssets = false
                }
            } catch {
                await MainActor.run {
                    project.narrationMessage = error.localizedDescription
                    isDeletingVoiceAssets = false
                }
                await refreshVoiceStorageSummary()
            }
        }
    }

    private func updateVoiceEngineInstallationStatusFromError(_ error: Error, engine: NarrationEngine, project: CarouselProject) {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("not installed")
            || message.localizedCaseInsensitiveContains("no module named")
            || message.localizedCaseInsensitiveContains("externally-managed")
            || message.localizedCaseInsensitiveContains("externally managed") {
            project.narrationEngineInstallationStatus = .notInstalled
        }
        if message.localizedCaseInsensitiveContains("requires Python") || message.localizedCaseInsensitiveContains("incompatible") {
            project.narrationEngineInstallationStatus = .incompatible
        }
    }
}

private struct CarouselProjectChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let onNewCarousel: () -> Void
    let onCloseCarousel: () -> Void
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)

            if isSelected {
                HStack(spacing: 4) {
                    Button(action: onNewCarousel) {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("New carousel")

                    Button(role: .destructive, action: onCloseCarousel) {
                        Image(systemName: "xmark")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Close selected carousel")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 12)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? AnyShapeStyle(AppChrome.accentGradient) : AnyShapeStyle(Color.gray.opacity(0.12)))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? Color.white.opacity(0.22) : Color.gray.opacity(0.18), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture(perform: action)
    }
}

private struct ExportOptionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let detail: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(isHovering ? 0.18 : 0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#377DFF") ?? .blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                Text(detail)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: 92, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(isHovering ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(isHovering ? 0.24 : 0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct ExportQualityTile: View {
    let quality: CarouselExportQuality
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .bold))
                    Text(quality.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text("\(quality.detail) · \(quality.fps)fps")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AnyShapeStyle(AppChrome.accentGradient) : AnyShapeStyle(Color.gray.opacity(isHovering ? 0.14 : 0.08)))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.white.opacity(0.24) : Color.gray.opacity(isHovering ? 0.24 : 0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("\(quality.useCase): \(quality.detail), \(quality.fps)fps")
    }
}

private struct SidebarFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct CarouselOptionChip: View {
    let label: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AnyShapeStyle(AppChrome.accentGradient) : AnyShapeStyle(Color.gray.opacity(0.12)))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white.opacity(0.22) : Color.gray.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
