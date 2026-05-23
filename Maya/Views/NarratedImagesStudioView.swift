import AppKit
import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct NarratedImagesStudioView: View {
    @Binding var selectedMode: StudioMode
    @State private var workspace = NarratedImagesWorkspace()
    @State private var exporter = NarratedImagesExportService()
    @State private var currentTime = 0.0
    @State private var isPlaying = false
    @State private var playbackAnchorTime = 0.0
    @State private var playbackStartedAt: Date?
    @State private var playbackTickTime: Double?
    @State private var isInspectorVisible = true
    @State private var voiceoverPlayer: AVAudioPlayer?
    @State private var voiceoverSceneID: UUID?
    @State private var voicePreviewSound: NSSound?
    @State private var voicePreviewTask: Task<Void, Never>?
    @State private var voicePreviewToken: UUID?
    @State private var voiceStorageSummary: NarrationStorageSummary?
    @State private var isDeletingVoiceAssets = false
    @State private var isConfirmingVoiceAssetDeletion = false

    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            NarratedImagesSidebar(
                workspace: workspace,
                onNewProject: workspace.addProject,
                onCloseProject: workspace.closeSelectedProject,
                onImportImages: openImagePicker,
                onOpenInspector: { isInspectorVisible = true },
                onGenerateVoiceover: generateVoiceoverForSelectedScene,
                onGenerateCaptions: generateCaptionsForSelectedScene,
                onRegenerateVoiceAndCaptions: regenerateVoiceAndCaptionsForSelectedScene,
                onGenerateAllScenes: generateAllScenes,
                onAlignCaptionsToVoice: alignCaptionsForSelectedScene,
                onExportVideo: exportVideo,
                isInspectorVisible: isInspectorVisible,
                voiceStorageSummary: voiceStorageSummary,
                isDeletingVoiceAssets: isDeletingVoiceAssets,
                onPreviewVoice: previewVoice,
                onInstallVoiceEngine: installSelectedVoiceEngine,
                onInstallCaptionAligner: installCaptionAligner,
                onDeleteVoiceAssets: { isConfirmingVoiceAssetDeletion = true }
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 430)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    NarratedImagesCanvasView(
                        project: workspace.selectedProject,
                        currentTime: currentTime,
                        onImportImages: openImagePicker
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .dropDestination(for: URL.self) { urls, _ in
                        importImages(from: urls)
                        return true
                    }

                    if !workspace.selectedProject.scenes.isEmpty {
                        NarratedImagesTimelineView(
                            project: workspace.selectedProject,
                            currentTime: $currentTime,
                            isPlaying: $isPlaying
                        )
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))

                if isInspectorVisible {
                    Divider()
                    NarratedImagesInspector(
                        project: workspace.selectedProject,
                        onGenerateCaptions: generateCaptionsForSelectedScene,
                        onRegenerateVoiceover: generateVoiceoverForSelectedScene,
                        onRegenerateVoiceAndCaptions: regenerateVoiceAndCaptionsForSelectedScene,
                        onAlignCaptionsToVoice: alignCaptionsForSelectedScene,
                        onInstallCaptionAligner: installCaptionAligner
                    ) {
                        isInspectorVisible = false
                    }
                    .frame(width: 360)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isInspectorVisible)
        }
        .navigationTitle(AppChrome.title)
        .navigationSubtitle(AppChrome.versionLabel)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                StudioModePicker(selectedMode: $selectedMode)
            }
        }
        .task {
            await refreshVoiceEngineInstallationStatus()
            await refreshCaptionAlignerInstallationStatus()
            await refreshVoiceStorageSummary()
            await warmContentCreationPipeline()
        }
        .onReceive(timer) { _ in
            let project = workspace.selectedProject
            guard isPlaying, project.totalDuration > 0 else { return }

            let now = Date()
            if playbackStartedAt == nil {
                startPlaybackClock(at: currentTime, now: now)
            }

            let elapsed = now.timeIntervalSince(playbackStartedAt ?? now)
            var nextTime = playbackAnchorTime + elapsed
            if nextTime >= project.totalDuration {
                nextTime = nextTime.truncatingRemainder(dividingBy: project.totalDuration)
                startPlaybackClock(at: nextTime, now: now)
                stopVoiceoverPlayback()
            }

            playbackTickTime = nextTime
            currentTime = nextTime
            project.selectScene(at: currentTime)
            syncVoiceoverPlayback(correctExistingPlayer: false)
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                startPlaybackClock(at: currentTime)
                syncVoiceoverPlayback()
            } else {
                playbackStartedAt = nil
                stopVoiceoverPlayback()
            }
        }
        .onChange(of: currentTime) { _, newValue in
            if let playbackTickTime,
               abs(playbackTickTime - newValue) < 0.002 {
                self.playbackTickTime = nil
                return
            }
            guard isPlaying else { return }
            startPlaybackClock(at: currentTime)
            syncVoiceoverPlayback()
        }
        .onChange(of: workspace.selectedProject.selectedSceneID) { _, _ in
            guard !isPlaying else { return }
            guard let id = workspace.selectedProject.selectedSceneID else { return }
            currentTime = workspace.selectedProject.startTime(for: id)
        }
        .onChange(of: workspace.selectedProjectID) { _, _ in
            currentTime = 0
            isPlaying = false
            stopVoiceoverPlayback()
            Task {
                await refreshVoiceEngineInstallationStatus()
                await refreshCaptionAlignerInstallationStatus()
                await refreshVoiceStorageSummary()
            }
        }
        .onChange(of: workspace.selectedProject.narrationEngine) { _, _ in
            Task {
                await refreshVoiceEngineInstallationStatus()
                await refreshCaptionAlignerInstallationStatus()
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
            Text("This removes the selected engine's installed files, downloaded voice models, and cached previews. Generated scene voiceovers are kept.")
        }
    }

    private func openImagePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            importImages(from: panel.urls)
        }
    }

    private func importImages(from urls: [URL]) {
        let imageURLs = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
        guard !imageURLs.isEmpty else { return }
        do {
            let scenes = try imageURLs.map { url in
                let adopted = try CarouselImageImporter.adoptIntoSandbox(url)
                return NarratedImageScene(imageURL: adopted.sandboxURL, displayName: adopted.displayName)
            }
            workspace.selectedProject.addScenes(scenes)
            currentTime = workspace.selectedProject.startTime(for: scenes.first?.id ?? workspace.selectedProject.selectedSceneID ?? UUID())
            workspace.lastMessage = "Imported \(scenes.count) image\(scenes.count == 1 ? "" : "s")."
            workspace.lastError = nil
        } catch {
            workspace.lastError = "Could not import images: \(error.localizedDescription)"
        }
    }

    private func generateVoiceoverForSelectedScene() {
        generateVoiceoverForSelectedScene(regenerateCaptionsAfterVoice: false)
    }

    private func regenerateVoiceAndCaptionsForSelectedScene() {
        generateVoiceoverForSelectedScene(regenerateCaptionsAfterVoice: true)
    }

    private func generateAllScenes() {
        let project = workspace.selectedProject
        guard !project.isGeneratingNarration,
              !project.isInstallingVoiceEngine,
              !project.isCachingVoicePreviews else { return }
        let scenes = project.scenes.filter { !$0.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !scenes.isEmpty else { return }

        project.isGeneratingNarration = true
        project.narrationMessage = "Generating \(scenes.count) scene\(scenes.count == 1 ? "" : "s")..."
        project.captionAlignmentMessage = "Preparing content pipeline..."

        Task {
            var activeScene: NarratedImageScene?
            do {
                if project.narrationEngineInstallationStatus != .installed {
                    try await NarrationService.install(project.narrationEngine) { message in
                        Task { @MainActor in project.narrationMessage = message }
                    }
                    await MainActor.run { project.narrationEngineInstallationStatus = .installed }
                }
                try await ensureCaptionAlignerInstalled(project: project)
                await NarrationService.warmEngines(engine: project.narrationEngine)
                try? await NarratedCaptionAlignmentService.warm()

                for (index, scene) in scenes.enumerated() {
                    try Task.checkCancellation()
                    activeScene = scene
                    await MainActor.run {
                        project.selectedSceneID = scene.id
                        scene.narrationStatus = .generating
                        scene.narrationError = nil
                        scene.captionAlignmentStatus = .aligning
                        scene.captionAlignmentError = nil
                        project.narrationMessage = "Generating scene \(index + 1) of \(scenes.count): \(scene.displayName)"
                        project.captionAlignmentMessage = "Generating voice and aligned captions..."
                    }
                    try await generateVoiceAndAlignedCaptions(for: scene, project: project)
                }

                await MainActor.run {
                    project.narrationMessage = "Generated \(scenes.count) scene\(scenes.count == 1 ? "" : "s")."
                    project.captionAlignmentMessage = "Voice-aligned captions ready."
                    project.isGeneratingNarration = false
                }
                await refreshVoiceStorageSummary()
            } catch {
                await MainActor.run {
                    activeScene?.narrationStatus = .failed
                    activeScene?.narrationError = error.localizedDescription
                    activeScene?.captionAlignmentStatus = .failed
                    activeScene?.captionAlignmentError = error.localizedDescription
                    project.narrationMessage = error.localizedDescription
                    project.captionAlignmentMessage = error.localizedDescription
                    project.isGeneratingNarration = false
                }
            }
        }
    }

    private func generateVoiceoverForSelectedScene(regenerateCaptionsAfterVoice: Bool) {
        let project = workspace.selectedProject
        guard let scene = project.selectedScene,
              !project.isGeneratingNarration,
              !project.isInstallingVoiceEngine,
              !project.isCachingVoicePreviews else { return }
        let script = scene.script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { return }

        project.isGeneratingNarration = true
        project.narrationMessage = regenerateCaptionsAfterVoice
            ? "Regenerating voice and captions for \(scene.displayName)..."
            : "Generating voiceover for \(scene.displayName)..."
        scene.narrationStatus = .generating
        scene.narrationError = nil
        let request = NarrationRequest(engine: project.narrationEngine, text: script, voice: project.voice)

        Task {
            do {
                let url = try await NarrationService.generate(request)
                let duration = try await CarouselSlideNarrationService.audioDuration(for: url)
                let shouldAlignCaptions = regenerateCaptionsAfterVoice || scene.captionBeats.isEmpty
                var alignedBeats: [NarratedCaptionBeat]?
                var alignmentError: String?
                if shouldAlignCaptions {
                    await MainActor.run {
                        project.captionAlignmentMessage = "Preparing voice-aligned captions..."
                        scene.captionAlignmentStatus = .aligning
                        scene.captionAlignmentError = nil
                    }
                    do {
                        try await ensureCaptionAlignerInstalled(project: project)
                        await MainActor.run {
                            project.captionAlignmentMessage = "Aligning captions to voice..."
                        }
                        let alignment = try await NarratedCaptionAlignmentService.align(
                            audioURL: url,
                            script: script,
                            duration: duration
                        )
                        alignedBeats = alignment.beats
                    } catch {
                        alignmentError = error.localizedDescription
                    }
                }
                await MainActor.run {
                    NarrationService.cleanupGeneratedNarration(at: scene.narrationAudioURL)
                    scene.narrationAudioURL = url
                    scene.narrationAudioDuration = duration
                    scene.duration = max(0.5, min(30.0, duration + 0.4))
                    scene.narrationStatus = .generated
                    if let alignedBeats {
                        project.applyAlignedCaptions(alignedBeats, to: scene)
                        project.captionAlignmentMessage = "Voice-aligned captions ready."
                    } else if shouldAlignCaptions {
                        project.generateCaptions(for: scene)
                        if let alignmentError {
                            scene.captionAlignmentStatus = .failed
                            scene.captionAlignmentError = alignmentError
                            project.captionAlignmentMessage = "Alignment failed. Estimated captions were created."
                        }
                    } else {
                        project.retimeCaptionsToSceneDuration(for: scene)
                    }
                    project.narrationMessage = regenerateCaptionsAfterVoice
                        ? "Regenerated voice and captions for \(scene.displayName)."
                        : "Generated voiceover for \(scene.displayName)."
                    project.isGeneratingNarration = false
                }
                await NarrationService.warmPreviewsIfNeeded(for: request.engine)
                await refreshVoiceStorageSummary()
            } catch {
                await MainActor.run {
                    scene.narrationStatus = .failed
                    scene.narrationError = error.localizedDescription
                    project.narrationMessage = error.localizedDescription
                    updateVoiceEngineInstallationStatusFromError(error, engine: request.engine, project: project)
                    project.isGeneratingNarration = false
                }
            }
        }
    }

    private func generateVoiceAndAlignedCaptions(for scene: NarratedImageScene, project: NarratedImageProject) async throws {
        let script = scene.script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { throw PiperNarrationError.emptyScript }
        let request = NarrationRequest(engine: project.narrationEngine, text: script, voice: project.voice)
        let url = try await NarrationService.generate(request)
        let duration = try await CarouselSlideNarrationService.audioDuration(for: url)
        let alignment = try await NarratedCaptionAlignmentService.align(audioURL: url, script: script, duration: duration)
        await MainActor.run {
            NarrationService.cleanupGeneratedNarration(at: scene.narrationAudioURL)
            scene.narrationAudioURL = url
            scene.narrationAudioDuration = duration
            scene.duration = max(0.5, min(30.0, duration + 0.4))
            scene.narrationStatus = .generated
            project.applyAlignedCaptions(alignment.beats, to: scene)
        }
    }

    private func generateCaptionsForSelectedScene() {
        guard let scene = workspace.selectedProject.selectedScene else { return }
        if scene.narrationAudioURL != nil {
            alignCaptionsForSelectedScene()
            return
        }
        workspace.selectedProject.generateCaptions(for: scene)
        workspace.lastMessage = "Generated estimated captions for \(scene.displayName)."
    }

    private func alignCaptionsForSelectedScene() {
        let project = workspace.selectedProject
        guard let scene = project.selectedScene,
              let audioURL = scene.narrationAudioURL,
              !project.isGeneratingNarration,
              !project.isInstallingCaptionAligner else {
            return
        }
        let script = scene.script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { return }
        let duration = scene.narrationAudioDuration ?? scene.duration
        project.isGeneratingNarration = true
        project.captionAlignmentMessage = "Preparing voice-aligned captions..."
        scene.captionAlignmentStatus = .aligning
        scene.captionAlignmentError = nil

        Task {
            do {
                try await ensureCaptionAlignerInstalled(project: project)
                await MainActor.run {
                    project.captionAlignmentMessage = "Aligning captions to voice..."
                }
                let result = try await NarratedCaptionAlignmentService.align(
                    audioURL: audioURL,
                    script: script,
                    duration: duration
                )
                await MainActor.run {
                    project.applyAlignedCaptions(result.beats, to: scene)
                    project.captionAlignmentMessage = "Voice-aligned captions ready."
                    project.narrationMessage = nil
                    project.isGeneratingNarration = false
                }
            } catch {
                await MainActor.run {
                    project.generateCaptions(for: scene)
                    scene.captionAlignmentStatus = .failed
                    scene.captionAlignmentError = error.localizedDescription
                    project.captionAlignmentMessage = "Alignment failed. Estimated captions were created."
                    project.isGeneratingNarration = false
                }
            }
        }
    }

    private func ensureCaptionAlignerInstalled(project: NarratedImageProject) async throws {
        guard project.captionAlignerInstallationStatus != .installed else { return }
        let currentStatus = await NarratedCaptionAlignmentService.installationStatus()
        await MainActor.run {
            project.captionAlignerInstallationStatus = currentStatus
        }
        guard currentStatus != .installed else { return }
        await MainActor.run {
            project.isInstallingCaptionAligner = true
            project.captionAlignmentMessage = "Installing caption aligner for automatic voice timing..."
        }
        do {
            try await NarratedCaptionAlignmentService.install { message in
                Task { @MainActor in project.captionAlignmentMessage = message }
            }
            await MainActor.run {
                project.captionAlignerInstallationStatus = .installed
                project.isInstallingCaptionAligner = false
                project.captionAlignmentMessage = "Caption aligner ready."
            }
        } catch {
            await MainActor.run {
                project.captionAlignerInstallationStatus = .notInstalled
                project.isInstallingCaptionAligner = false
            }
            throw error
        }
    }

    private func exportVideo() {
        let project = workspace.selectedProject
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(safeName(project.title)).mp4"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let task = Task {
            workspace.isExporting = true
            workspace.exportProgress = 0
            workspace.exportStatus = "Preparing export"
            workspace.exportDestinationName = url.lastPathComponent
            workspace.lastError = nil
            do {
                try await exporter.exportVideo(project: project, to: url) { progress in
                    Task { @MainActor in
                        workspace.exportStatus = progress.phase.title
                        workspace.exportDetail = progress.detail
                        workspace.exportProgress = progress.progress
                    }
                }
                workspace.lastMessage = "Exported narrated images video."
            } catch is CancellationError {
                workspace.lastMessage = "Export canceled."
            } catch {
                workspace.lastError = error.localizedDescription
            }
            workspace.exportStatus = ""
            workspace.exportDetail = ""
            workspace.exportDestinationName = ""
            workspace.isExporting = false
            workspace.activeExportTask = nil
        }
        workspace.activeExportTask = task
    }

    private func syncVoiceoverPlayback(correctExistingPlayer: Bool = true) {
        let project = workspace.selectedProject
        guard isPlaying,
              let sample = project.timelineSample(at: currentTime),
              let audioURL = sample.scene.narrationAudioURL else {
            stopVoiceoverPlayback()
            return
        }
        let maxTime = sample.scene.narrationAudioDuration ?? sample.localTime
        let targetTime = max(0, min(sample.localTime, maxTime))
        if voiceoverSceneID == sample.scene.id, let player = voiceoverPlayer {
            if correctExistingPlayer, abs(player.currentTime - targetTime) > 0.35 {
                player.currentTime = targetTime
            }
            if !player.isPlaying, sample.localTime < maxTime - 0.03 {
                player.play()
            }
            return
        }
        guard sample.localTime < maxTime - 0.03 else { return }
        stopVoiceoverPlayback()
        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.currentTime = targetTime
            player.prepareToPlay()
            player.play()
            voiceoverPlayer = player
            voiceoverSceneID = sample.scene.id
        } catch {
            project.narrationMessage = error.localizedDescription
        }
    }

    private func startPlaybackClock(at time: Double, now: Date = Date()) {
        playbackAnchorTime = time
        playbackStartedAt = now
    }

    private func stopVoiceoverPlayback() {
        voiceoverPlayer?.stop()
        voiceoverPlayer = nil
        voiceoverSceneID = nil
    }

    private func previewVoice() {
        let project = workspace.selectedProject
        guard !project.isGeneratingNarration,
              !project.isInstallingVoiceEngine,
              !project.isCachingVoicePreviews else { return }
        if project.isPreviewingVoice {
            voicePreviewSound?.stop()
            project.isPreviewingVoice = false
            project.narrationMessage = "Preview stopped."
            return
        }
        voicePreviewTask?.cancel()
        voicePreviewSound?.stop()
        let request = NarrationRequest(engine: project.narrationEngine, text: NarrationService.previewText, voice: project.voice)
        let token = UUID()
        voicePreviewToken = token
        project.isPreviewingVoice = true
        project.narrationMessage = "Generating voice preview..."
        voicePreviewTask = Task {
            do {
                let preview = try await NarrationService.preview(request)
                await MainActor.run {
                    guard voicePreviewToken == token else { return }
                    let sound = NSSound(contentsOf: preview.url, byReference: true)
                    voicePreviewSound = sound
                    voicePreviewSound?.play()
                    project.narrationMessage = preview.usedCache ? "Playing cached preview." : "Preview ready."
                    project.isPreviewingVoice = false
                }
                await refreshVoiceStorageSummary()
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

    private func installSelectedVoiceEngine() {
        let project = workspace.selectedProject
        guard !project.isInstallingVoiceEngine,
              !project.isGeneratingNarration,
              !project.isCachingVoicePreviews else { return }
        let engine = project.narrationEngine
        project.isInstallingVoiceEngine = true
        project.narrationMessage = "Installing \(engine.displayName): starting..."
        Task {
            do {
                try await NarrationService.install(engine) { message in
                    Task { @MainActor in project.narrationMessage = message }
                }
                await MainActor.run {
                    project.isInstallingVoiceEngine = false
                    project.isCachingVoicePreviews = true
                    project.narrationMessage = "\(engine.displayName) installed. Preparing previews..."
                }
                try await NarrationService.cacheVoicePreviews(for: engine) { message in
                    Task { @MainActor in project.narrationMessage = message }
                }
                await MainActor.run {
                    project.narrationEngineInstallationStatus = .installed
                    project.isCachingVoicePreviews = false
                    project.narrationMessage = "\(engine.displayName) installed."
                }
                await refreshVoiceStorageSummary()
            } catch {
                await MainActor.run {
                    project.narrationMessage = error.localizedDescription
                    updateVoiceEngineInstallationStatusFromError(error, engine: engine, project: project)
                    project.isInstallingVoiceEngine = false
                    project.isCachingVoicePreviews = false
                }
            }
        }
    }

    private func installCaptionAligner() {
        let project = workspace.selectedProject
        guard !project.isInstallingCaptionAligner,
              !project.isGeneratingNarration else { return }
        project.isInstallingCaptionAligner = true
        project.captionAlignmentMessage = "Installing caption aligner..."
        Task {
            do {
                try await NarratedCaptionAlignmentService.install { message in
                    Task { @MainActor in project.captionAlignmentMessage = message }
                }
                await MainActor.run {
                    project.captionAlignerInstallationStatus = .installed
                    project.isInstallingCaptionAligner = false
                    project.captionAlignmentMessage = "Caption aligner installed."
                }
            } catch {
                await MainActor.run {
                    project.captionAlignmentMessage = error.localizedDescription
                    project.captionAlignerInstallationStatus = .notInstalled
                    project.isInstallingCaptionAligner = false
                }
            }
        }
    }

    private func deleteSelectedVoiceEngineAssets() {
        let project = workspace.selectedProject
        guard !isDeletingVoiceAssets else { return }
        isDeletingVoiceAssets = true
        let engine = project.narrationEngine
        project.narrationMessage = "Deleting \(engine.displayName) voice assets..."
        Task {
            do {
                try await NarrationService.deleteAssets(for: engine)
                await MainActor.run {
                    project.narrationEngineInstallationStatus = .notInstalled
                    project.narrationMessage = "\(engine.displayName) voice assets deleted."
                    isDeletingVoiceAssets = false
                }
                await refreshVoiceStorageSummary()
            } catch {
                await MainActor.run {
                    project.narrationMessage = error.localizedDescription
                    isDeletingVoiceAssets = false
                }
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

    private func refreshCaptionAlignerInstallationStatus() async {
        let status = await NarratedCaptionAlignmentService.installationStatus()
        await MainActor.run {
            workspace.selectedProject.captionAlignerInstallationStatus = status
        }
    }

    private func refreshVoiceStorageSummary() async {
        let summary = await NarrationService.storageSummary()
        await MainActor.run {
            voiceStorageSummary = summary
        }
    }

    private func warmContentCreationPipeline() async {
        let project = workspace.selectedProject
        guard project.narrationEngineInstallationStatus == .installed else { return }
        await NarrationService.warmEngines(engine: project.narrationEngine)
        if project.captionAlignerInstallationStatus == .installed {
            try? await NarratedCaptionAlignmentService.warm()
        }
    }

    private func updateVoiceEngineInstallationStatusFromError(_ error: Error, engine: NarrationEngine, project: NarratedImageProject) {
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

    private func safeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "narrated-images" : cleaned
    }
}
