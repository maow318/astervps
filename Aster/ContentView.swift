//
//  ContentView.swift
//  Aster
//
//  Created by serein on 2026/7/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(MonitorStore.self) private var store
    var body: some View { MainSplitView().environment(store) }
}

#Preview { ContentView().environment(MonitorStore()) }
