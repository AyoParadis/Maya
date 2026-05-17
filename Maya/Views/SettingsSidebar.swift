import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsSidebar: View {
    @Bindable var project: Project
    let onExport: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                videoSection
                Divider()
                canvasSection
                Divider()
                deviceSection
                Divider()
                transformSection
                Divider()
                BackgroundPicker(project: project)
                Divider()
                shadowSection
                Divider()
                exportSection
                if let error = project.lastExportError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 12)
            }
            .padding(16)
        }
        .frame(minWidth: 280)
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Device").font(.headline)
                Spacer()
                if project.deviceModel.kind == .physical {
                    Text(project.deviceColor.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            // Model picker — wraps to multiple rows so 5 entries (Off, Generic
            // and the three Pro models) all fit comfortably in the sidebar.
            let columns = [GridItem(.adaptive(minimum: 78), spacing: 6)]
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
            if project.deviceModel.kind == .physical {
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
            Toggle(isOn: $project.shadow.enabled) {
                Text("Shadow").font(.headline)
            }
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
            Text("Canvas")
                .font(.headline)

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
            Text("Recording")
                .font(.headline)

            if project.videoURL != nil {
                Label(project.displayName ?? "Loaded video", systemImage: "film")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.callout)
                HStack(spacing: 8) {
                    Button {
                        project.togglePlayback()
                    } label: {
                        Image(systemName: (project.player?.timeControlStatus == .playing) ? "pause.fill" : "play.fill")
                            .frame(width: 16)
                    }
                    .help("Play / Pause (Space)")

                    Button {
                        project.toggleMute()
                    } label: {
                        Image(systemName: project.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .frame(width: 16)
                    }
                    .help("Mute audio (M)")

                    Spacer()

                    Button("Replace…") { openVideoPicker() }
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
            Text("Size & Position")
                .font(.headline)

            HStack {
                Image(systemName: "minus.magnifyingglass")
                Slider(value: $project.scale, in: 0.3...1.6)
                Image(systemName: "plus.magnifyingglass")
            }
            Text(String(format: "Scale: %.0f%%", project.scale * 100))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Reset position") {
                project.offset = .zero
                project.scale = 0.85
            }
            .controlSize(.small)
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export")
                .font(.headline)

            Button {
                onExport()
            } label: {
                Label(exportButtonLabel, systemImage: exportButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(project.videoURL == nil || project.isExporting)

            Text(exportHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if project.isExporting {
                ProgressView(value: project.exportProgress)
                Text(String(format: "Exporting… %.0f%%", project.exportProgress * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exportButtonLabel: String {
        project.background.isTransparent
            ? "Export transparent (.mov)"
            : "Export video (.mp4)"
    }

    private var exportButtonIcon: String {
        project.background.isTransparent
            ? "square.and.arrow.down.on.square"
            : "square.and.arrow.down"
    }

    private var exportHint: String {
        let size = project.canvasAspect.renderSize
        let dims = "\(Int(size.width))×\(Int(size.height))"
        return project.background.isTransparent
            ? "\(dims) HEVC + alpha. Drop it over anything in AVPlayer / AVKit."
            : "\(dims) H.264 · \(project.canvasAspect.shortLabel)."
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
    /// Short label for the picker chip — "15 Pro" reads cleaner than the full
    /// name. Non-iPhone entries keep their displayName as-is.
    var shortName: String {
        if displayName.hasPrefix("iPhone ") {
            return String(displayName.dropFirst("iPhone ".count))
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
            .frame(maxWidth: .infinity, minHeight: 30)
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
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.name)
    }
}

private struct AspectRatioChip: View {
    let aspect: CanvasAspectRatio
    let isSelected: Bool
    let action: () -> Void

    /// Tiny visual rectangle in the chip uses the actual aspect so the user
    /// can read 9:16 vs 4:5 at a glance instead of decoding the text label.
    private var thumbnailSize: CGSize {
        let maxDim: CGFloat = 22
        if aspect.ratio >= 1 {
            return CGSize(width: maxDim, height: maxDim / aspect.ratio)
        } else {
            return CGSize(width: maxDim * aspect.ratio, height: maxDim)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? Color.white : Color.primary.opacity(0.7),
                            lineWidth: 1.5)
                    .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                    .frame(height: 24)
                Text(aspect.shortLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? (Color(hex: "#6466FA") ?? .accentColor)
                          : Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white.opacity(0.4) : Color.gray.opacity(0.2),
                             lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(aspect.displayName)
    }
}
