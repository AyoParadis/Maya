import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsSidebar: View {
    @Bindable var project: Project
    let onExport: () -> Void
    let onOpenAIDirector: () -> Void
    let onCreateAIVideo: () -> Void
    let onExportAIBundle: () -> Void
    let onImportAIPlan: () -> Void
    let aiDirectorMessage: AIDirectorMessage?
    let isRunningAIDirector: Bool
    let aiDirectorStatus: AIDirectorStatus
    let isAIDirectorPanelVisible: Bool

    @State private var showAdvancedAIDirector = false
    @State private var voicePreviewSound: NSSound?
    @State private var voicePreviewTask: Task<Void, Never>?
    @State private var voicePreviewToken: UUID?
    @State private var voiceStorageSummary: NarrationStorageSummary?
    @State private var isDeletingVoiceAssets = false
    @State private var isConfirmingVoiceAssetDeletion = false
    @State private var isVoiceoverExpanded = true
    @State private var isRecordingExpanded = true
    @State private var isAIDirectorExpanded = true
    @State private var isCanvasExpanded = true
    @State private var isDeviceExpanded = true
    @State private var isTransformExpanded = true
    @State private var isBackgroundExpanded = true
    @State private var isShadowExpanded = true
    @State private var isExportExpanded = true

    var body: some View {
        StudioSidebarScaffold {
            StudioSidebarHeader(title: "Video")
            SidebarDisclosureSection(title: "AI Voiceover", isExpanded: $isVoiceoverExpanded) {
                narrationSection
            }
            SidebarDisclosureSection(title: "Recording", isExpanded: $isRecordingExpanded) {
                videoSection
            }
            if project.videoURL != nil {
                SidebarDisclosureSection(title: "AI Director", isExpanded: $isAIDirectorExpanded) {
                    aiDirectorSection
                }
            }
            SidebarDisclosureSection(title: "Canvas", isExpanded: $isCanvasExpanded) {
                canvasSection
            }
            SidebarDisclosureSection(title: "Device", isExpanded: $isDeviceExpanded) {
                deviceSection
            }
            SidebarDisclosureSection(title: "Size & Position", isExpanded: $isTransformExpanded) {
                transformSection
            }
            SidebarDisclosureSection(title: "Background", isExpanded: $isBackgroundExpanded) {
                BackgroundPicker(project: project)
            }
            SidebarDisclosureSection(title: "Shadow", isExpanded: $isShadowExpanded) {
                shadowSection
            }
            SidebarDisclosureSection(title: "Export", isExpanded: $isExportExpanded) {
                exportSection
            }
            if let error = project.lastExportError {
                CopyableMessageBox(text: error, isError: true)
            }
        }
        .task {
            await refreshVoiceEngineInstallationStatus()
            await refreshVoiceStorageSummary()
            if project.narrationEngineInstallationStatus == .installed {
                await NarrationService.warmPreviewsIfNeeded(for: project.narrationEngine)
                await refreshVoiceStorageSummary()
            }
        }
        .onChange(of: project.narrationEngine) { _, _ in
            Task {
                await refreshVoiceEngineInstallationStatus()
                await refreshVoiceStorageSummary()
            }
        }
        .confirmationDialog(
            "Delete \(project.narrationEngine.displayName) voice assets?",
            isPresented: $isConfirmingVoiceAssetDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete \(project.narrationEngine.displayName) assets", role: .destructive) {
                deleteSelectedVoiceEngineAssets()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected engine's installed files, downloaded voice models, and cached previews. Generated project voiceovers are kept.")
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if project.deviceModel.kind == .physical || project.deviceModel.kind == .drawn {
                Text(project.deviceColor.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Model picker — wraps to multiple rows so 5 entries (Off, Generic
            // and the three Pro models) all fit comfortably in the sidebar.
            let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(DeviceModel.all) { model in
                    DeviceModelChip(
                        label: model.shortName,
                        symbol: model.kind == .physical ? nil : model.symbol,
                        isSelected: project.deviceModelID == model.id
                    ) {
                        project.selectDeviceModel(model)
                    }
                }
            }

            // Color swatches only apply to physical models.
            if project.deviceModel.kind == .physical || project.deviceModel.kind == .drawn {
                HStack(spacing: 10) {
                    ForEach(project.deviceModel.colors) { color in
                        DeviceColorSwatch(
                            color: color,
                            isSelected: project.deviceColorID == color.id
                        ) {
                            project.selectDeviceColor(color)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                // Corner radius is user-controlled when there's no fixed device
                // hardware dictating its screen geometry.
                bareControlsSection
            }
        }
    }

    private var bareControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRow(
                title: "Corner radius",
                value: $project.bareCornerRadius,
                range: 0...0.5,
                display: "\(Int(project.bareCornerRadius * 200))%"
            )

            if project.deviceModel.kind == .generic {
                sliderRow(
                    title: "Bezel width",
                    value: $project.bareBezelWidth,
                    range: 0...0.1,
                    display: "\(Int(project.bareBezelWidth * 1000))"
                )

                bezelColorRow
            }
        }
    }

    // MARK: - Shadow

    private var shadowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enabled", isOn: $project.shadow.enabled)
            .toggleStyle(.switch)

            if project.shadow.enabled {
                HStack(spacing: 10) {
                    Text("Color").font(.caption.weight(.medium))
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: project.shadow.colorHex) ?? .black },
                        set: { project.shadow.colorHex = $0.hexString }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    Text(project.shadow.colorHex)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                sliderRow(
                    title: "Blur",
                    value: $project.shadow.radius,
                    range: PhoneShadow.radiusRange,
                    display: "\(Int(project.shadow.radius))pt"
                )

                sliderRow(
                    title: "Offset Y",
                    value: $project.shadow.offsetY,
                    range: PhoneShadow.offsetYRange,
                    display: "\(Int(project.shadow.offsetY))pt"
                )

                sliderRow(
                    title: "Offset X",
                    value: $project.shadow.offsetX,
                    range: PhoneShadow.offsetXRange,
                    display: "\(Int(project.shadow.offsetX))pt"
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Opacity").font(.caption.weight(.medium))
                        Spacer()
                        Text("\(Int(project.shadow.opacity * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $project.shadow.opacity, in: PhoneShadow.opacityRange)
                }
            }
        }
    }

    private func sliderRow(title: String,
                           value: Binding<CGFloat>,
                           range: ClosedRange<CGFloat>,
                           display: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private var bezelColorRow: some View {
        let binding = Binding<Color>(
            get: { Color(hex: project.bareBezelHex) ?? .black },
            set: { newColor in
                project.bareBezelHex = newColor.hexString
            }
        )
        return HStack(spacing: 10) {
            Text("Bezel color").font(.caption.weight(.medium))
            ColorPicker("", selection: binding, supportsOpacity: false)
                .labelsHidden()
            Text(project.bareBezelHex)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let columns = [GridItem(.adaptive(minimum: 56), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CanvasAspectRatio.allCases) { aspect in
                    AspectRatioChip(
                        aspect: aspect,
                        isSelected: project.canvasAspect == aspect
                    ) {
                        project.canvasAspect = aspect
                    }
                }
            }

            Text(project.canvasAspect.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if project.videoURL != nil {
                Label(project.displayName ?? "Loaded video", systemImage: "film")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.callout)
                Button {
                    openVideoPicker()
                } label: {
                    Label("Replace recording", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    openVideoPicker()
                } label: {
                    Label("Open screen recording…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
    }

    private var transformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.secondary)
                Slider(value: $project.scale, in: 0.3...1.6)
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.secondary)
            }
            Text(String(format: "Scale: %.0f%%", project.scale * 100))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                project.offset = .zero
                project.scale = 0.85
            } label: {
                Label("Reset position", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioActionCardButton(
                title: exportButtonTitle,
                subtitle: exportSubtitle,
                icon: exportButtonIcon,
                isEnabled: project.videoURL != nil && !project.isExporting,
                isWorking: project.isExporting,
                progress: project.exportProgress,
                disabledHelp: "Load a video to enable export",
                enabledHelp: "Render and save the video",
                action: onExport
            )
        }
    }

    private var narrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioVoiceoverControls(
                engine: $project.narrationEngine,
                voice: $project.piperVoice,
                isPreviewing: project.isPreviewingVoice,
                isGenerating: project.isGeneratingNarration,
                isInstalling: project.isInstallingPiper,
                isCaching: project.isCachingVoicePreviews,
                isDeletingAssets: isDeletingVoiceAssets,
                hasNarration: project.narrationAudioURL != nil,
                installationStatus: project.narrationEngineInstallationStatus,
                storageSummary: voiceStorageSummary,
                status: narrationStatusMessage,
                errorMessage: narrationErrorMessage,
                onPreview: previewVoice,
                onRemove: removeNarration,
                onInstall: installSelectedVoiceEngine,
                onDeleteAssets: { isConfirmingVoiceAssetDeletion = true }
            )

            StudioVoiceoverScriptEditor(
                title: "Script",
                placeholder: "Write or paste the voiceover script...",
                text: $project.narrationScript
            )

            Button {
                generateNarration()
            } label: {
                Label(project.isGeneratingNarration ? "Generating voiceover..." : "Generate voiceover", systemImage: "waveform")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(project.isGeneratingNarration || project.isInstallingPiper || project.isCachingVoicePreviews || project.narrationScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var narrationStatusMessage: (text: String, icon: String, tint: Color)? {
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
            return ("Generating voiceover...", "waveform", .secondary)
        }
        if project.isPreviewingVoice {
            return ("Playing preview...", "play.circle", .secondary)
        }
        if project.narrationAudioURL != nil {
            return ("Voiceover ready", "checkmark.circle.fill", .green)
        }
        if let message = project.narrationMessage, !isErrorMessage(message) {
            return (message, "info.circle", .secondary)
        }
        return nil
    }

    private var narrationErrorMessage: String? {
        guard let message = project.narrationMessage, isErrorMessage(message) else { return nil }
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

    private var aiDirectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            aiStatusBadge

            Label(aiDirectorStatus.isWorking ? aiDirectorStatus.workingTitle : "Local Codex", systemImage: aiDirectorStatus.isWorking ? "wand.and.stars" : "terminal")
                .font(.caption.weight(.medium))
                .foregroundStyle(aiDirectorStatus == .failed ? .red : .secondary)

            if !isAIDirectorPanelVisible {
                Button {
                    onCreateAIVideo()
                } label: {
                    Label(aiDirectorStatus.isWorking ? "Creating video..." : "Create video", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(isRunningAIDirector)

                Button {
                    onOpenAIDirector()
                } label: {
                    Label("Open director", systemImage: "sidebar.trailing")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isRunningAIDirector)
            }

            DisclosureGroup("Advanced", isExpanded: $showAdvancedAIDirector) {
                HStack(spacing: 8) {
                    Button {
                        onExportAIBundle()
                    } label: {
                        Label("Export bundle", systemImage: "shippingbox.and.arrow.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isRunningAIDirector)

                    Button {
                        onImportAIPlan()
                    } label: {
                        Label("Import plan", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isRunningAIDirector)
                }
                .padding(.top, 6)
            }
            .font(.caption.weight(.medium))

            if let aiDirectorMessage, !isAIDirectorPanelVisible {
                if aiDirectorMessage.kind == .failure {
                    CopyableMessageBox(text: aiDirectorMessage.text, isError: true)
                } else {
                    CompactStatusMessage(text: aiDirectorMessage.text, icon: "checkmark.circle.fill", tint: .green)
                }
            }
        }
    }

    private func removeNarration() {
        NarrationService.cleanupGeneratedNarration(at: project.narrationAudioURL)
        project.narrationAudioURL = nil
        project.narrationDisplayName = nil
        project.narrationMessage = nil
    }

    private func generateNarration() {
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
                    project.narrationMessage = project.videoURL == nil
                        ? "Voiceover is ready. Load a recording to include it in export."
                        : "Voiceover will be included in export."
                    project.isGeneratingNarration = false
                }
                await NarrationService.warmPreviewsIfNeeded(for: request.engine)
                await refreshVoiceStorageSummary()
            } catch {
                await MainActor.run {
                    project.narrationMessage = error.localizedDescription
                    updateVoiceEngineInstallationStatusFromError(error, engine: request.engine)
                    project.isGeneratingNarration = false
                }
            }
        }
    }

    private func previewVoice() {
        guard !project.isGeneratingNarration,
              !project.isInstallingPiper,
              !project.isCachingVoicePreviews else { return }
        if project.isPreviewingVoice {
            stopVoicePreview(message: "Preview stopped.")
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
                    updateVoiceEngineInstallationStatusFromError(error, engine: request.engine)
                    project.isPreviewingVoice = false
                }
            }
        }
    }

    private func stopVoicePreview(message: String? = nil) {
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
                    updateVoiceEngineInstallationStatusFromError(error, engine: engine)
                    project.isInstallingPiper = false
                    project.isCachingVoicePreviews = false
                }
                await refreshVoiceStorageSummary()
            }
        }
    }

    private func refreshVoiceEngineInstallationStatus() async {
        let engine = project.narrationEngine
        let status = await NarrationService.installationStatus(for: engine)
        await MainActor.run {
            guard project.narrationEngine == engine else { return }
            project.narrationEngineInstallationStatus = status
        }
    }

    private func refreshVoiceStorageSummary() async {
        let summary = await NarrationService.storageSummary()
        await MainActor.run {
            voiceStorageSummary = summary
        }
    }

    private func deleteSelectedVoiceEngineAssets() {
        guard !isDeletingVoiceAssets,
              !project.isInstallingPiper,
              !project.isGeneratingNarration,
              !project.isCachingVoicePreviews else { return }
        isDeletingVoiceAssets = true
        let engine = project.narrationEngine
        project.narrationMessage = "Deleting \(engine.displayName) voice assets..."

        Task {
            do {
                try await NarrationService.deleteAssets(for: engine)
                let summary = await NarrationService.storageSummary()
                await MainActor.run {
                    if project.narrationEngine == engine {
                        project.narrationEngineInstallationStatus = .notInstalled
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

    private func updateVoiceEngineInstallationStatusFromError(_ error: Error, engine: NarrationEngine) {
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

    private var aiStatusBadge: some View {
        Text(aiDirectorStatus.label)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(aiDirectorStatus == .failed ? Color.red : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(aiDirectorStatus == .failed ? Color.red.opacity(0.10) : Color.gray.opacity(0.12))
            )
    }

    private var exportButtonTitle: String {
        project.background.isTransparent ? "Export transparent" : "Export video"
    }

    private var exportButtonIcon: String {
        project.background.isTransparent
            ? "square.and.arrow.down.on.square.fill"
            : "square.and.arrow.down.fill"
    }

    /// One-line subtitle shown under the export title. Pieces are joined with
    /// middle dots so it stays readable without breaking onto two rows.
    private var exportSubtitle: String {
        let size = project.canvasAspect.renderSize
        let dims = "\(Int(size.width))×\(Int(size.height))"
        let pieces: [String] = project.background.isTransparent
            ? [dims, "HEVC + α", "MOV"]
            : [dims, "H.264", "MP4"]
        return pieces.joined(separator: " · ")
    }

    private func openVideoPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
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
    }
}

private extension DeviceModel {
    /// Short label for the picker chip. Strips/abbreviates the product family
    /// so chips fit in the narrow row: "iPhone 15 Pro" → "15 Pro",
    /// "MacBook Pro 14" → "M Pro 14".
    var shortName: String {
        if displayName.hasPrefix("iPhone ") {
            return String(displayName.dropFirst("iPhone ".count))
        }
        if displayName.hasPrefix("MacBook ") {
            return "M " + displayName.dropFirst("MacBook ".count)
        }
        return displayName
    }
}

private struct DeviceModelChip: View {
    let label: String
    let symbol: String?
    let isSelected: Bool
    let action: () -> Void

    private var fillColor: Color {
        isSelected ? (Color(hex: "#6466FA") ?? .accentColor) : Color.gray.opacity(0.12)
    }

    private var strokeColor: Color {
        isSelected ? Color.white.opacity(0.35) : Color.gray.opacity(0.18)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 7).fill(fillColor))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(strokeColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct DeviceColorSwatch: View {
    let color: DeviceColor
    let isSelected: Bool
    let action: () -> Void

    private var swatch: Color {
        Color(hex: color.swatchHex) ?? .gray
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Selection ring sits behind the swatch with a small gap so the
                // tint reads even on white/silver finishes.
                Circle()
                    .stroke(isSelected
                            ? (Color(hex: "#6466FA") ?? .accentColor)
                            : Color.clear,
                            lineWidth: 2)
                    .frame(width: 30, height: 30)

                Circle()
                    .fill(swatch)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.name)
    }
}
