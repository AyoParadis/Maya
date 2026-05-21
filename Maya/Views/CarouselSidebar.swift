import SwiftUI

struct CarouselSidebar: View {
    @Bindable var workspace: CarouselWorkspace
    let onNewCarousel: () -> Void
    let onCloseCarousel: () -> Void
    let onImportImages: () -> Void
    let onCreateOutline: () -> Void
    let onGenerateSlide: () -> Void
    let onRegenerateSlide: () -> Void
    let onApproveSlide: () -> Void
    let onOpenInspector: () -> Void
    let onExportVideo: () -> Void
    let onExportImages: () -> Void
    let onExportBundle: () -> Void
    let isInspectorVisible: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StudioSidebarHeader(title: "Carousel")
                Divider()
                carouselList
                Divider()
                importSection
                Divider()
                formatSection
                Divider()
                pipelineSection
                if !isInspectorVisible {
                    Divider()
                    inspectorSection
                }
                Divider()
                exportSection
                if let message = workspace.lastMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = workspace.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.visible)
        .frame(minWidth: 320, idealWidth: 360)
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
            HStack(alignment: .firstTextBaseline) {
                Text("Projects").font(.headline)
                Spacer()
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
            ForEach(workspace.projects) { project in
                CarouselProjectChip(
                    title: project.title,
                    count: project.cards.count,
                    isSelected: workspace.selectedProjectID == project.id
                ) {
                    workspace.selectedProjectID = project.id
                }
            }
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Brief")
                .font(.headline)
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
            Text("Canvas").font(.headline)
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

            Text("Template")
                .font(.headline)
                .padding(.top, 2)

            Picker("Formula", selection: Binding(
                get: { workspace.selectedProject.formula },
                set: { workspace.selectedProject.formula = $0 }
            )) {
                ForEach(CarouselFormula.allCases) { formula in
                    Text(formula.label).tag(formula)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Motion").font(.headline)
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

    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pipeline").font(.headline)
            if let active = workspace.selectedProject.activePipelineCard {
                Label("\(active.status.label): \(active.role.isEmpty ? active.displayName : active.role)", systemImage: active.status.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Create an outline to start drafting slides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            StudioActionCardButton(
                title: workspace.isGeneratingPlan ? "Creating..." : "Create Outline",
                subtitle: "Local Codex structure, roles, and visual prompts",
                icon: "sparkles",
                isEnabled: !workspace.isGeneratingPlan,
                isWorking: workspace.isGeneratingPlan,
                showsProgress: false,
                workingLabel: "Generating",
                disabledHelp: "Carousel Director is already generating",
                enabledHelp: "Create a local Codex carousel outline",
                action: onCreateOutline
            )
            HStack {
                StudioSmallActionButton(
                    title: "Draft",
                    icon: "pencil.and.scribble",
                    isEnabled: !workspace.isGeneratingPlan && workspace.selectedProject.activePipelineCard != nil,
                    action: onGenerateSlide
                )
                StudioSmallActionButton(
                    title: "Approve",
                    icon: "checkmark.circle",
                    isEnabled: workspace.selectedProject.selectedCard?.status == .drafted,
                    action: onApproveSlide
                )
            }
            StudioSmallActionButton(
                title: "Regenerate selected slide",
                icon: "arrow.clockwise",
                isEnabled: !workspace.isGeneratingPlan && workspace.selectedProject.selectedCard != nil,
                action: onRegenerateSlide
            )
            if !workspace.selectedProject.cards.isEmpty {
                Text("\(workspace.selectedProject.approvedCards.count) of \(workspace.selectedProject.cards.count) slides approved")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export").font(.headline)
            StudioActionCardButton(
                title: workspace.isExporting ? "Exporting..." : "Export Bundle",
                subtitle: exportSubtitle,
                icon: "folder.badge.gearshape",
                isEnabled: !workspace.isExporting,
                isWorking: workspace.isExporting,
                progress: workspace.exportProgress,
                accent: Color(hex: "#7C6DFF") ?? .accentColor,
                accentDark: Color(hex: "#377DFF") ?? .blue,
                disabledHelp: "Wait for the current export to finish",
                enabledHelp: "Export the complete carousel bundle",
                action: onExportBundle
            )
            HStack {
                StudioSmallActionButton(title: "Video", icon: "film", isEnabled: !workspace.isExporting, action: onExportVideo)
                StudioSmallActionButton(title: "Images", icon: "photo.stack", isEnabled: !workspace.isExporting, action: onExportImages)
            }
        }
    }

    private var exportSubtitle: String {
        let size = workspace.selectedProject.canvasAspect.renderSize
        let dims = "\(Int(size.width))×\(Int(size.height))"
        let approved = workspace.selectedProject.approvedCards.count
        let total = workspace.selectedProject.cards.count
        let suffix = total > 0 ? " · \(approved)/\(total) approved" : ""
        return "\(dims) · MP4 · PNG · copy\(suffix)"
    }
}

private struct CarouselProjectChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
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
        }
        .buttonStyle(.plain)
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
