//
//  MayaApp.swift
//  Maya
//
//  Created by Ronaldo Avalos on 16/05/26.
//

import SwiftUI

@main
struct MayaApp: App {
    init() {
        PerformanceBenchmark.runIfRequested()
        PerformanceMetrics.event(.appLaunch, detail: "MayaApp initialized")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1360, height: 900)
        .windowResizability(.contentMinSize)
    }
}
