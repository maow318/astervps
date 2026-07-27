import SwiftUI

enum NodeDisplayMode: String, CaseIterable, Identifiable {
  case grid, table, compact

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .grid: "square.grid.2x2"
    case .table: "list.bullet"
    case .compact: "tablecells"
    }
  }

  var titleKey: String { "mode.\(rawValue)" }
}

/// Shared node list container: grid cards, Komari-style table or compact
/// rows, with the chosen mode persisted across pages and launches.
struct NodesDisplay: View {
  let nodes: [NodeSnapshot]
  @AppStorage("aster.displayMode") private var modeRaw = NodeDisplayMode.grid.rawValue

  private var mode: NodeDisplayMode {
    NodeDisplayMode(rawValue: modeRaw) ?? .grid
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AsterSpacing.sm) {
      HStack {
        Spacer()
        Picker("", selection: $modeRaw) {
          ForEach(NodeDisplayMode.allCases) { mode in
            Image(systemName: mode.icon)
              .help(L.text(mode.titleKey))
              .tag(mode.rawValue)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 130)
      }
      switch mode {
      case .grid:
        NodeGrid(nodes: nodes)
      case .table:
        NodeTableView(nodes: nodes)
      case .compact:
        compactList
      }
    }
  }

  private var compactList: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 290, maximum: 360), spacing: AsterSpacing.sm)],
      spacing: AsterSpacing.sm
    ) {
      ForEach(nodes) { node in
        NodeCompactCard(node: node)
      }
    }
  }
}

/// Komari-style dense card: identity, billing chips, one icon-stat line,
/// rates + cumulative traffic, expiry + online duration.
struct NodeCompactCard: View {
  let node: NodeSnapshot

  var body: some View {
    NavigationLink(value: node.id) {
      GlassCard {
        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 5) {
            StatusDot(status: node.info.status, diameter: 7)
            Text(node.info.flag)
            Text(node.info.name)
              .font(AsterTypography.sectionTitle)
              .foregroundStyle(AsterColor.foregroundPrimary)
              .lineLimit(1)
            OSBadge(osID: node.info.operatingSystem, size: 11)
            Spacer()
          }
          if node.info.billingPrice != nil || node.info.billingExpiresAt != nil {
            billingChips
          }
          statLine
          networkLine
          footerLine
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var billingChips: some View {
    HStack(spacing: 6) {
      if let price = node.info.billingPrice {
        chip(price, tint: AsterColor.warning)
      }
      if let expiry = node.info.billingExpiresAt {
        let days = AsterFormat.daysLeft(until: expiry)
        chip(
          String(format: L.text("billing.daysLeft"), days),
          tint: days < 14 ? AsterColor.offline : AsterColor.online)
      }
    }
  }

  private func chip(_ text: String, tint: Color) -> some View {
    Text(text)
      .font(AsterTypography.caption)
      .foregroundStyle(tint)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
  }

  private var statLine: some View {
    HStack(spacing: AsterSpacing.sm) {
      iconStat("cpu", "\(Int(node.metrics.cpuUsage))%", AsterColor.chartPalette[0])
      iconStat("memorychip", "\(Int(node.metrics.memoryUsage))%", AsterColor.chartPalette[1])
      iconStat("internaldrive", "\(Int(node.metrics.diskUsage))%", AsterColor.chartPalette[3])
      iconStat(
        "bolt.fill",
        String(
          format: "%.2f | %.2f | %.2f", node.metrics.loadAverage, node.metrics.load5,
          node.metrics.load15),
        AsterColor.warning)
      Spacer(minLength: 0)
    }
  }

  private var networkLine: some View {
    let up = AsterFormat.rate(node.metrics.uploadBytesPerSecond)
    let down = AsterFormat.rate(node.metrics.downloadBytesPerSecond)
    return HStack(alignment: .top, spacing: AsterSpacing.md) {
      HStack(spacing: 4) {
        Image(systemName: "speedometer")
          .font(.caption)
          .foregroundStyle(AsterColor.chartPalette[2])
        VStack(alignment: .leading, spacing: 1) {
          Text("↑ \(up.value) \(up.unit)")
          Text("↓ \(down.value) \(down.unit)")
        }
      }
      HStack(spacing: 4) {
        Image(systemName: "arrow.up.arrow.down")
          .font(.caption)
          .foregroundStyle(AsterColor.chartPalette[4])
        VStack(alignment: .leading, spacing: 1) {
          Text("↑ \(AsterFormat.bytes(node.metrics.totalUploadBytes))")
          Text("↓ \(AsterFormat.bytes(node.metrics.totalDownloadBytes))")
        }
      }
      Spacer(minLength: 0)
    }
    .font(AsterTypography.caption.monospacedDigit())
    .foregroundStyle(AsterColor.foregroundPrimary.opacity(0.85))
  }

  private var footerLine: some View {
    HStack {
      if let expiry = node.info.billingExpiresAt {
        Text(
          "\(L.text("billing.expiryShort")): \(expiry.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))"
        )
      }
      Spacer()
      Text(AsterFormat.uptime(node.metrics.uptime))
    }
    .font(AsterTypography.caption)
    .foregroundStyle(AsterColor.foregroundSecondary)
    .lineLimit(1)
  }

  private func iconStat(_ symbol: String, _ value: String, _ tint: Color) -> some View {
    HStack(spacing: 3) {
      Image(systemName: symbol).font(.caption).foregroundStyle(tint)
      Text(value)
        .font(AsterTypography.caption.monospacedDigit())
        .foregroundStyle(AsterColor.foregroundPrimary)
        .lineLimit(1)
    }
  }
}

#Preview {
  ScrollView {
    NodesDisplay(nodes: MockDataSource().loadNodes()).padding()
  }
  .background(AsterColor.background1)
  .frame(width: 1000, height: 700)
}
