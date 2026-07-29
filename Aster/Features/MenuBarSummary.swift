import AppKit
import SwiftUI

/// Rich menu-bar panel (MenuBarExtra `.window` style): fleet header, aggregate
/// speed/load strip and per-node cards with CPU/memory/disk meters.
struct MenuBarSummary: View {
  @Environment(MonitorStore.self) private var store
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismiss) private var dismiss

  private var nodes: [NodeSnapshot] { store.nodes }
  private var upRate: Double { nodes.reduce(0) { $0 + $1.metrics.uploadBytesPerSecond } }
  private var downRate: Double { nodes.reduce(0) { $0 + $1.metrics.downloadBytesPerSecond } }
  private var averageLoad: Double {
    nodes.isEmpty ? 0 : nodes.reduce(0) { $0 + $1.metrics.loadAverage } / Double(nodes.count)
  }

  var body: some View {
    VStack(spacing: AsterSpacing.sm) {
      header
      if nodes.isEmpty {
        emptyState
      } else {
        summaryStrip
        nodeList
      }
      footer
    }
    .padding(AsterSpacing.sm)
    .frame(width: 324)
    .background(alignment: .top) {
      LinearGradient(
        colors: [AsterColor.accent.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom
      )
      .frame(height: 130)
      .ignoresSafeArea()
    }
  }

  // MARK: header

  private var header: some View {
    HStack(spacing: AsterSpacing.xs) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            LinearGradient(
              colors: [AsterColor.accent, AsterColor.chartPalette[4]],
              startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .frame(width: 30, height: 30)
        Image(systemName: "waveform.path.ecg")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white)
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(L.text("app.name"))
          .font(.system(size: 14, weight: .bold, design: .rounded))
        Text(store.connectionState.localizedText)
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: AsterSpacing.xs)
      if !nodes.isEmpty { onlineChip }
    }
  }

  private var onlineChip: some View {
    HStack(spacing: 5) {
      StatusDot(status: store.onlineCount == nodes.count ? .online : .warning, diameter: 6)
      Text("\(store.onlineCount)/\(nodes.count)")
        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      (store.onlineCount == nodes.count ? AsterColor.online : AsterColor.warning).opacity(0.13),
      in: Capsule())
  }

  // MARK: aggregate strip

  private var summaryStrip: some View {
    HStack(spacing: 0) {
      stat(
        icon: "arrow.up", tint: AsterColor.chartPalette[3], title: L.text("metric.upload"),
        value: rateText(upRate))
      divider
      stat(
        icon: "arrow.down", tint: AsterColor.chartPalette[0], title: L.text("metric.download"),
        value: rateText(downRate))
      divider
      stat(
        icon: "gauge.with.needle", tint: AsterColor.chartPalette[1],
        title: L.text("overview.load"), value: String(format: "%.2f", averageLoad))
    }
    .padding(.vertical, AsterSpacing.xs)
    .background(panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var divider: some View {
    Rectangle().fill(AsterColor.foregroundSecondary.opacity(0.15)).frame(width: 1, height: 22)
  }

  private func stat(icon: String, tint: Color, title: String, value: String) -> some View {
    VStack(spacing: 3) {
      HStack(spacing: 3) {
        Image(systemName: icon).font(.system(size: 8, weight: .bold)).foregroundStyle(tint)
        Text(title).font(.system(size: 9.5)).foregroundStyle(AsterColor.foregroundSecondary)
      }
      Text(value)
        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
        .contentTransition(.numericText())
    }
    .frame(maxWidth: .infinity)
    .lineLimit(1)
  }

  // MARK: node list

  @ViewBuilder private var nodeList: some View {
    let rows = VStack(spacing: 6) {
      ForEach(nodes) { node in
        NodeRow(node: node) { openMainWindow() }
      }
    }
    if nodes.count > 5 {
      ScrollView(showsIndicators: false) { rows }.frame(height: 5 * 68)
    } else {
      rows
    }
  }

  private var emptyState: some View {
    VStack(spacing: 6) {
      Image(systemName: "server.rack")
        .font(.system(size: 22, weight: .light))
        .foregroundStyle(AsterColor.foregroundSecondary)
      Text(L.text("menu.empty"))
        .font(AsterTypography.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, AsterSpacing.lg)
    .background(panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  // MARK: footer

  private var footer: some View {
    HStack {
      FooterButton(title: L.text("menu.open"), icon: "macwindow") { openMainWindow() }
        .keyboardShortcut("o")
      Spacer()
      FooterButton(title: L.text("menu.quit"), icon: "power") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    }
  }

  private func openMainWindow() {
    dismiss()
    openWindow(id: "main-window")
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  private func rateText(_ value: Double) -> String {
    let rate = AsterFormat.rate(value)
    return "\(rate.value) \(rate.unit)"
  }
}

private let panelFill = Color.primary.opacity(0.045)

// MARK: - Node row

private struct NodeRow: View {
  let node: NodeSnapshot
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 7) {
        HStack(spacing: 5) {
          Text(node.info.flag).font(.system(size: 12))
          Text(node.info.name)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .lineLimit(1)
          StatusDot(status: node.info.status, diameter: 5)
          Spacer(minLength: AsterSpacing.xs)
          Text("↑ \(compactRate(node.metrics.uploadBytesPerSecond))")
            .foregroundStyle(AsterColor.foregroundSecondary)
          Text("↓ \(compactRate(node.metrics.downloadBytesPerSecond))")
            .foregroundStyle(AsterColor.foregroundSecondary)
        }
        .font(.system(size: 10, design: .rounded).monospacedDigit())
        HStack(spacing: AsterSpacing.sm) {
          meter(L.text("metric.cpu"), node.metrics.cpuUsage, AsterColor.chartPalette[0])
          meter(L.text("metric.memory"), node.metrics.memoryUsage, AsterColor.chartPalette[1])
          meter(L.text("metric.disk"), node.metrics.diskUsage, AsterColor.chartPalette[2])
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 9)
      .background(
        Color.primary.opacity(hovered ? 0.085 : 0.045),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color.primary.opacity(hovered ? 0.12 : 0), lineWidth: 1)
      }
      .opacity(node.info.status == .offline ? 0.55 : 1)
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .animation(AsterAnimation.gentle, value: hovered)
    .onHover { hovered = $0 }
  }

  private func meter(_ label: String, _ value: Double, _ tint: Color) -> some View {
    let clamped = min(max(value / 100, 0), 1)
    let barTint = value >= 85 ? AsterColor.warning : tint
    return VStack(spacing: 3) {
      HStack {
        Text(label).font(.system(size: 9)).foregroundStyle(AsterColor.foregroundSecondary)
        Spacer()
        Text("\(Int(value.rounded()))%")
          .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
          .contentTransition(.numericText())
      }
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(barTint.opacity(0.16))
          Capsule().fill(barTint).frame(width: geo.size.width * clamped)
        }
      }
      .frame(height: 3.5)
      .animation(AsterAnimation.gentle, value: clamped)
    }
  }

  private func compactRate(_ value: Double) -> String {
    let rate = AsterFormat.rate(value)
    return "\(rate.value) \(rate.unit)"
  }
}

// MARK: - Footer button

private struct FooterButton: View {
  let title: String
  let icon: String
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: icon).font(.system(size: 10, weight: .semibold))
        Text(title).font(.system(size: 11.5, weight: .medium))
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(
        Color.primary.opacity(hovered ? 0.08 : 0),
        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .buttonStyle(.plain)
    .foregroundStyle(hovered ? AsterColor.foregroundPrimary : AsterColor.foregroundSecondary)
    .animation(AsterAnimation.gentle, value: hovered)
    .onHover { hovered = $0 }
  }
}

#Preview {
  MenuBarSummary().environment(MonitorStore.preview)
}
