import AppKit
import SwiftUI

struct VideoThumbnailStrip: View {
    let url: URL
    let thumbnailCount: Int
    let height: CGFloat

    @State private var thumbnails: [NSImage] = []

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if thumbnails.isEmpty {
                    Color.black.opacity(0.4)
                } else {
                    ForEach(0..<thumbnails.count, id: \.self) { idx in
                        Image(nsImage: thumbnails[idx])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width / CGFloat(thumbnails.count),
                                   height: proxy.size.height)
                            .clipped()
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(height: height)
        .task(id: url) {
            let count = thumbnailCount
            let imgs = await VideoThumbnailGenerator.shared.thumbnails(
                for: url,
                count: count,
                height: height
            )
            await MainActor.run { self.thumbnails = imgs }
        }
    }
}
