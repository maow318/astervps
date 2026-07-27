import SwiftUI

/// Komari-style information-dense table. Fixed column widths keep header and
/// rows aligned; the name column absorbs remaining space.
struct NodeTableView: View {
  let nodes: [NodeSnapshot]

  var body: some View {
    VStack(spacing: 6) {
      header
      ForEach(nodes) { node in
        NodeTableRow(node: node)
      }
    }
  }

  private var header: some View {
    HStack(spacing: AsterSpacing.sm) {
      headerCell(L.text("table.node"), width: nil)
        .frame(maxWidth: .infinity, alignment: .leading)
      headerCell(L.text("metric.cpu"), width: ColumnWidths.cpu)
      headerCell(L.text("metric.memory"), width: ColumnWidths.memory)
      headerCell(L.text("metric.swap"), width: ColumnWidths.swap)
      headerCell(L.text("metric.disk"), width: ColumnWidths.disk)
      headerCell(L.text("table.network"), width: ColumnWidths.network)
      headerCell(L.text("table.traffic"), width: ColumnWidths.traffic)
      headerCell(L.text("table.load"), width: ColumnWidths.load)
    }
    .padding(.horizontal, AsterSpacing.md)
  }

  private func headerCell(_ title: String, width: CGFloat?) -> some View {
    Text(title)
      .font(AsterTypography.caption)
      .foregroundStyle(AsterColor.foregroundSecondary)
      .frame(width: width, alignment: .leading)
  }
}

private struct NodeTableRow: View {
  let node: NodeSnapshot

  var body: some View {
    NavigationLink(value: node.id) {
      GlassCard {
        HStack(spacing: AsterSpacing.sm) {
          identity.frame(maxWidth: .infinity, alignment: .leading)
          usageCell(
            percent: node.metrics.cpuUsage, total: nil, tint: AsterColor.chartPalette[0],
            width: NodeTableView.ColumnWidths.cpu)
          usageCell(
            percent: node.metrics.memoryUsage, total: node.metrics.memoryTotalBytes,
            tint: AsterColor.chartPalette[1], width: NodeTableView.ColumnWidths.memory)
          swapCell
          usageCell(
            percent: node.metrics.diskUsage, total: node.metrics.diskTotalBytes,
            tint: AsterColor.chartPalette[3], width: NodeTableView.ColumnWidths.disk)
          pairCell(
            up: AsterFormat.rate(node.metrics.uploadBytesPerSecond),
            down: AsterFormat.rate(node.metrics.downloadBytesPerSecond),
            width: NodeTableView.ColumnWidths.network)
          trafficCell
          loadCell
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 5) {
        StatusDot(status: node.info.status, diameter: 7)
        Text(node.info.flag)
        Text(node.info.name)
          .font(AsterTypography.sectionTitle)
          .foregroundStyle(AsterColor.foregroundPrimary)
          .lineLimit(1)
        OSBadge(osID: node.info.operatingSystem, size: 11)
      }
      HStack(spacing: 6) {
        if let price = node.info.billingPrice {
          Text(price)
            .font(AsterTypography.caption)
            .foregroundStyle(AsterColor.warning)
        }
        if let expiry = node.info.billingExpiresAt {
          let days = AsterFormat.daysLeft(until: expiry)
          Text(String(format: L.text("billing.daysLeft"), days))
            .font(AsterTypography.caption)
            .foregroundStyle(days < 14 ? AsterColor.offline : AsterColor.foregroundSecondary)
        }
        Text(AsterFormat.uptime(node.metrics.uptime))
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
          .lineLimit(1)
      }
    }
  }

  private func usageCell(percent: Double, total: Double?, tint: Color, width: CGFloat)
    -> some View
  {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Text("\(Int(percent))%")
          .font(AsterTypography.label.monospacedDigit())
        if let total, total > 0 {
          Text(AsterFormat.bytes(total))
            .font(AsterTypography.caption)
            .foregroundStyle(AsterColor.foregroundSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
      }
      miniBar(percent: percent, tint: tint)
    }
    .frame(width: width, alignment: .leading)
  }

  private var swapCell: some View {
    Group {
      if node.metrics.swapTotalBytes > 0 {
        usageCell(
          percent: node.metrics.swapUsage, total: node.metrics.swapTotalBytes,
          tint: AsterColor.chartPalette[4], width: NodeTableView.ColumnWidths.swap)
      } else {
        Text(L.text("swap.off"))
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
          .frame(width: NodeTableView.ColumnWidths.swap, alignment: .leading)
      }
    }
  }

  private var trafficCell: some View {
    pairCell(
      up: split(AsterFormat.bytes(node.metrics.totalUploadBytes)),
      down: split(AsterFormat.bytes(node.metrics.totalDownloadBytes)),
      width: NodeTableView.ColumnWidths.traffic)
  }

  private func split(_ formatted: String) -> (value: String, unit: String) {
    let parts = formatted.split(separator: " ")
    guard parts.count == 2 else { return (formatted, "") }
    return (String(parts[0]), String(parts[1]))
  }

  private func pairCell(
    up: (value: String, unit: String), down: (value: String, unit: String), width: CGFloat
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("↑ \(up.value) \(up.unit)")
      Text("↓ \(down.value) \(down.unit)")
    }
    .font(AsterTypography.caption.monospacedDigit())
    .foregroundStyle(AsterColor.foregroundPrimary.opacity(0.85))
    .lineLimit(1)
    .frame(width: width, alignment: .leading)
  }

  private var loadCell: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(String(format: "%.2f", node.metrics.loadAverage))
      Text(String(format: "%.2f", node.metrics.load5))
      Text(String(format: "%.2f", node.metrics.load15))
    }
    .font(AsterTypography.caption.monospacedDigit())
    .foregroundStyle(AsterColor.foregroundSecondary)
    .frame(width: NodeTableView.ColumnWidths.load, alignment: .leading)
  }

  private func miniBar(percent: Double, tint: Color) -> some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(AsterColor.foregroundSecondary.opacity(0.13))
        Capsule().fill(percent >= 90 ? AsterColor.offline : tint)
          .frame(width: proxy.size.width * min(max(percent / 100, 0), 1))
      }
    }
    .frame(height: 4)
  }
}

extension NodeTableView {
  fileprivate enum ColumnWidths {
    static let cpu: CGFloat = 92
    static let memory: CGFloat = 112
    static let swap: CGFloat = 80
    static let disk: CGFloat = 112
    static let network: CGFloat = 104
    static let traffic: CGFloat = 108
    static let load: CGFloat = 62
  }
}

#Preview {
  ScrollView {
    NodeTableView(nodes: MockDataSource().loadNodes()).padding()
  }
  .background(AsterColor.background1)
  .frame(width: 1100, height: 720)
}
