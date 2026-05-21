import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct CarouselStudioView: View {
    @State private var workspace = CarouselWorkspace()
    @State private var exporter = CarouselExportService()
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var isSidebarVisible = true
    @State private var isInspectorVisible = true

    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                CarouselSidebar(
                    workspace: workspace,
                    onNewCarousel: workspace.addProject,
                    onCloseCarousel: workspace.closeSelectedProject,
                    onImportImages: openImagePicker,
                    onCreateOutline: createOutline,
                    onGenerateSlide: generateActiveSlide,
                    onRegenerateSlide: regenerateSelectedSlide,
                    onApproveSlide: approveSelectedSlide,
                    onOpenInspector: { isInspectorVisible = true },
                    onExportVideo: exportVideo,
                    onExportImages: exportImages,
                    onExportBundle: exportBundle,
                    isInspectorVisible: isInspectorVisible
                )
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 430)
                .transition(.move(edge: .leading).combined(with: .opacity))

                Divider()
            }

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

                CarouselInspector(project: workspace.selectedProject) {
                    isInspectorVisible = false
                }
                .frame(width: 360)
                .background(Color(nsColor: .windowBackgroundColor))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSidebarVisible)
        .animation(.easeInOut(duration: 0.2), value: isInspectorVisible)
        .navigationTitle(AppChrome.title)
        .navigationSubtitle(AppChrome.versionLabel)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                }
                .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
            }
        }
        .onReceive(timer) { _ in
            let project = workspace.selectedProject
            guard isPlaying, project.totalDuration > 0 else { return }
            currentTime += 1.0 / 30.0
            if currentTime >= project.totalDuration {
                currentTime = 0
            }
            project.selectCard(at: currentTime)
        }
        .onChange(of: workspace.selectedProject.selectedCardID) { _, _ in
            guard let id = workspace.selectedProject.selectedCardID else { return }
            currentTime = workspace.selectedProject.startTime(for: id)
        }
        .onChange(of: workspace.selectedProjectID) { _, _ in
            currentTime = 0
        }
    }

    private func toggleSidebar() {
        isSidebarVisible.toggle()
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

    private func createOutline() {
        let project = workspace.selectedProject
        guard !project.brief.sourceContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !project.cards.isEmpty else {
            workspace.lastError = "Add source content or import images before creating an outline."
            return
        }

        Task {
            workspace.isGeneratingPlan = true
            project.pipelineState = .outlining
            workspace.lastError = nil
            do {
                let result = try await CarouselAIDirectorBridge.createOutline(for: project)
                project.applyOutline(result.plan)
                workspace.runDirectory = result.runDirectory
                workspace.lastMessage = result.usedFallback
                    ? "Created local fallback carousel outline."
                    : "Created Carousel Director outline."
            } catch {
                let plan = CarouselAIDirectorBridge.fallbackPlan(for: project, warning: error.localizedDescription)
                project.applyOutline(plan)
                workspace.lastMessage = "Created local fallback carousel outline."
            }
            workspace.isGeneratingPlan = false
        }
    }

    private func generateActiveSlide() {
        let project = workspace.selectedProject
        guard let card = project.activePipelineCard else {
            workspace.lastError = "Create an outline before drafting slides."
            return
        }
        draft(cardID: card.id, regenerate: false)
    }

    private func regenerateSelectedSlide() {
        guard let card = workspace.selectedProject.selectedCard else {
            workspace.lastError = "Select a slide to regenerate."
            return
        }
        draft(cardID: card.id, regenerate: true)
    }

    private func draft(cardID: UUID, regenerate: Bool) {
        let project = workspace.selectedProject
        Task {
            workspace.isGeneratingPlan = true
            project.pipelineState = .draftingSlide
            workspace.lastError = nil
            do {
                let result = try await CarouselAIDirectorBridge.draftSlide(for: project, cardID: cardID)
                guard let cardPlan = result.plan.cards.first(where: { $0.id == cardID }) else {
                    throw CarouselAIDirectorError.invalidCardIDs
                }
                project.applySlideDraft(cardPlan)
                workspace.runDirectory = result.runDirectory
                workspace.lastMessage = result.usedFallback
                    ? "Drafted slide with local fallback."
                    : "\(regenerate ? "Regenerated" : "Drafted") slide with Carousel Director."
            } catch {
                let plan = CarouselAIDirectorBridge.fallbackDraftPlan(for: project, cardID: cardID, warning: error.localizedDescription)
                if let cardPlan = plan.cards.first(where: { $0.id == cardID }) {
                    project.applySlideDraft(cardPlan)
                }
                workspace.lastMessage = "Drafted slide with local fallback."
            }
            workspace.isGeneratingPlan = false
        }
    }

    private func approveSelectedSlide() {
        let project = workspace.selectedProject
        project.approveSelectedSlide()
        if let id = project.selectedCardID {
            currentTime = project.startTime(for: id)
        }
        workspace.lastMessage = project.pipelineState == .complete ? "All carousel slides approved." : "Slide approved. Ready for the next draft."
        workspace.lastError = nil
    }

    private func exportVideo() {
        let project = workspace.selectedProject
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(safeName(project.title)).mp4"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            workspace.isExporting = true
            workspace.exportProgress = 0
            workspace.lastError = nil
            do {
                try await exporter.exportVideo(project: project, to: url) { progress in
                    Task { @MainActor in workspace.exportProgress = progress }
                }
                workspace.lastMessage = "Exported carousel video."
            } catch {
                workspace.lastError = error.localizedDescription
            }
            workspace.isExporting = false
        }
    }

    private func exportImages() {
        let project = workspace.selectedProject
        let panel = NSOpenPanel()
        panel.message = "Choose a folder for carousel still images."
        panel.prompt = "Export Images"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            workspace.isExporting = true
            workspace.lastError = nil
            do {
                let directory = url.appendingPathComponent("\(safeName(project.title))-images", isDirectory: true)
                _ = try exporter.exportImages(project: project, to: directory)
                workspace.lastMessage = "Exported carousel images."
            } catch {
                workspace.lastError = error.localizedDescription
            }
            workspace.isExporting = false
        }
    }

    private func exportBundle() {
        let project = workspace.selectedProject
        let panel = NSOpenPanel()
        panel.message = "Choose a folder for the carousel export bundle."
        panel.prompt = "Export Bundle"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            workspace.isExporting = true
            workspace.exportProgress = 0
            workspace.lastError = nil
            do {
                let directory = url.appendingPathComponent("\(safeName(project.title))-bundle", isDirectory: true)
                try await exporter.exportBundle(project: project, to: directory) { progress in
                    Task { @MainActor in workspace.exportProgress = progress }
                }
                workspace.lastMessage = "Exported carousel bundle."
            } catch {
                workspace.lastError = error.localizedDescription
            }
            workspace.isExporting = false
        }
    }

    private func safeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "carousel" : cleaned
    }
}
