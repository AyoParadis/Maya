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
                transformSection
                Divider()
                BackgroundPicker(project: project)
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
