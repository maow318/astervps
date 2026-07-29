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
  @Environment(MonitorStore.self) private var store
  let node: NodeSnapshot
  let action: () -> Void
  @State private var hovered = false
  @State private var showProcesses = false

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
          if node.metrics.swapTotalBytes > 0 {
            meter(L.text("metric.swap"), node.metrics.swapUsage, AsterColor.chartPalette[4])
          }
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
    .task(id: hovered) {
      // Show the per-process breakdown after a short dwell, Sensei-style.
      if hovered {
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, hovered else { return }
        showProcesses = true
        await store.loadTopProcesses(for: node.id)
      } else {
        showProcesses = false
      }
    }
    .popover(isPresented: $showProcesses, arrowEdge: .trailing) {
      NodeInsightPopover(nodeID: node.id).environment(store)
    }
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

// MARK: - Node insight popover

/// Full machine panel shown on hover: identity, live gauges for CPU, memory,
/// swap and disk, the network/connection line, then the top-process ranking.
struct NodeInsightPopover: View {
  @Environment(MonitorStore.self) private var store
  let nodeID: UUID

  var body: some View {
    if let node = store.node(id: nodeID) {
      VStack(alignment: .leading, spacing: AsterSpacing.sm) {
        header(node)
        chartGrid(node)
        vitalsLine(node)
        Divider().opacity(0.4)
        processSection
      }
      .padding(AsterSpacing.sm)
      .frame(width: 290)
    }
  }

  private func header(_ node: NodeSnapshot) -> some View {
    HStack(spacing: 6) {
      Text(node.info.flag).font(.system(size: 13))
      Text(node.info.name).font(.system(size: 13, weight: .bold, design: .rounded))
      StatusDot(status: node.info.status, diameter: 6)
      Spacer(minLength: AsterSpacing.xs)
      if let host = endpointHost {
        Text(host)
          .font(.system(size: 10, design: .rounded).monospacedDigit())
          .foregroundStyle(AsterColor.foregroundSecondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
  }

  private var endpointHost: String? {
    guard let machine = store.machines.first(where: { $0.id == nodeID }) else { return nil }
    return URL(string: machine.endpoint)?.host ?? machine.endpoint
  }

  /// Thumbnail history charts — the panel row already shows the live bars, so
  /// hovering adds the time dimension instead of repeating them.
  private func chartGrid(_ node: NodeSnapshot) -> some View {
    let metrics = node.metrics
    let down = AsterFormat.rate(metrics.downloadBytesPerSecond)
    let up = AsterFormat.rate(metrics.uploadBytesPerSecond)
    return LazyVGrid(
      columns: [GridItem(.flexible(), spacing: AsterSpacing.xs), GridItem(.flexible())],
      spacing: AsterSpacing.xs
    ) {
      ChartCell(
        label: L.text("metric.cpu"),
        value: "\(Int(metrics.cpuUsage.rounded()))%",
        detail: "\(L.text("overview.load")) \(String(format: "%.2f", metrics.loadAverage))",
        samples: node.history.cpu, tint: AsterColor.chartPalette[0])
      ChartCell(
        label: L.text("metric.memory"),
        value: "\(Int(metrics.memoryUsage.rounded()))%",
        detail:
          "\(AsterFormat.bytes(metrics.memoryUsedBytes)) / \(AsterFormat.bytes(metrics.memoryTotalBytes))",
        samples: node.history.memory, tint: AsterColor.chartPalette[1])
      ChartCell(
        label: L.text("metric.download"),
        value: "\(down.value) \(down.unit)",
        samples: node.history.download, tint: AsterColor.chartPalette[1])
      ChartCell(
        label: L.text("metric.upload"),
        value: "\(up.value) \(up.unit)",
        samples: node.history.upload, tint: AsterColor.chartPalette[4])
    }
  }

  private func vitalsLine(_ node: NodeSnapshot) -> some View {
    HStack(spacing: AsterSpacing.xs) {
      Text(
        "\(L.text("metric.disk")) \(AsterFormat.bytes(node.metrics.diskUsedBytes)) / \(AsterFormat.bytes(node.metrics.diskTotalBytes))"
      )
      Spacer(minLength: AsterSpacing.xxs)
      Text("\(L.text("metric.connections")) \(node.metrics.connectionCount)")
      Text("\(L.text("metric.processes")) \(node.metrics.processCount)")
    }
    .font(.system(size: 9.5, design: .rounded).monospacedDigit())
    .foregroundStyle(AsterColor.foregroundSecondary)
    .lineLimit(1)
  }

  @ViewBuilder private var processSection: some View {
    HStack(spacing: 5) {
      Image(systemName: "chart.bar.fill")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(AsterColor.accent)
      Text(L.text("menu.processes"))
        .font(.system(size: 11, weight: .semibold, design: .rounded))
    }
    switch store.processesByNode[nodeID] {
    case .none:
      ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        .padding(.vertical, AsterSpacing.xs)
    case .some(.none):
      Text(L.text("menu.processesOld"))
        .font(AsterTypography.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
    case .some(.some(let processes)):
      let ranked = processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(8)
      VStack(spacing: 4) {
        ForEach(Array(ranked)) { proc in
          HStack(spacing: AsterSpacing.xs) {
            Text(proc.name)
              .font(.system(size: 11, weight: .medium, design: .rounded))
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer(minLength: AsterSpacing.xs)
            Text(String(format: "%.1f%%", proc.cpuPercent))
              .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
              .frame(width: 46, alignment: .trailing)
            Text(AsterFormat.bytes(proc.memBytes))
              .font(.system(size: 10, design: .rounded).monospacedDigit())
              .foregroundStyle(AsterColor.foregroundSecondary)
              .frame(width: 62, alignment: .trailing)
          }
        }
      }
      if ranked.isEmpty {
        Text("—").font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
      }
    }
  }
}

private struct ChartCell: View {
  let label: String
  let value: String
  var detail: String? = nil
  let samples: [MetricSample]
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(label).font(.system(size: 9)).foregroundStyle(AsterColor.foregroundSecondary)
        Spacer()
        Text(value)
          .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
          .contentTransition(.numericText())
      }
      Sparkline(samples: samples, tint: tint, height: 26)
      if let detail {
        Text(detail)
          .font(.system(size: 8.5, design: .rounded).monospacedDigit())
          .foregroundStyle(AsterColor.foregroundSecondary.opacity(0.85))
          .lineLimit(1)
      }
    }
    .padding(7)
    .background(
      Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
