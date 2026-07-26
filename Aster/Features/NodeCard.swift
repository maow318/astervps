import SwiftUI

struct NodeCard: View {
    let node: NodeSnapshot
    var body: some View {
        NavigationLink(value: node.id) {
            GlassCard {
                VStack(alignment: .leading, spacing: AsterSpacing.sm) {
                    HStack(alignment: .top) { VStack(alignment: .leading, spacing: 3) { HStack(spacing: 6) { Text(node.info.flag); Text(node.info.name).font(AsterTypography.sectionTitle).foregroundStyle(AsterColor.foregroundPrimary) }; Label(node.info.region, systemImage: "location.fill").font(AsterTypography.caption).foregroundStyle(AsterColor.foregroundSecondary) }; Spacer(); StatusDot(status: node.info.status) }
                    HStack(spacing: AsterSpacing.md) { MetricRing(value: node.metrics.cpuUsage, label: L.text("metric.cpu"), size: 70, tint: AsterColor.chartPalette[0]); MetricRing(value: node.metrics.memoryUsage, label: L.text("metric.memory"), size: 70, tint: AsterColor.chartPalette[1]); Spacer(); VStack(alignment: .trailing, spacing: 5) { MetricLabel(symbol: "arrow.down", value: String(format: "%.1f", node.metrics.downloadBytesPerSecond / 1_000_000), unit: "MB/s", tint: AsterColor.chartPalette[1]); MetricLabel(symbol: "arrow.up", value: String(format: "%.1f", node.metrics.uploadBytesPerSecond / 1_000_000), unit: "MB/s", tint: AsterColor.chartPalette[4]) } }
                    Sparkline(samples: node.history.download, tint: AsterColor.chartPalette[1])
                    HStack { Label(Duration.seconds(node.metrics.uptime).formatted(.units(allowed: [.days, .hours], width: .abbreviated)), systemImage: "clock").font(AsterTypography.caption).foregroundStyle(AsterColor.foregroundSecondary); Spacer(); ForEach(node.info.tags.prefix(2), id: \.self) { TagChip(text: $0) } }
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

#Preview { NodeCard(node: MockDataSource().loadNodes()[0]).frame(width: 330).padding().background(AsterColor.background1) }
