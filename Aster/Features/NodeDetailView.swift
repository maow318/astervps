import Charts
import SwiftUI

struct NodeDetailView: View {
  @Environment(MonitorStore.self) private var store
  let nodeID: UUID
  @State private var range: TimeRange = .hour
  var body: some View {
    if let node = store.node(id: nodeID) {
      ScrollView {
        VStack(alignment: .leading, spacing: AsterSpacing.lg) {
          detailHeader(node)
          metricRings(node)
          Picker(L.text("history.range"), selection: $range) {
            ForEach(TimeRange.allCases) { Text(L.text($0.key)).tag($0) }
          }.pickerStyle(.segmented).frame(maxWidth: 360)
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 360), spacing: AsterSpacing.md)],
            spacing: AsterSpacing.md
          ) {
            DetailChart(
              title: L.text("chart.cpuMemory"),
              series: [
                (L.text("metric.cpu"), node.history.cpu, AsterColor.chartPalette[0]),
                (L.text("metric.memory"), node.history.memory, AsterColor.chartPalette[1]),
              ], unit: "%")
            DetailChart(
              title: L.text("chart.network"),
              series: [
                (L.text("metric.download"), node.history.download, AsterColor.chartPalette[1]),
                (L.text("metric.upload"), node.history.upload, AsterColor.chartPalette[4]),
              ], unit: "MB/s")
            DetailChart(
              title: L.text("chart.diskIO"),
              series: [
                (L.text("metric.read"), node.history.diskRead, AsterColor.chartPalette[2]),
                (L.text("metric.write"), node.history.diskWrite, AsterColor.chartPalette[3]),
              ], unit: "MB/s")
            GlassCard {
              VStack(alignment: .leading, spacing: AsterSpacing.md) {
                Text(L.text("chart.storage")).font(AsterTypography.sectionTitle)
                ProgressBarMetric(value: node.metrics.diskUsage / 100, label: L.text("metric.disk"))
                MetricLabel(
                  symbol: "point.3.connected.trianglepath.dotted",
                  value: "\(node.metrics.connectionCount)", unit: L.text("metric.connections"))
                MetricLabel(
                  symbol: "cpu", value: "\(node.metrics.processCount)",
                  unit: L.text("metric.processes"))
              }
            }
          }
        }.padding(AsterSpacing.lg)
      }
      .navigationTitle(node.info.name).toolbar {
        ToolbarItem { StatusDot(status: node.info.status) }
      }
      .task(id: range) { await store.loadHistory(for: nodeID, hours: range.hours) }
    } else {
      EmptyStateView(
        symbol: "server.rack", title: L.text("node.missing.title"),
        message: L.text("node.missing.message"))
    }
  }
  private func detailHeader(_ node: NodeSnapshot) -> some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text(node.info.flag).font(.title2)
          Text(node.info.name).font(AsterTypography.pageTitle)
        }
        Label("\(node.info.region) · \(node.info.operatingSystem)", systemImage: "location.fill")
          .foregroundStyle(AsterColor.foregroundSecondary)
        HStack { ForEach(node.info.tags, id: \.self) { TagChip(text: $0) } }
      }
      Spacer()
      Text(
        Duration.seconds(node.metrics.uptime).formatted(
          .units(allowed: [.days, .hours, .minutes], width: .abbreviated))
      ).font(AsterTypography.metric).foregroundStyle(AsterColor.foregroundSecondary)
    }
  }
  private func metricRings(_ node: NodeSnapshot) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: AsterSpacing.lg) {
        MetricRing(
          value: node.metrics.cpuUsage, label: L.text("metric.cpu"),
          tint: AsterColor.chartPalette[0])
        MetricRing(
          value: node.metrics.memoryUsage, label: L.text("metric.memory"),
          tint: AsterColor.chartPalette[1])
        MetricRing(
          value: node.metrics.swapUsage, label: L.text("metric.swap"),
          tint: AsterColor.chartPalette[4])
        MetricRing(
          value: node.metrics.diskUsage, label: L.text("metric.disk"),
          tint: AsterColor.chartPalette[3])
      }
      HStack {
        MetricRing(value: node.metrics.cpuUsage, label: L.text("metric.cpu"))
        MetricRing(
          value: node.metrics.memoryUsage, label: L.text("metric.memory"),
          tint: AsterColor.chartPalette[1])
      }
    }
  }
}

private struct DetailChart: View {
  let title: String
  let series: [(String, [MetricSample], Color)]
  let unit: String
  var body: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: AsterSpacing.sm) {
        Text(title).font(AsterTypography.sectionTitle)
        Chart {
          ForEach(Array(series.enumerated()), id: \.offset) { _, item in
            ForEach(item.1) { sample in
              LineMark(x: .value("time", sample.date), y: .value("value", sample.value))
                .foregroundStyle(item.2).interpolationMethod(.linear).lineStyle(
                  StrokeStyle(lineWidth: 2))
            }
          }
        }.chartLegend(.hidden).chartYAxis { AxisMarks(position: .leading) }.frame(height: 185)
        HStack {
          ForEach(Array(series.enumerated()), id: \.offset) { _, item in
            Label(item.0, systemImage: "circle.fill").foregroundStyle(item.2).font(
              AsterTypography.caption)
          }
          Spacer()
          Text(unit).font(AsterTypography.caption).foregroundStyle(AsterColor.foregroundSecondary)
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    NodeDetailView(nodeID: MockDataSource().loadNodes()[0].id).environment(MonitorStore())
  }.frame(width: 1000, height: 700)
}
