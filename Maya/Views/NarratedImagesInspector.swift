import AppKit
import SwiftUI

struct NarratedImagesInspector: View {
    @Bindable var project: NarratedImageProject
    let onGenerateCaptions: () -> Void
    let onRegenerateVoiceover: () -> Void
    let onRegenerateVoiceAndCaptions: () -> Void
    let onAlignCaptionsToVoice: () -> Void
    let onInstallCaptionAligner: () -> Void
    let onClose: () -> Void
    private let systemFontFamilies = ["System"] + NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    selectedSceneSection
                }
                .padding(18)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Inspector")
                    .font(.headline)
                Text("Narrated image scene")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var selectedSceneSection: some View {
        if let scene = project.selectedScene {
            @Bindable var scene = scene
            VStack(alignment: .leading, spacing: 12) {
                Text("Selected Scene").font(.headline)
                Text(scene.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                StudioVoiceoverScriptEditor(
                    title: "Spoken script",
                    placeholder: "Write the narration for this image...",
                    text: $scene.script
                )

                generationControls(scene: scene)

                captionBeatsSection(scene: scene)

                Picker("Motion", selection: $scene.motionPreset) {
                    ForEach(CarouselMotionPreset.allCases) { motion in
                        Text(motion.label).tag(motion)
                    }
                }

                HStack {
                    Text("Duration")
                    Spacer()
                    Text("\(scene.duration, specifier: "%.1f")s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $scene.duration, in: 0.5...30.0, step: 0.1)
                    .tint(.gray)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Caption Layout")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Smart fit") {
                            project.applyShortFormCaptionDefaults(to: scene)
                            project.retimeCaptionsToSceneDuration(for: scene, markManual: true)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                    HStack(spacing: 8) {
                        captionPlacementButton("Top", anchor: CGPoint(x: 0.5, y: 0.24), scene: scene)
                        captionPlacementButton("Middle", anchor: CGPoint(x: 0.5, y: 0.5), scene: scene)
                        captionPlacementButton("Lower", anchor: CGPoint(x: 0.5, y: 0.58), scene: scene)
                    }
                    HStack {
                        Text("Width")
                        Slider(value: Binding(
                            get: { scene.captionBoxWidth },
                            set: { scene.captionBoxWidth = max(0.38, min(0.96, $0)) }
                        ), in: 0.38...0.96, step: 0.01)
                        Text("\(Int(scene.captionBoxWidth * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Size")
                        Slider(value: Binding(
                            get: { scene.captionFontScale },
                            set: { scene.captionFontScale = max(0.72, min(1.45, $0)) }
                        ), in: 0.72...1.45, step: 0.01)
                        Text("\(scene.captionFontScale, specifier: "%.2f")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Picker("Font", selection: Binding(
                        get: { scene.captionFontFamily ?? "System" },
                        set: { scene.captionFontFamily = $0 == "System" ? nil : $0 }
                    )) {
                        ForEach(systemFontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    Text("Position")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("X")
                        Slider(value: Binding(
                            get: { scene.captionAnchor.x },
                            set: { scene.captionAnchor.x = max(0.08, min(0.92, $0)) }
                        ), in: 0.08...0.92, step: 0.01)
                        Text("\(scene.captionAnchor.x, specifier: "%.2f")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Y")
                        Slider(value: Binding(
                            get: { scene.captionAnchor.y },
                            set: { scene.captionAnchor.y = max(0.08, min(0.92, $0)) }
                        ), in: 0.08...0.92, step: 0.01)
                        Text("\(scene.captionAnchor.y, specifier: "%.2f")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let duration = scene.narrationAudioDuration {
                    Text("Audio \(duration, specifier: "%.1f")s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let error = scene.narrationError {
                    CopyableMessageBox(text: error, isError: true)
                }

                Button(role: .destructive) {
                    project.removeScene(id: scene.id)
                } label: {
                    Label("Delete scene", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .textFieldStyle(.roundedBorder)
        } else {
            Text("Import an image to edit its script, captions, timing, and placement.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func generationControls(scene: NarratedImageScene) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Generation")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(scene.narrationStatus.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Button(action: onRegenerateVoiceAndCaptions) {
                Label(project.isGeneratingNarration ? "Regenerating..." : "Voice + aligned captions", systemImage: "wand.and.waves")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(project.isGeneratingNarration || scene.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            HStack(spacing: 8) {
                Button(action: onRegenerateVoiceover) {
                    Label("Voice", systemImage: "waveform.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(project.isGeneratingNarration || scene.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                .disabled(project.isGeneratingNarration || project.isInstallingCaptionAligner)
            }

            captionAlignmentStatus(scene: scene)
        }
    }

    private func captionBeatsSection(scene: NarratedImageScene) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Captions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(scene.captionBeats.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if scene.captionBeats.isEmpty {
                Text("Generate captions from the spoken script, then edit the visible text here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                captionBeatPicker(scene: scene)
                if let index = selectedBeatIndex(in: scene) {
                    captionBeatEditor(scene: scene, index: index)
                }
                Text("Caption timing is matched to the voice. Use the timeline handles only when you need a manual timing tweak.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func captionBeatPicker(scene: NarratedImageScene) -> some View {
        Picker("Selected beat", selection: Binding(
            get: { scene.selectedCaptionBeatID ?? scene.captionBeats.first?.id },
            set: { scene.selectedCaptionBeatID = $0 }
        )) {
            ForEach(Array(scene.captionBeats.enumerated()), id: \.element.id) { index, beat in
                Text("\(index + 1). \(beat.text)").tag(Optional(beat.id))
            }
        }
    }

    private func selectedBeatIndex(in scene: NarratedImageScene) -> Int? {
        guard !scene.captionBeats.isEmpty else { return nil }
        let selectedID = scene.selectedCaptionBeatID ?? scene.captionBeats.first?.id
        return scene.captionBeats.firstIndex { $0.id == selectedID } ?? scene.captionBeats.indices.first
    }

    private func captionBeatEditor(scene: NarratedImageScene, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Beat \(index + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let source = scene.captionBeats[safe: index]?.alignmentSource {
                Text(source.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(source == .forcedAligned ? .green : source == .manual ? .blue : .orange)
            }
            TextField("Caption", text: Binding(
                get: { scene.captionBeats[safe: index]?.text ?? "" },
                set: { value in
                    guard scene.captionBeats.indices.contains(index) else { return }
                    scene.captionBeats[index].text = value
                    scene.captionBeats[index].alignmentSource = .manual
                }
            ))
            Picker("Style", selection: Binding(
                get: { scene.captionBeats[safe: index]?.style ?? .boldCenter },
                set: { value in
                    guard scene.captionBeats.indices.contains(index) else { return }
                    scene.captionBeats[index].style = value
                }
            )) {
                ForEach(NarratedCaptionStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func captionPlacementButton(_ title: String, anchor: CGPoint, scene: NarratedImageScene) -> some View {
        Button(title) {
            scene.captionAnchor = anchor
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    private func captionAlignmentStatus(scene: NarratedImageScene) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: captionAlignmentIcon(for: scene))
                    .foregroundStyle(captionAlignmentTint(for: scene))
                Text(scene.captionAlignmentStatus.label)
                    .font(.caption.weight(.semibold))
                Spacer()
                if project.captionAlignerInstallationStatus != .installed {
                    Button(action: onInstallCaptionAligner) {
                        Text(project.isInstallingCaptionAligner ? "Installing..." : "Install")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                    .disabled(project.isInstallingCaptionAligner || project.isGeneratingNarration)
                }
            }
            if let message = project.captionAlignmentMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if project.captionAlignerInstallationStatus != .installed {
                Text("Install the local aligner for exact voice timing.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let error = scene.captionAlignmentError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
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
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
