import SwiftUI
import AppKit

struct MenuBarSummary: View {
    @Environment(MonitorStore.self) private var store
    var body: some View { VStack(alignment: .leading, spacing: 6) { Text(L.text("menu.nodes")).font(.headline).padding(.horizontal, 8).padding(.top, 6); ForEach(store.nodes.prefix(5)) { node in HStack(spacing: 8) { StatusDot(status: node.info.status, diameter: 7); Text(node.info.name).lineLimit(1); Spacer(); MiniBar(value: node.metrics.cpuUsage, tint: AsterColor.chartPalette[0]); MiniBar(value: node.metrics.memoryUsage, tint: AsterColor.chartPalette[1]) }.padding(.horizontal, 8) }; Divider(); Button(L.text("menu.open")) { NSApplication.shared.activate(ignoringOtherApps: true) }.keyboardShortcut("o") }.frame(width: 260).padding(.bottom, 6) }
}

private struct MiniBar: View { let value: Double; let tint: Color; var body: some View { Capsule().fill(tint.opacity(0.2)).overlay(alignment: .leading) { Capsule().fill(tint).frame(width: 34 * value / 100) }.frame(width: 34, height: 5) } }

#Preview { MenuBarSummary().environment(MonitorStore()).padding() }
