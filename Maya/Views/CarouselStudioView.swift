import AppKit
import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct CarouselStudioView: View {
    @Binding var selectedMode: StudioMode
    @State private var workspace = CarouselWorkspace()
    @State private var exporter = CarouselExportService()
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var voiceoverPlayer: AVAudioPlayer?
    @State private var voiceoverCardID: UUID?
    @State private var isInspectorVisible = true

    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            CarouselSidebar(
                workspace: workspace,
                onNewCarousel: workspace.addProject,
                onCloseCarousel: workspace.closeSelectedProject,
                onImportImages: openImagePicker,
                onOpenInspector: { isInspectorVisible = true },
                onExportVideo: exportVideo,
                onExportImages: exportImages,
                onExportBundle: exportBundle,
                isInspectorVisible: isInspectorVisible
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 430)
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        CarouselCanvasView(
                            project: workspace.selectedProject,
                            currentTime: currentTime,
                            onImportImages: openImagePicker
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .dropDestination(for: URL.self) { urls, _ in
                            importImages(from: urls)
                            return true
                        }

                        if !workspace.selectedProject.cards.isEmpty {
                            CarouselTimelineView(
                                project: workspace.selectedProject,
                                currentTime: $currentTime,
                                isPlaying: $isPlaying
                            )
                        }
                    }
                    .background(Color(nsColor: .windowBackgroundColor))

                    if isInspectorVisible {
                        Divider()

                        CarouselInspector(
                            project: workspace.selectedProject,
                            onRegenerateVoiceover: regenerateVoiceover,
                            onRedetectText: redetectNarrationText,
                            onCleanScript: cleanNarrationScript
                        ) {
                            isInspectorVisible = false
                        }
                        .frame(width: 360)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isInspectorVisible)
                .navigationTitle(AppChrome.title)
                .navigationSubtitle(AppChrome.versionLabel)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        StudioModePicker(selectedMode: $selectedMode)
                    }
                }
                .onReceive(timer) { _ in
                    let project = workspace.selectedProject
                    guard isPlaying, project.totalDuration > 0 else { return }
                    currentTime += 1.0 / 30.0
                    if currentTime >= project.totalDuration {
                        currentTime = 0
                        stopVoiceoverPlayback()
                    }
                    project.selectCard(at: currentTime)
                    syncVoiceoverPlayback()
                }
                .onChange(of: isPlaying) { _, playing in
                    playing ? syncVoiceoverPlayback() : stopVoiceoverPlayback()
                }
                .onChange(of: currentTime) { _, _ in
                    guard isPlaying else { return }
                    syncVoiceoverPlayback()
                }
                .onChange(of: workspace.selectedProject.selectedCardID) { _, _ in
                    guard let id = workspace.selectedProject.selectedCardID else { return }
                    currentTime = workspace.selectedProject.startTime(for: id)
                    if isPlaying {
                        syncVoiceoverPlayback()
                    }
                }
                .onChange(of: workspace.selectedProjectID) { _, _ in
                    currentTime = 0
                    isPlaying = false
                    stopVoiceoverPlayback()
                }
            }
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
            let cards = try imageURLs.map { url in
                let adopted = try CarouselImageImporter.adoptIntoSandbox(url)
                return CarouselCard(
                    imageURL: adopted.sandboxURL,
                    displayName: adopted.displayName,
                    duration: workspace.selectedProject.defaultCardDuration
                )
            }
            workspace.selectedProject.addCards(cards)
            currentTime = workspace.selectedProject.startTime(for: cards.first?.id ?? workspace.selectedProject.selectedCardID ?? UUID())
            workspace.lastMessage = "Imported \(cards.count) image\(cards.count == 1 ? "" : "s")."
            workspace.lastError = nil
        } catch {
            workspace.lastError = "Could not import images: \(error.localizedDescription)"
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
            workspace.exportDetail = "\(project.exportQuality.label) video · \(url.lastPathComponent)"
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
                workspace.lastMessage = "Exported carousel video."
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

    private func exportImages() {
        let project = workspace.selectedProject
        let panel = NSOpenPanel()
        panel.message = "Choose a folder for carousel still images."
        panel.prompt = "Export Images"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let task = Task {
            workspace.isExporting = true
            workspace.exportProgress = 0
            workspace.exportStatus = "Exporting images"
            workspace.exportDetail = "Writing PNG slide set"
            workspace.exportDestinationName = "\(safeName(project.title))-images"
            workspace.lastError = nil
            do {
                let directory = url.appendingPathComponent("\(safeName(project.title))-images", isDirectory: true)
                _ = try exporter.exportImages(project: project, to: directory)
                workspace.exportProgress = 1
                workspace.lastMessage = "Exported carousel images."
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

    private func exportBundle() {
        let project = workspace.selectedProject
        let panel = NSOpenPanel()
        panel.message = "Choose a folder for the carousel export bundle."
        panel.prompt = "Export Bundle"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let task = Task {
            workspace.isExporting = true
            workspace.exportProgress = 0
            workspace.exportStatus = "Preparing export"
            workspace.exportDetail = "\(project.exportQuality.label) bundle · \(safeName(project.title))-bundle"
            workspace.exportDestinationName = "\(safeName(project.title))-bundle"
            workspace.lastError = nil
            do {
                let directory = url.appendingPathComponent("\(safeName(project.title))-bundle", isDirectory: true)
                try await exporter.exportBundle(project: project, to: directory) { progress in
                    Task { @MainActor in
                        workspace.exportStatus = progress.phase.title
                        workspace.exportDetail = progress.detail
                        workspace.exportProgress = progress.progress
                    }
                }
                workspace.lastMessage = "Exported carousel bundle."
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

    private func safeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "carousel" : cleaned
    }

    private func regenerateVoiceover(for card: CarouselCard) {
        let project = workspace.selectedProject
        guard !project.isGeneratingNarration,
              !project.isInstallingPiper,
              !project.isCachingVoicePreviews else { return }
        let engine = project.narrationEngine
        let voice = project.piperVoice
        card.narrationStatus = .detecting
        card.narrationError = nil
        project.narrationMessage = "Generating voiceover for \(card.displayName)..."

        Task {
            do {
                let source = await MainActor.run {
                    CarouselSlideNarrationService.Source(card: card)
                }
                await MainActor.run {
                    card.narrationStatus = .generating
                }
                let editedScript = await MainActor.run {
                    card.narrationScriptEdited ? card.narrationScript : nil
                }
                if let editedScript {
                    await MainActor.run {
                        card.narrationStatus = .generating
                    }
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
                            project.narrationMessage = "Generated voiceover for \(card.displayName)."
                        } else {
                            NarrationService.cleanupGeneratedNarration(at: card.narrationAudioURL)
                            card.narrationAudioURL = nil
                            card.narrationAudioDuration = nil
                            card.narrationStatus = .skipped
                            project.narrationMessage = "Skipped \(card.displayName): no script found."
                        }
                        project.validate()
                    }
                    return
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
                        project.narrationMessage = "Generated voiceover for \(card.displayName)."
                    } else {
                        NarrationService.cleanupGeneratedNarration(at: card.narrationAudioURL)
                        card.detectedNarrationText = ""
                        card.narrationScript = ""
                        card.narrationScriptEdited = false
                        card.narrationAudioURL = nil
                        card.narrationAudioDuration = nil
                        card.narrationStatus = .skipped
                        project.narrationMessage = "Skipped \(card.displayName): no text found."
                    }
                    project.validate()
                }
            } catch {
                await MainActor.run {
                    NarrationService.cleanupGeneratedNarration(at: card.narrationAudioURL)
                    card.narrationAudioURL = nil
                    card.narrationAudioDuration = nil
                    card.narrationStatus = .failed
                    card.narrationError = error.localizedDescription
                    project.narrationMessage = error.localizedDescription
                }
            }
        }
    }

    private func redetectNarrationText(for card: CarouselCard) {
        let project = workspace.selectedProject
        guard !project.isGeneratingNarration,
              !project.isInstallingPiper,
              !project.isCachingVoicePreviews else { return }

        card.narrationStatus = .detecting
        card.narrationError = nil
        project.narrationMessage = "Detecting text for \(card.displayName)..."

        Task {
            do {
                let source = await MainActor.run {
                    CarouselSlideNarrationService.Source(card: card)
                }
                let detectedText = try await CarouselSlideNarrationService.redetectImageText(for: source)
                let script = CarouselSlideNarrationService.cleanedSpokenScript(from: detectedText)
                await MainActor.run {
                    card.detectedNarrationText = detectedText
                    if !card.narrationScriptEdited || card.narrationScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        card.narrationScript = script
                        card.narrationScriptEdited = false
                    }
                    card.narrationStatus = card.narrationAudioURL == nil ? .idle : .generated
                    project.narrationMessage = detectedText.isEmpty ? "No readable text found." : "Text detected."
                    project.validate()
                }
            } catch {
                await MainActor.run {
                    card.narrationStatus = .failed
                    card.narrationError = error.localizedDescription
                    project.narrationMessage = error.localizedDescription
                }
            }
        }
    }

    private func cleanNarrationScript(for card: CarouselCard) {
        let project = workspace.selectedProject
        guard !project.isCleaningNarrationText,
              !project.isGeneratingNarration,
              !project.isInstallingPiper,
              !project.isCachingVoicePreviews else { return }

        project.isCleaningNarrationText = true
        card.narrationError = nil
        project.narrationMessage = "Cleaning script with Codex..."

        Task {
            do {
                let source = await MainActor.run {
                    (
                        script: card.narrationScript,
                        detectedText: card.detectedNarrationText,
                        displayName: card.displayName
                    )
                }
                let result = try await CarouselNarrationCleanupService.clean(
                    script: source.script,
                    detectedText: source.detectedText,
                    slideName: source.displayName
                )
                await MainActor.run {
                    card.narrationScript = result.cleanedScript
                    card.narrationScriptEdited = true
                    project.narrationMessage = "Script cleaned. Regenerating audio..."
                    project.isCleaningNarrationText = false
                }
                await MainActor.run {
                    regenerateVoiceover(for: card)
                }
            } catch {
                await MainActor.run {
                    card.narrationError = error.localizedDescription
                    project.narrationMessage = error.localizedDescription
                    project.isCleaningNarrationText = false
                }
            }
        }
    }

    private func syncVoiceoverPlayback() {
        let project = workspace.selectedProject
        guard isPlaying,
              let sample = project.timelineSample(at: currentTime),
              let audioURL = sample.card.narrationAudioURL else {
            stopVoiceoverPlayback()
            return
        }

        let maxTime = sample.card.narrationAudioDuration ?? sample.localTime
        let targetTime = max(0, min(sample.localTime, maxTime))

        if voiceoverCardID == sample.card.id, let player = voiceoverPlayer {
            if abs(player.currentTime - targetTime) > 0.25 {
                player.currentTime = targetTime
            }
            if !player.isPlaying {
                player.play()
            }
            return
        }

        stopVoiceoverPlayback()
        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.currentTime = targetTime
            player.prepareToPlay()
            player.play()
            voiceoverPlayer = player
            voiceoverCardID = sample.card.id
        } catch {
            project.narrationMessage = error.localizedDescription
        }
    }

    private func stopVoiceoverPlayback() {
        voiceoverPlayer?.stop()
        voiceoverPlayer = nil
        voiceoverCardID = nil
    }
}
