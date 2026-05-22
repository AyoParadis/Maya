//
//  ContentView.swift
//  Maya
//
//  Created by Ronaldo Avalos on 16/05/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedMode: StudioMode = .carousel

    var body: some View {
        Group {
            switch selectedMode {
            case .video:
                EditorView(selectedMode: $selectedMode)
            case .carousel:
                CarouselStudioView(selectedMode: $selectedMode)
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
    }
}

enum StudioMode: String, CaseIterable, Identifiable {
    case video
    case carousel

    var id: String { rawValue }

    var label: String {
        switch self {
        case .video: "Video"
        case .carousel: "Carousel"
        }
    }
}

struct StudioModePicker: View {
    @Binding var selectedMode: StudioMode

    var body: some View {
        Picker("Mode", selection: $selectedMode) {
            ForEach(StudioMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 190)
    }
}

enum AppChrome {
    static let title = "Maya AI Studio"
    static let accentGradient = LinearGradient(
        colors: [
            Color(hex: "#7C6DFF") ?? .accentColor,
            Color(hex: "#377DFF") ?? .blue
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let accentShadow = (Color(hex: "#6466FA") ?? .accentColor).opacity(0.28)

    static var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty {
            return "v\(version) (\(build))"
        }
        return "v\(version)"
    }
}

#Preview {
    ContentView()
}
