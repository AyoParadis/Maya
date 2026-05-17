import SwiftUI

struct AnimationEditorPanel: View {
    @Bindable var project: Project
    let segmentID: ZoomSegment.ID
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let binding = segmentBinding() {
                        presetsSection(binding: binding)
                        Divider()
                        timingSection(binding: binding)
                        Divider()
                        zoomSection(binding: binding)
                        Divider()
                        curveSection(binding: binding)
                        Divider()
                        focusSection(binding: binding)
                        Divider()
                        actionsSection
                    } else {
                        Text("Segment not found.").foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Text("Zoom event")
                .font(.headline)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Close panel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Presets
    private func presetsSection(binding: Binding<ZoomSegment>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Presets")
            let columns = [GridItem(.adaptive(minimum: 130), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ZoomSegment.presets) { preset in
                    PresetCard(preset: preset) {
                        var d = binding.wrappedValue
                        d.apply(preset: preset)
                        binding.wrappedValue = d
                    }
                }
            }
        }
    }

    // MARK: - Timing
    private func timingSection(binding: Binding<ZoomSegment>) -> some View {
        let totalDuration = max(project.durationSeconds, 0.5)
        return VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Timing")

            labeledSlider(
                title: "Start",
                value: Binding(
                    get: { binding.wrappedValue.startTime },
                    set: { newValue in
                        var d = binding.wrappedValue
                        let maxStart = max(totalDuration - d.duration, 0)
                        d.startTime = max(0, min(newValue, maxStart))
                        binding.wrappedValue = d
                    }
                ),
                range: 0...totalDuration,
                display: formattedTime(binding.wrappedValue.startTime)
            )

            labeledSlider(
                title: "Duration",
                value: Binding(
                    get: { binding.wrappedValue.duration },
                    set: { newValue in
                        var d = binding.wrappedValue
                        let maxDur = max(totalDuration - d.startTime, ZoomSegment.durationRange.lowerBound)
                        d.duration = max(ZoomSegment.durationRange.lowerBound,
                                         min(newValue, min(ZoomSegment.durationRange.upperBound, maxDur)))
                        binding.wrappedValue = d
                    }
                ),
                range: ZoomSegment.durationRange,
                display: String(format: "%.2fs", binding.wrappedValue.duration)
            )

            let halfDur = max(0.05, binding.wrappedValue.duration / 2)
            let inRange = ZoomSegment.transitionRange.lowerBound...min(ZoomSegment.transitionRange.upperBound, halfDur)
            labeledSlider(
                title: "Zoom in time",
                value: Binding(
                    get: { binding.wrappedValue.transitionIn },
                    set: { newValue in
                        var d = binding.wrappedValue
                        d.transitionIn = newValue
                        binding.wrappedValue = d
                    }
                ),
                range: inRange,
                display: String(format: "%.2fs", binding.wrappedValue.transitionIn)
            )

            labeledSlider(
                title: "Zoom out time",
                value: Binding(
                    get: { binding.wrappedValue.transitionOut },
                    set: { newValue in
                        var d = binding.wrappedValue
                        d.transitionOut = newValue
                        binding.wrappedValue = d
                    }
                ),
                range: inRange,
                display: String(format: "%.2fs", binding.wrappedValue.transitionOut)
            )
        }
    }

    // MARK: - Zoom
    private func zoomSection(binding: Binding<ZoomSegment>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Zoom")
            labeledSlider(
                title: "Scale",
                value: Binding(
                    get: { Double(binding.wrappedValue.scale) },
                    set: { newValue in
                        var d = binding.wrappedValue
                        d.scale = CGFloat(newValue)
                        binding.wrappedValue = d
                    }
                ),
                range: Double(ZoomSegment.scaleRange.lowerBound)...Double(ZoomSegment.scaleRange.upperBound),
                display: String(format: "%.2f×", binding.wrappedValue.scale)
            )
        }
    }

    // MARK: - Curve
    private func curveSection(binding: Binding<ZoomSegment>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Animation curve")
            let columns = [GridItem(.adaptive(minimum: 130), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AnimationCurve.allCases) { curve in
                    CurveOptionButton(
                        curve: curve,
                        isSelected: binding.wrappedValue.curve == curve
                    ) {
                        var d = binding.wrappedValue
                        d.curve = curve
                        binding.wrappedValue = d
                    }
                }
            }
        }
    }

    // MARK: - Focus
    private func focusSection(binding: Binding<ZoomSegment>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Focus")
            HStack(spacing: 10) {
                ForEach(ZoomFocus.allCases) { focus in
                    FocusOptionButton(
                        focus: focus,
                        isSelected: binding.wrappedValue.focus == focus
                    ) {
                        var d = binding.wrappedValue
                        d.focus = focus
                        binding.wrappedValue = d
                    }
                }
            }
        }
    }

    // MARK: - Actions
    private var actionsSection: some View {
        HStack {
            Button(role: .destructive) {
                project.removeZoomSegment(id: segmentID)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .controlSize(.regular)

            Spacer()

            Button {
                _ = project.duplicateZoomSegment(id: segmentID)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .controlSize(.regular)
        }
    }

    // MARK: - Helpers
    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func labeledSlider<V: BinaryFloatingPoint>(
        title: String,
        value: Binding<V>,
        range: ClosedRange<V>,
        display: String
    ) -> some View where V.Stride: BinaryFloatingPoint {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(display).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    /// Binds directly to the live segment inside `project.animations` so slider
    /// drags update the canvas in real time. Returns nil if the segment was
    /// removed out from under the panel.
    private func segmentBinding() -> Binding<ZoomSegment>? {
        guard project.animations.contains(where: { $0.id == segmentID }) else { return nil }
        return Binding(
            get: {
                project.animations.first(where: { $0.id == segmentID })
                    ?? ZoomSegment(startTime: 0, duration: 1, scale: 1, focus: .center)
            },
            set: { newValue in
                project.updateZoomSegment(newValue)
            }
        )
    }

    private func formattedTime(_ t: Double) -> String {
        let total = Int(t)
        let m = total / 60
        let s = total % 60
        let ms = Int((t - Double(total)) * 100)
        return String(format: "%d:%02d.%02d", m, s, abs(ms))
    }
}

private struct PresetCard: View {
    let preset: ZoomSegment.Preset
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: preset.symbol)
                        .font(.system(size: 14, weight: .semibold))
                    Text(preset.name).font(.callout.weight(.semibold))
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Text(String(format: "%.1f×", preset.scale))
                    Text("·")
                    Text(String(format: "%.1fs", preset.duration))
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#818CF8") ?? .indigo,
                        Color(hex: "#6466FA") ?? .indigo
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CurveOptionButton: View {
    let curve: AnimationCurve
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: curve.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(curve.label).font(.callout.weight(.semibold))
                    Text(curve.hint)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? (Color(hex: "#6466FA") ?? .accentColor)
                          : Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.white.opacity(0.4) : Color.gray.opacity(0.2),
                             lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FocusOptionButton: View {
    let focus: ZoomFocus
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: focus.systemImage)
                    .font(.system(size: 22, weight: .medium))
                Text(focus.label).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? (Color(hex: "#6466FA") ?? .accentColor)
                          : Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.white.opacity(0.4) : Color.gray.opacity(0.2),
                             lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
