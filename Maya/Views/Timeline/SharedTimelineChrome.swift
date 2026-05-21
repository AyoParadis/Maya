import SwiftUI

struct TimelineToolbarIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct TimelineTimeReadout: View {
    let current: Double
    let total: Double

    var body: some View {
        HStack(spacing: 4) {
            Text(formatTimestamp(current))
                .foregroundStyle(.white.opacity(0.95))
            Text("/")
                .foregroundStyle(.white.opacity(0.5))
            Text(formatTimestamp(total))
                .foregroundStyle(.white.opacity(0.7))
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
    }
}

struct TimelineShortcutHint: View {
    let key: String
    let description: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .frame(minWidth: 14)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct TimelineRowLabel: View {
    let icon: String
    let title: String
    let height: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(height: height, alignment: .center)
    }
}

struct TimelineTrackBackground: View {
    var cornerRadius: CGFloat = 6
    var fillOpacity: Double = 0.03

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}
