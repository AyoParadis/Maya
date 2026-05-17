import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BackgroundPicker: View {
    @Bindable var project: Project

    @State private var selectedKind: Kind = .gradient
    @State private var solidHex: String = BackgroundOption.defaultSolids[0]
    @State private var gradientSpec: GradientSpec = GradientSpec.presets[0]
    @State private var imageURL: URL?

    enum Kind: String, CaseIterable, Identifiable {
        case none, solid, gradient, image, videoBlur
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: "None"
            case .solid: "Solid"
            case .gradient: "Gradient"
            case .image: "Image"
            case .videoBlur: "Blur"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background")
                .font(.headline)

            Picker("", selection: $selectedKind) {
                ForEach(Kind.allCases) { k in
                    Text(k.label).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: selectedKind) { _, _ in applySelection() }
            .onAppear { syncKindFromProject() }
            .onChange(of: project.background) { _, _ in syncKindFromProject() }

            Group {
                switch selectedKind {
                case .none:
                    transparencyInfo
                case .solid:
                    solidGrid
                case .gradient:
                    gradientGrid
                case .image:
                    imagePicker
                case .videoBlur:
                    Text("Blurred frame of your video, Keynote-style.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var transparencyInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "#6466FA") ?? .accentColor)
                Text("Transparent")
                    .font(.callout.weight(.semibold))
            }
            Text("Export will be a .mov with HEVC + alpha. The framed phone shows over arbitrary content in any AVPlayer/AVKit consumer (your tutorial app, Final Cut, Motion).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func syncKindFromProject() {
        switch project.background {
        case .none: selectedKind = .none
        case .solid: selectedKind = .solid
        case .gradient: selectedKind = .gradient
        case .image: selectedKind = .image
        case .videoBlur: selectedKind = .videoBlur
        }
    }

    private var solidGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 36), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(BackgroundOption.defaultSolids, id: \.self) { hex in
                Button {
                    solidHex = hex
                    project.background = .solid(hex: hex)
                } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: hex) ?? .black)
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(currentSolidHex == hex ? Color.accentColor : .black.opacity(0.1),
                                         lineWidth: currentSolidHex == hex ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var gradientGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 60), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(GradientSpec.presets.enumerated()), id: \.offset) { idx, spec in
                Button {
                    gradientSpec = spec
                    project.background = .gradient(spec)
                } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [spec.startColor, spec.endColor],
                                             startPoint: spec.startUnitPoint,
                                             endPoint: spec.endUnitPoint))
                        .frame(height: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(currentGradient == spec ? Color.accentColor : .black.opacity(0.1),
                                         lineWidth: currentGradient == spec ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var imagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = imageURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            Button("Choose image…") { chooseImage() }
        }
    }

    private var currentSolidHex: String? {
        if case .solid(let hex) = project.background { return hex }
        return nil
    }

    private var currentGradient: GradientSpec? {
        if case .gradient(let s) = project.background { return s }
        return nil
    }

    private func applySelection() {
        switch selectedKind {
        case .none:
            project.background = .none
        case .solid:
            project.background = .solid(hex: solidHex)
        case .gradient:
            project.background = .gradient(gradientSpec)
        case .image:
            if let url = imageURL {
                project.background = .image(url)
            } else {
                project.background = .solid(hex: solidHex)
            }
        case .videoBlur:
            project.background = .videoBlur
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            imageURL = url
            project.background = .image(url)
        }
    }
}
