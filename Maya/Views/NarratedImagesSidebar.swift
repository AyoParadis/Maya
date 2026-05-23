import SwiftUI

struct NarratedImagesSidebar: View {
    @Bindable var workspace: NarratedImagesWorkspace
    let onNewProject: () -> Void
    let onCloseProject: () -> Void
    let onImportImages: () -> Void
    let onOpenInspector: () -> Void
    let onGenerateVoiceover: () -> Void
    let onGenerateCaptions: () -> Void
    let onRegenerateVoiceAndCaptions: () -> Void
    let onGenerateAllScenes: () -> Void
    let onAlignCaptionsToVoice: () -> Void
    let onExportVideo: () -> Void
    let isInspectorVisible: Bool
    let voiceStorageSummary: NarrationStorageSummary?
    let isDeletingVoiceAssets: Bool
    let onPreviewVoice: () -> Void
    let onInstallVoiceEngine: () -> Void
    let onInstallCaptionAligner: () -> Void
    let onDeleteVoiceAssets: () -> Void

    @State private var isProjectsExpanded = true
    @State private var isVoiceExpanded = true
    @State private var isSceneExpanded = true
    @State private var isGenerationExpanded = true
    @State private var isCanvasExpanded = true
    @State private var isInspectorExpanded = true
    @State private var isExportExpanded = true

    var body: some View {
        StudioSidebarScaffold {
            StudioSidebarHeader(title: "Narrated Images")
            SidebarDisclosureSection(title: "Projects", isExpanded: $isProjectsExpanded) {
                projectList
            }
            SidebarDisclosureSection(title: "AI Voice", isExpanded: $isVoiceExpanded) {
                voiceSection
            }
            SidebarDisclosureSection(title: "Scene Script", isExpanded: $isSceneExpanded) {
                sceneScriptSection
            }
            if workspace.selectedProject.selectedScene != nil {
                SidebarDisclosureSection(title: "Generation", isExpanded: $isGenerationExpanded) {
                    generationSection
                }
            }
            SidebarDisclosureSection(title: "Canvas", isExpanded: $isCanvasExpanded) {
                canvasSection
            }
            if !isInspectorVisible {
                SidebarDisclosureSection(title: "Inspector", isExpanded: $isInspectorExpanded) {
                    Button(action: onOpenInspector) {
                        Label("Open inspector", systemImage: "sidebar.trailing")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
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
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(workspace.projects) { project in
                NarratedProjectChip(
                    title: project.title,
                    count: project.scenes.count,
                    isSelected: workspace.selectedProjectID == project.id,
                    onNewProject: onNewProject,
                    onCloseProject: onCloseProject
                ) {
                    workspace.selectedProjectID = project.id
                }
            }
        }
    }

    private var voiceSection: some View {
        StudioVoiceoverControls(
            engine: $workspace.selectedProject.narrationEngine,
            voice: $workspace.selectedProject.voice,
            isPreviewing: workspace.selectedProject.isPreviewingVoice,
            isGenerating: workspace.selectedProject.isGeneratingNarration,
            isInstalling: workspace.selectedProject.isInstallingVoiceEngine,
            isCaching: workspace.selectedProject.isCachingVoicePreviews,
            isDeletingAssets: isDeletingVoiceAssets,
            hasNarration: workspace.selectedProject.scenes.contains { $0.narrationAudioURL != nil },
            installationStatus: workspace.selectedProject.narrationEngineInstallationStatus,
            storageSummary: voiceStorageSummary,
            status: narrationStatusMessage,
            errorMessage: narrationErrorMessage,
            onPreview: onPreviewVoice,
            onRemove: removeSelectedSceneVoiceover,
            onInstall: onInstallVoiceEngine,
            onDeleteAssets: onDeleteVoiceAssets
        )
    }

    private var sceneScriptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Project name", text: $workspace.selectedProject.title)
                .textFieldStyle(.roundedBorder)
            Button(action: onImportImages) {
                Label("Import images", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if let scene = workspace.selectedProject.selectedScene {
                @Bindable var scene = scene
                Text(scene.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                StudioVoiceoverScriptEditor(
                    title: "Spoken script",
                    placeholder: "Write what the AI voice should say for this image...",
                    text: $scene.script
                )
            } else {
                Text("Import an image to write a script.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var generationSection: some View {
        if let scene = workspace.selectedProject.selectedScene {
            VStack(alignment: .leading, spacing: 10) {
                generationPrimaryActions(scene: scene)
                Divider().opacity(0.45)
                generationSecondaryActions(scene: scene)
                captionAlignmentStatus(scene: scene)
            }
        }
    }

    private func generationPrimaryActions(scene: NarratedImageScene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onRegenerateVoiceAndCaptions) {
                Label(scene.narrationStatus == .generating ? "Generating selected scene..." : "Selected scene", systemImage: "wand.and.waves")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(scene.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || workspace.selectedProject.isGeneratingNarration)
            .help("Generate voice and voice-aligned captions for the selected image")

            Button(action: onGenerateAllScenes) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                    Text(workspace.selectedProject.isGeneratingNarration ? "Generating project..." : "All scripted scenes")
                    Spacer()
                    Text("\(scriptedSceneCount)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(workspace.selectedProject.isGeneratingNarration || scriptedSceneCount == 0)
            .help("Generate voice and aligned captions for every scene with a script")
        }
    }

    private func generationSecondaryActions(scene: NarratedImageScene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onGenerateVoiceover) {
                    Label("Voice", systemImage: "waveform.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(scene.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || workspace.selectedProject.isGeneratingNarration)

                Button(action: onGenerateCaptions) {
                    Label("Captions", systemImage: "captions.bubble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(scene.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if scene.narrationAudioURL != nil {
                Button(action: onAlignCaptionsToVoice) {
                    Label(scene.captionAlignmentStatus == .aligning ? "Aligning..." : "Align existing captions to voice", systemImage: "text.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(workspace.selectedProject.isGeneratingNarration || workspace.selectedProject.isInstallingCaptionAligner)
            }
        }
    }

    private var scriptedSceneCount: Int {
        workspace.selectedProject.scenes.filter { !$0.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Format")
                .font(.caption.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach([CanvasAspectRatio.vertical9x16, .vertical4x5, .square, .landscape16x9]) { aspect in
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
            NarratedSidebarFieldLabel("Video quality")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(CarouselExportQuality.allCases) { quality in
                    NarratedExportQualityTile(
                        quality: quality,
                        isSelected: workspace.selectedProject.exportQuality == quality
                    ) {
                        workspace.selectedProject.exportQuality = quality
                    }
                }
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if workspace.isExporting {
                StudioActionCardButton(
                    title: workspace.exportStatus.isEmpty ? "Preparing export" : workspace.exportStatus,
                    subtitle: "\(Int((workspace.exportProgress * 100).rounded()))% complete",
                    icon: "square.and.arrow.up",
                    isEnabled: false,
                    isWorking: true,
                    progress: workspace.exportProgress,
                    workingLabel: workspace.exportStatus.isEmpty ? "Exporting" : workspace.exportStatus,
                    accent: Color(hex: "#7C6DFF") ?? .accentColor,
                    accentDark: Color(hex: "#377DFF") ?? .blue,
                    disabledHelp: "Export in progress",
                    enabledHelp: "Exporting",
                    action: {}
                )
                Button(role: .cancel) {
                    workspace.cancelExport()
                } label: {
                    Label("Cancel export", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                NarratedExportOptionButton(
                    title: "Video",
                    subtitle: "MP4 with voice and captions",
                    icon: "film",
                    detail: exportDimensions,
                    action: onExportVideo
                )
                .disabled(workspace.selectedProject.scenes.isEmpty)
            }
        }
    }

    private var exportDimensions: String {
        let size = workspace.selectedProject.canvasAspect.renderSize(for: workspace.selectedProject.exportQuality)
        return "\(Int(size.width))×\(Int(size.height))"
    }

    private var narrationStatusMessage: (text: String, icon: String, tint: Color)? {
        let project = workspace.selectedProject
        if project.isInstallingVoiceEngine {
            return (project.narrationMessage ?? "Setting up \(project.narrationEngine.displayName)...", "arrow.down.circle", .secondary)
        }
        if project.isCachingVoicePreviews {
            return (project.narrationMessage ?? "Preparing previews...", "bolt.circle", .secondary)
        }
        if project.isGeneratingNarration {
            return (project.captionAlignmentMessage ?? "Generating scene voiceover...", "waveform", .secondary)
        }
        if project.isPreviewingVoice {
            return ("Playing preview...", "play.circle", .secondary)
        }
        if let message = project.narrationMessage, !isErrorMessage(message) {
            return (message, "info.circle", .secondary)
        }
        return nil
    }

    private func captionAlignmentStatus(scene: NarratedImageScene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: captionAlignmentIcon(for: scene))
                    .foregroundStyle(captionAlignmentTint(for: scene))
                Text(scene.captionAlignmentStatus.label)
                    .font(.caption.weight(.semibold))
                Spacer()
                if workspace.selectedProject.captionAlignerInstallationStatus != .installed {
                    Button(action: onInstallCaptionAligner) {
                        Text(workspace.selectedProject.isInstallingCaptionAligner ? "Installing..." : "Install aligner")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                    .disabled(workspace.selectedProject.isInstallingCaptionAligner || workspace.selectedProject.isGeneratingNarration)
                }
            }
            if let message = workspace.selectedProject.captionAlignmentMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = scene.captionAlignmentError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(9)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func captionAlignmentIcon(for scene: NarratedImageScene) -> String {
        switch scene.captionAlignmentStatus {
        case .idle: "captions.bubble"
        case .aligning: "waveform.path.ecg"
        case .aligned: "checkmark.seal.fill"
        case .estimated: "clock.badge.exclamationmark"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func captionAlignmentTint(for scene: NarratedImageScene) -> Color {
        switch scene.captionAlignmentStatus {
        case .aligned: .green
        case .failed: .red
        case .aligning: .blue
        case .estimated: .orange
        case .idle: .secondary
        }
    }

    private var narrationErrorMessage: String? {
        guard let message = workspace.selectedProject.narrationMessage, isErrorMessage(message) else { return nil }
        return message
    }

    private func removeSelectedSceneVoiceover() {
        guard let scene = workspace.selectedProject.selectedScene else { return }
        NarrationService.cleanupGeneratedNarration(at: scene.narrationAudioURL)
        scene.narrationAudioURL = nil
        scene.narrationAudioDuration = nil
        scene.narrationStatus = .idle
    }

    private func isErrorMessage(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("error")
            || message.localizedCaseInsensitiveContains("failed")
            || message.localizedCaseInsensitiveContains("not installed")
            || message.localizedCaseInsensitiveContains("no module named")
            || message.localizedCaseInsensitiveContains("externally-managed")
    }
}

private struct NarratedExportOptionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#377DFF") ?? .blue)
                    .frame(width: 34, height: 34)
                    .background(Color.gray.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(detail)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

private struct NarratedExportQualityTile: View {
    let quality: CarouselExportQuality
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(quality.label)
                    .font(.caption.weight(.semibold))
                Text(quality.detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AnyShapeStyle(AppChrome.accentGradient) : AnyShapeStyle(Color.gray.opacity(0.10)))
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

private struct NarratedSidebarFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct NarratedProjectChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let onNewProject: () -> Void
    let onCloseProject: () -> Void
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.stack")
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            if isSelected {
                Button(action: onNewProject) {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                Button(role: .destructive, action: onCloseProject) {
                    Image(systemName: "xmark").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
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
