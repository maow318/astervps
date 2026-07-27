import SwiftUI

struct NodeCard: View {
  let node: NodeSnapshot

  var body: some View {
    NavigationLink(value: node.id) {
      GlassCard {
        VStack(alignment: .leading, spacing: AsterSpacing.sm) {
          headerRow
          metricsRow
          ProgressBarMetric(value: node.metrics.diskUsage / 100, label: L.text("metric.disk"))
          trendSection
          footerRow
        }
      }.contentShape(Rectangle())
    }.buttonStyle(.plain)
  }

  private var headerRow: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(node.info.flag)
          Text(node.info.name).font(AsterTypography.sectionTitle).foregroundStyle(
            AsterColor.foregroundPrimary)
        }
        Text(node.info.region)
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
        if !node.info.hardware.isEmpty {
          Text(node.info.hardware)
            .font(AsterTypography.caption)
            .foregroundStyle(AsterColor.foregroundSecondary.opacity(0.8))
            .lineLimit(1)
        }
      }
      Spacer()
      HStack(spacing: 6) {
        OSBadge(osID: node.info.operatingSystem)
        StatusDot(status: node.info.status)
      }
    }
  }

  private var metricsRow: some View {
    HStack(spacing: AsterSpacing.md) {
      MetricRing(
        value: node.metrics.cpuUsage, label: L.text("metric.cpu"), size: 70,
        tint: AsterColor.chartPalette[0])
      MetricRing(
        value: node.metrics.memoryUsage, label: L.text("metric.memory"), size: 70,
        tint: AsterColor.chartPalette[1])
      Spacer()
      VStack(alignment: .trailing, spacing: 5) {
        let down = AsterFormat.rate(node.metrics.downloadBytesPerSecond)
        let up = AsterFormat.rate(node.metrics.uploadBytesPerSecond)
        MetricLabel(
          symbol: "arrow.down", value: down.value, unit: down.unit,
          tint: AsterColor.chartPalette[1])
        MetricLabel(
          symbol: "arrow.up", value: up.value, unit: up.unit,
          tint: AsterColor.chartPalette[4])
      }
    }
  }

  private var trendSection: some View {
    VStack(alignment: .leading, spacing: 2) {
      Label(L.text("card.trend"), systemImage: "arrow.down.circle")
        .font(AsterTypography.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
      Sparkline(samples: node.history.download, tint: AsterColor.chartPalette[1])
    }
  }

  private var footerRow: some View {
    HStack {
      Text(AsterFormat.uptime(node.metrics.uptime))
        .font(AsterTypography.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
      if let expiry = node.info.billingExpiresAt {
        let days = AsterFormat.daysLeft(until: expiry)
        Text(String(format: L.text("billing.daysLeft"), days))
          .font(AsterTypography.caption)
          .foregroundStyle(days < 14 ? AsterColor.offline : AsterColor.warning)
      }
      Spacer()
      ForEach(node.info.tags.prefix(2), id: \.self) { TagChip(text: $0) }
    }
  }
}

#Preview {
  NodeCard(node: MockDataSource().loadNodes()[0]).frame(width: 330).padding().background(
    AsterColor.background1)
}
