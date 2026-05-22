import SwiftUI

enum StudioSidebarMetrics {
    static let width: CGFloat = 360
    static let minWidth: CGFloat = 320
    static let outerPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 16
    static let bottomSpacer: CGFloat = 12
}

struct StudioSidebarScaffold<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioSidebarMetrics.sectionSpacing) {
                content()
                Spacer(minLength: StudioSidebarMetrics.bottomSpacer)
            }
            .padding(.horizontal, StudioSidebarMetrics.outerPadding)
            .padding(.vertical, StudioSidebarMetrics.outerPadding)
        }
        .scrollIndicators(.visible)
        .frame(minWidth: StudioSidebarMetrics.minWidth, idealWidth: StudioSidebarMetrics.width)
    }
}

struct StudioSidebarHeader: View {
    var title = "Maya AI Studio"

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            Text(appVersionLabel)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty {
            return "v\(version) (\(build))"
        }
        return "v\(version)"
    }
}

struct SidebarDisclosureSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .frame(width: 16, height: 16)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .padding(.horizontal, 12)
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(title)" : "Expand \(title)")

            if isExpanded {
                content()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(sectionFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .clipped()
    }

    private var sectionFill: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor).opacity(isExpanded ? 0.86 : 0.68)
        #else
        Color.primary.opacity(isExpanded ? 0.045 : 0.03)
        #endif
    }
}

struct CompactStatusMessage: View {
    let text: String
    var icon = "checkmark.circle.fill"
    var tint = Color.secondary

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct PiperVoiceSelector: View {
    @Binding var voice: String

    private let customVoiceTag = "__maya_custom_piper_voice__"

    private var catalogVoiceIDs: Set<String> {
        Set(PiperVoiceCatalog.voices.map(\.id))
    }

    private var isCustomVoice: Bool {
        !voice.isEmpty && !catalogVoiceIDs.contains(voice)
    }

    private var pickerSelection: Binding<String> {
        Binding {
            isCustomVoice || voice.isEmpty ? customVoiceTag : voice
        } set: { newValue in
            if newValue == customVoiceTag {
                if !isCustomVoice {
                    voice = ""
                }
            } else {
                voice = newValue
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI voice")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Picker("AI voice", selection: pickerSelection) {
                ForEach(PiperVoiceCatalog.voices) { voice in
                    Text(voice.displayName).tag(voice.id)
                }
                Divider()
                Text("Custom voice ID...").tag(customVoiceTag)
            }
            .labelsHidden()

            if isCustomVoice || voice.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Piper voice ID")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField(PiperNarrationService.defaultVoice, text: $voice)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .help("Type any Piper voice ID, including voices not listed above")
                }
            }
        }
    }
}

struct StudioVoiceoverControls: View {
    @Binding var voice: String
    let isPreviewing: Bool
    let isGenerating: Bool
    let isInstalling: Bool
    let isCaching: Bool
    let hasNarration: Bool
    let shouldShowInstall: Bool
    let status: (text: String, icon: String, tint: Color)?
    let errorMessage: String?
    let onPreview: () -> Void
    let onRemove: () -> Void
    let onInstall: () -> Void

    private var isBusy: Bool {
        isPreviewing || isGenerating || isInstalling || isCaching
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PiperVoiceSelector(voice: $voice)

            HStack(spacing: 8) {
                Button(action: onPreview) {
                    Label(isPreviewing ? "Previewing..." : "Preview", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isBusy)

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .frame(width: 30)
                }
                .disabled(!hasNarration || isGenerating)
                .help("Remove voiceover")
            }

            if shouldShowInstall {
                Button(action: onInstall) {
                    Label(isInstalling ? "Installing voice engine..." : "Install voice engine", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isInstalling || isCaching || isGenerating)
                .help("Create Maya's local Piper environment and install piper-tts")
            }

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            if let status {
                CompactStatusMessage(text: status.text, icon: status.icon, tint: status.tint)
            }

            if let errorMessage {
                CopyableMessageBox(text: errorMessage, isError: true)
            }
        }
    }
}

struct StudioVoiceoverScriptEditor: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92)
                    .padding(6)

                if text.isEmpty {
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(.secondary.opacity(0.75))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.18), lineWidth: 1))
        }
    }
}

struct StudioCanvasStage<Content: View>: View {
    let aspect: CGFloat
    var minimumSize: CGFloat = 220
    var heightReserve: CGFloat = 0
    var cornerRadius: CGFloat = 12
    var strokeColor = Color.black.opacity(0.1)
    var shadowColor = Color.black.opacity(0.25)
    var shadowRadius: CGFloat = 18
    var shadowX: CGFloat = 0
    var shadowY: CGFloat = 8
    @ViewBuilder let content: (CGSize) -> Content

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = fittedCanvasSize(in: proxy.size)
            content(canvasSize)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(strokeColor, lineWidth: 1)
                )
                .shadow(color: shadowColor, radius: shadowRadius, x: shadowX, y: shadowY)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
    }

    private func fittedCanvasSize(in available: CGSize) -> CGSize {
        let availableWidth = max(minimumSize, available.width)
        let availableHeight = max(minimumSize, available.height - heightReserve)
        if availableWidth / max(availableHeight, 1) > aspect {
            return CGSize(width: availableHeight * aspect, height: availableHeight)
        }
        return CGSize(width: availableWidth, height: availableWidth / aspect)
    }
}

struct EmptyCanvasPrompt: View {
    let icon: String
    let title: String
    let buttonTitle: String
    var buttonIcon = "folder"
    var footnote: String?
    var prominentButton = true
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            Text(title)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
            promptButton

            if let footnote {
                Text(footnote)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(22)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var promptButton: some View {
        if prominentButton {
            Button(action: action) {
                buttonLabel
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: action) {
                buttonLabel
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
        }
    }

    private var buttonLabel: some View {
        Label(buttonTitle, systemImage: buttonIcon)
            .font(.callout.weight(.semibold))
            .frame(minWidth: 170)
    }
}

struct AspectRatioChip: View {
    let aspect: CanvasAspectRatio
    let isSelected: Bool
    var minHeight: CGFloat = 60
    var maxThumbnailDimension: CGFloat = 22
    let action: () -> Void

    private var thumbnailSize: CGSize {
        if aspect.ratio >= 1 {
            return CGSize(width: maxThumbnailDimension, height: maxThumbnailDimension / aspect.ratio)
        }
        return CGSize(width: maxThumbnailDimension * aspect.ratio, height: maxThumbnailDimension)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? Color.white : Color.primary.opacity(0.7), lineWidth: 1.5)
                    .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                    .frame(height: maxThumbnailDimension + 2)
                Text(aspect.shortLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? (Color(hex: "#6466FA") ?? .accentColor) : Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(aspect.displayName)
    }
}

struct StudioSmallActionButton: View {
    let title: String
    let icon: String
    var isEnabled = true
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDestructive ? Color.red : Color.primary)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.18), lineWidth: 1))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

struct StudioActionCardButton: View {
    let title: String
    let subtitle: String
    let icon: String
    var isEnabled = true
    var isWorking = false
    var progress: Double = 0
    var showsProgress = true
    var workingLabel = "Exporting"
    var accent = Color(hex: "#6466FA") ?? .accentColor
    var accentDark = Color(hex: "#4F46E5") ?? .accentColor
    var disabledHelp = "Complete the required setup to enable this action"
    var enabledHelp: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(isVisuallyActive ? 1.0 : 0.45),
                                accentDark.opacity(isVisuallyActive ? 1.0 : 0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(isVisuallyActive ? 0.22 : 0.08), lineWidth: 1)
                    )
                    .shadow(
                        color: accent.opacity(isVisuallyActive && isHovering ? 0.45 : 0.25),
                        radius: isHovering ? 14 : 8,
                        x: 0,
                        y: isHovering ? 6 : 4
                    )

                if isWorking {
                    progressContent
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else {
                    idleContent
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .animation(.easeOut(duration: 0.2), value: isWorking)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isWorking)
        .onHover { hovering in
            isHovering = hovering && isEnabled && !isWorking
        }
        .help(isWorking ? title : (isEnabled ? (enabledHelp ?? title) : disabledHelp))
    }

    private var idleContent: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .offset(x: isHovering ? 3 : 0)
        }
    }

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(.white)
                Text(title.isEmpty ? workingLabel : title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                if showsProgress {
                    Text(String(format: "%.0f%%", clampedProgress * 100))
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }

            if showsProgress {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(4, g.size.width * CGFloat(clampedProgress)))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private var clampedProgress: Double {
        max(0, min(1, progress))
    }

    private var isVisuallyActive: Bool {
        isEnabled || isWorking
    }
}
struct CopyableMessageBox: View {
    let text: String
    var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(isError ? "Error" : "Message", systemImage: isError ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isError ? .red : .secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
            }

            TextEditor(text: .constant(text))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isError ? .red : .secondary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 86, maxHeight: 190)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.gray.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke((isError ? Color.red : Color.gray).opacity(0.20), lineWidth: 1))
        }
    }
}
