import AppKit
import SwiftUI

struct CarouselInspector: View {
    @Bindable var project: CarouselProject
    let onRegenerateVoiceover: (CarouselCard) -> Void
    let onRedetectText: (CarouselCard) -> Void
    let onCleanScript: (CarouselCard) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    selectedCardSection
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
                Text("Carousel slide details")
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
            .help("Close inspector")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var selectedCardSection: some View {
        if let card = project.selectedCard {
            @Bindable var card = card
            VStack(alignment: .leading, spacing: 12) {
                Text("Selected Card").font(.headline)
                HStack {
                    Label(card.status.label, systemImage: card.status.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(card.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                TextField("Role", text: $card.role)
                TextField("Badge", text: $card.badge)
                TextField("Headline", text: $card.headline, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Subtitle", text: $card.subtitle, axis: .vertical)
                    .lineLimit(2...4)
                TextField("CTA", text: $card.cta)
                TextField("Visual prompt", text: $card.visualPrompt, axis: .vertical)
                    .lineLimit(2...5)
                narrationSection(for: card)
                if !card.rationale.isEmpty {
                    Text(card.rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Picker("Motion", selection: Binding(
                    get: { card.motionOverride ?? project.motionPreset },
                    set: { card.motionOverride = $0 }
                )) {
                    ForEach(CarouselMotionPreset.allCases) { motion in
                        Text(motion.label).tag(motion)
                    }
                }
                HStack {
                    Text("Duration")
                    Spacer()
                    Text("\(card.duration, specifier: "%.1f")s")
                        .foregroundStyle(.secondary)
                        .font(.caption.monospacedDigit())
                }
                Slider(value: $card.duration, in: 0.5...30.0, step: 0.1)
                    .tint(.gray)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Focal X")
                        Spacer()
                        Text("\(card.focalPoint.x, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                            .font(.caption.monospacedDigit())
                    }
                    Slider(
                        value: Binding(
                            get: { card.focalPoint.x },
                            set: { card.focalPoint.x = max(0, min(1, $0)) }
                        ),
                        in: 0...1,
                        step: 0.01
                    )
                    .tint(.gray)
                    HStack {
                        Text("Focal Y")
                        Spacer()
                        Text("\(card.focalPoint.y, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                            .font(.caption.monospacedDigit())
                    }
                    Slider(
                        value: Binding(
                            get: { card.focalPoint.y },
                            set: { card.focalPoint.y = max(0, min(1, $0)) }
                        ),
                        in: 0...1,
                        step: 0.01
                    )
                    .tint(.gray)
                }
                HStack {
                    StudioSmallActionButton(title: "Duplicate", icon: "square.on.square") {
                        project.duplicateSelectedCard()
                    }
                    StudioSmallActionButton(title: "Delete", icon: "trash", isDestructive: true) {
                        project.removeSelectedCard()
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .onChange(of: card.headline) { _, _ in project.validate() }
            .onChange(of: card.subtitle) { _, _ in project.validate() }
            .onChange(of: card.cta) { _, _ in project.validate() }
            .onChange(of: card.visualPrompt) { _, _ in project.validate() }
        } else {
            Text("Select a card to edit copy, motion, and timing.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func narrationSection(for card: CarouselCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Voiceover")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Label(card.narrationStatus.label, systemImage: card.narrationStatus.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(narrationStatusColor(card.narrationStatus))
            }

            if !card.detectedNarrationText.isEmpty {
                HStack {
                    Text("Detected text")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        copy(card.detectedNarrationText)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.plain)
                }
                Text(card.detectedNarrationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            HStack {
                Text("Spoken script")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if card.narrationScriptEdited {
                    Label("Edited", systemImage: "pencil")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }
            }
            TextEditor(text: Binding(
                get: { card.narrationScript },
                set: { value in
                    card.narrationScript = value
                    card.narrationScriptEdited = true
                }
            ))
            .font(.caption)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 110)
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.gray.opacity(0.18), lineWidth: 1))

            HStack(spacing: 8) {
                StudioSmallActionButton(
                    title: "Copy",
                    icon: "doc.on.doc",
                    isEnabled: !card.narrationScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    copy(card.narrationScript)
                }
                StudioSmallActionButton(
                    title: "Clean up",
                    icon: "wand.and.stars",
                    isEnabled: !cleanupSource(for: card).isEmpty
                        && !project.isCleaningNarrationText
                        && !project.isGeneratingNarration
                ) {
                    onCleanScript(card)
                }
            }

            HStack(spacing: 8) {
                StudioSmallActionButton(
                    title: "Re-detect",
                    icon: "text.viewfinder",
                    isEnabled: card.imageURL != nil && !project.isGeneratingNarration
                ) {
                    onRedetectText(card)
                }
                StudioSmallActionButton(
                    title: "Regenerate audio",
                    icon: "waveform.badge.plus",
                    isEnabled: !project.isGeneratingNarration
                        && !project.isInstallingPiper
                        && !project.isCachingVoicePreviews
                        && !project.isCleaningNarrationText
                        && !card.narrationScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    onRegenerateVoiceover(card)
                }
            }

            if let duration = card.narrationAudioDuration {
                Text("Audio \(duration, specifier: "%.1f")s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let error = card.narrationError {
                CopyableMessageBox(text: error, isError: true)
            }
        }
    }

    private func cleanupSource(for card: CarouselCard) -> String {
        let script = card.narrationScript.trimmingCharacters(in: .whitespacesAndNewlines)
        return script.isEmpty ? card.detectedNarrationText : script
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func narrationStatusColor(_ status: CarouselSlideNarrationStatus) -> Color {
        switch status {
        case .generated: .green
        case .failed: .red
        case .skipped: .secondary
        case .detecting, .generating: .blue
        case .idle: .secondary
        }
    }

}
