import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BackgroundPicker: View {
    @Bindable var project: Project

    @State private var selectedKind: Kind = .gradient
    @State private var solidHex: String = BackgroundOption.defaultSolids[0]
    @State private var gradientSpec: GradientSpec = GradientSpec.presets[0]
    @State private var imageURL: URL?

    // Custom solid editor
    @State private var customSolidColor: Color = Color(hex: "#6466FA") ?? .indigo

    // Custom gradient editor
    @State private var customGradientStart: Color = Color(hex: "#6466FA") ?? .indigo
    @State private var customGradientEnd: Color = Color(hex: "#EC4899") ?? .pink
    @State private var customGradientAngle: Double = 135

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
            .onAppear {
                syncKindFromProject()
                seedCustomEditorsFromProject()
            }
            .onChange(of: project.background) { _, _ in syncKindFromProject() }

            Group {
                switch selectedKind {
                case .none:
                    transparencyInfo
                case .solid:
                    solidSection
                case .gradient:
                    gradientSection
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

    // MARK: - Transparency

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

    // MARK: - Solid

    private var solidSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            solidGrid
            Divider()
            customSolidEditor
        }
    }

    private var solidGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 36), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(BackgroundOption.defaultSolids, id: \.self) { hex in
                Button {
                    solidHex = hex
                    customSolidColor = Color(hex: hex) ?? .black
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

    private var customSolidEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ColorPicker("", selection: Binding(
                    get: { customSolidColor },
                    set: { newColor in
                        customSolidColor = newColor
                        let hex = newColor.hexString
                        solidHex = hex
                        project.background = .solid(hex: hex)
                    }
                ), supportsOpacity: false)
                .labelsHidden()

                Text(customSolidColor.hexString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
    }

    // MARK: - Gradient

    private var gradientSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            gradientGrid
            Divider()
            customGradientEditor
        }
    }

    private var gradientGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 60), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(GradientSpec.presets.enumerated()), id: \.offset) { _, spec in
                Button {
                    gradientSpec = spec
                    customGradientStart = spec.startColor
                    customGradientEnd = spec.endColor
                    customGradientAngle = spec.angleDegrees
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

    private var customGradientEditor: some View {
        let customSpec = GradientSpec(
            startHex: customGradientStart.hexString,
            endHex: customGradientEnd.hexString,
            angleDegrees: customGradientAngle
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text("Custom").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            // Live preview
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    colors: [customGradientStart, customGradientEnd],
                    startPoint: customSpec.startUnitPoint,
                    endPoint: customSpec.endUnitPoint
                ))
                .frame(height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )

            HStack(spacing: 12) {
                colorWell(label: "Start", binding: $customGradientStart)
                colorWell(label: "End", binding: $customGradientEnd)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Angle").font(.caption.weight(.medium))
                    Spacer()
                    Text("\(Int(customGradientAngle.rounded()))°")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $customGradientAngle, in: 0...360, step: 1)
            }
        }
        .onChange(of: customGradientStart) { _, _ in pushCustomGradient() }
        .onChange(of: customGradientEnd) { _, _ in pushCustomGradient() }
        .onChange(of: customGradientAngle) { _, _ in pushCustomGradient() }
    }

    private func colorWell(label: String, binding: Binding<Color>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium))
            HStack(spacing: 8) {
                ColorPicker("", selection: binding, supportsOpacity: false)
                    .labelsHidden()
                Text(binding.wrappedValue.hexString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pushCustomGradient() {
        let spec = GradientSpec(
            startHex: customGradientStart.hexString,
            endHex: customGradientEnd.hexString,
            angleDegrees: customGradientAngle
        )
        gradientSpec = spec
        project.background = .gradient(spec)
    }

    // MARK: - Image

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

    // MARK: - Sync helpers

    private var currentSolidHex: String? {
        if case .solid(let hex) = project.background { return hex }
        return nil
    }

    private var currentGradient: GradientSpec? {
        if case .gradient(let s) = project.background { return s }
        return nil
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

    /// Seed the ColorPicker / gradient editor controls from whatever is currently
    /// active on the project, so the user picks up where they left off.
    private func seedCustomEditorsFromProject() {
        if case .solid(let hex) = project.background, let c = Color(hex: hex) {
            customSolidColor = c
            solidHex = hex
        }
        if case .gradient(let spec) = project.background {
            customGradientStart = spec.startColor
            customGradientEnd = spec.endColor
            customGradientAngle = spec.angleDegrees
            gradientSpec = spec
        }
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
