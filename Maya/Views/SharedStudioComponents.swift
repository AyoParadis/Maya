import SwiftUI

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
                                accent.opacity(isEnabled ? 1.0 : 0.45),
                                accentDark.opacity(isEnabled ? 1.0 : 0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(isEnabled ? 0.22 : 0.08), lineWidth: 1)
                    )
                    .shadow(
                        color: accent.opacity(isEnabled && isHovering ? 0.45 : 0.25),
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
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovering = hovering && isEnabled
        }
        .help(isEnabled ? (enabledHelp ?? title) : disabledHelp)
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
                Text(workingLabel)
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
}
