//
//  AsterApp.swift
//  Aster
//
//  Created by serein on 2026/7/26.
//

import SwiftUI

@main
struct AsterApp: App {
    @State private var store = MonitorStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 600)
                .background(AsterBackground())
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra(L.text("app.name"), systemImage: "waveform.path.ecg") { MenuBarSummary().environment(store) }
    }
}

private struct AsterBackground: View {
    var body: some View { LinearGradient(colors: [AsterColor.background1, AsterColor.background2], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea() }
}
