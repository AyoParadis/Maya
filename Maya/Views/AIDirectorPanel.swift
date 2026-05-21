import SwiftUI

struct AIDirectorPanel: View {
    @Binding var run: AIDirectorRun
    let onCreate: () -> Void
    let onRetry: () -> Void
    let onApply: (AIDirectorPlan) -> Void
    let onRevert: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusSection
                    if run.status.isWorking {
                        AIDirectorWorkingCard(status: run.status)
                    }
                    controlsSection
                        .disabled(run.status.isWorking)
                    planSection
                    versionSection
                    actionsSection
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Director")
                    .font(.headline)
                HStack(spacing: 6) {
                    Text("Social Demo")
                    Text("•")
                    AIDirectorTrustNote()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(run.status.label)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(run.status == .failed ? Color.red : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(run.status == .failed ? Color.red.opacity(0.10) : Color.gray.opacity(0.12))
                )
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Close AI Director")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusSection: some View {
        Group {
            if let error = run.error {
                Label {
                    Text(error)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
            }
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Direction")
                .font(.headline)

            sliderRow(
                title: "Target length",
                value: $run.settings.targetLength,
                range: 4...30,
                display: "\(Int(run.settings.targetLength))s"
            )

            Picker("Pacing", selection: $run.settings.pacing) {
                ForEach(AIDirectorPacing.allCases) { pacing in
                    Text(pacing.label).tag(pacing)
                }
            }
            .pickerStyle(.segmented)

            Picker("Zooms", selection: $run.settings.zoomIntensity) {
                ForEach(AIDirectorZoomIntensity.allCases) { intensity in
                    Text(intensity.label).tag(intensity)
                }
            }
            .pickerStyle(.segmented)

            sliderRow(
                title: "Opening hook",
                value: $run.settings.hookStrength,
                range: 0...1,
                display: "\(Int(run.settings.hookStrength * 100))%"
            )

            sliderRow(
                title: "Ending emphasis",
                value: $run.settings.endingEmphasis,
                range: 0...1,
                display: "\(Int(run.settings.endingEmphasis * 100))%"
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Revision notes")
                    .font(.caption.weight(.medium))
                TextEditor(text: $run.settings.revisionNotes)
                    .font(.callout)
                    .frame(minHeight: 74)
                    .scrollContentBackground(.hidden)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.18), lineWidth: 1))
            }
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generated Plan")
                .font(.headline)

            if let plan = run.selectedPlan {
                VStack(alignment: .leading, spacing: 10) {
                    Text(plan.rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Label("\(AIDirectorBridge.format(plan.trimEnd - plan.trimStart))s", systemImage: "scissors")
                        Spacer()
                        Label("\(plan.zoomSegments.count) zooms", systemImage: "sparkles")
                    }
                    .font(.caption.weight(.medium))

                    if !plan.warnings.isEmpty {
                        ForEach(plan.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } else {
                Text("Create a video to generate the first plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Versions")
                .font(.headline)

            if run.versions.isEmpty {
                Text("Retries will appear here for quick comparison.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(run.versions.enumerated()), id: \.element.id) { index, plan in
                    Button {
                        run.selectedVersionID = plan.id
                    } label: {
                        HStack {
                            Text("Version \(index + 1)")
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text("\(Int(plan.trimEnd - plan.trimStart))s")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if run.selectedPlan?.id == plan.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 8) {
            Button {
                onCreate()
            } label: {
                Label(primaryActionTitle, systemImage: run.status.isWorking ? "wand.and.stars" : "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(run.status.isWorking)

            HStack(spacing: 8) {
                Button("Retry") { onRetry() }
                    .disabled(run.versions.isEmpty || run.status.isWorking)

                Button("Apply plan") {
                    if let plan = run.selectedPlan { onApply(plan) }
                }
                .disabled(run.selectedPlan == nil || run.status.isWorking)

                Button("Revert") { onRevert() }
                    .disabled(run.originalEdit == nil || run.status.isWorking)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var primaryActionTitle: String {
        if run.status.isWorking {
            return run.status == .analyzing ? "Preparing frames..." : "Creating video..."
        }
        return run.versions.isEmpty ? "Create video" : "Create new plan"
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

}

struct AIDirectorWorkingCard: View {
    let status: AIDirectorStatus

    private var progress: Double {
        status == .analyzing ? 0.35 : 0.72
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.16))
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(status.workingTitle)
                        .font(.callout.weight(.semibold))
                    Text(status.workingDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                HStack {
                    Text(status == .analyzing ? "Frames" : "Codex CLI")
                    Spacer()
                    Text(status == .analyzing ? "Preparing" : "Generating plan")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "play.rectangle")
                Text("Maya will apply the edit and start preview automatically.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct AIDirectorTrustNote: View {
    @State private var isShowingInfo = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "terminal")
            Text("Local Codex")
            Button {
                isShowingInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .popover(isPresented: $isShowingInfo, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Local Codex")
                        .font(.headline)
                    Text("AI Director passes sampled frames and project metadata to the `codex` CLI installed on this Mac. Usage is tied to your local Codex login/subscription. Maya does not send the full video file and only applies trim and zoom edits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(width: 300)
            }
        }
    }
}
