import Charts
import SwiftUI

struct NodeDetailView: View {
  @Environment(MonitorStore.self) private var store
  let nodeID: UUID
  @State private var range: TimeRange = .hour
  @State private var section: DetailSection = .overview

  private enum DetailSection: String, CaseIterable, Identifiable {
    case overview, services
    var id: String { rawValue }
    var key: String { "services.tab.\(rawValue)" }
  }

  var body: some View {
    if let node = store.node(id: nodeID) {
      ScrollView {
        VStack(alignment: .leading, spacing: AsterSpacing.lg) {
          detailHeader(node)
          if section == .services {
            NodeServicesView(nodeID: nodeID)
          } else {
            overview(node)
          }
        }.padding(AsterSpacing.lg)
      }
      .navigationTitle(node.info.name).toolbar {
        ToolbarItem { StatusDot(status: node.info.status) }
      }
      .task(id: range) { await store.loadHistory(for: nodeID, hours: range.hours) }
      .task(id: nodeID) {
        while !Task.isCancelled {
          await store.loadSensors(for: nodeID)
          try? await Task.sleep(for: .seconds(15))
        }
      }
      .overlay(alignment: .bottom) {
        if let message = store.historyError(for: nodeID) {
          HStack {
            Text(message)
              .font(AsterTypography.caption)
              .lineLimit(1)
            Button(L.text("settings.test")) {
              store.clearHistoryError(for: nodeID)
              Task { await store.loadHistory(for: nodeID, hours: range.hours) }
            }
          }
          .padding(AsterSpacing.sm)
          .background(.thinMaterial, in: Capsule())
          .padding()
        }
      }
    } else {
      EmptyStateView(
        symbol: "server.rack", title: L.text("node.missing.title"),
        message: L.text("node.missing.message"))
    }
  }

  @ViewBuilder private func overview(_ node: NodeSnapshot) -> some View {
          infoCard(node)
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
              VStack(alignment: .leading, spacing: AsterSpacing.sm) {
                Text(L.text("chart.storage")).font(AsterTypography.sectionTitle)
                ProgressBarMetric(value: node.metrics.diskUsage / 100, label: L.text("metric.disk"))
                detailLine(
                  L.text("metric.disk"),
                  "\(AsterFormat.bytes(node.metrics.diskUsedBytes)) / \(AsterFormat.bytes(node.metrics.diskTotalBytes))"
                )
                detailLine(
                  L.text("metric.memory"),
                  "\(AsterFormat.bytes(node.metrics.memoryUsedBytes)) / \(AsterFormat.bytes(node.metrics.memoryTotalBytes))"
                )
                detailLine(
                  L.text("metric.swap"),
                  node.metrics.swapTotalBytes > 0
                    ? "\(AsterFormat.bytes(node.metrics.swapUsedBytes)) / \(AsterFormat.bytes(node.metrics.swapTotalBytes))"
                    : L.text("swap.off"))
                detailLine(
                  L.text("table.traffic"),
                  "↑ \(AsterFormat.bytes(node.metrics.totalUploadBytes))   ↓ \(AsterFormat.bytes(node.metrics.totalDownloadBytes))"
                )
                detailLine(
                  L.text("table.load"),
                  String(
                    format: "%.2f / %.2f / %.2f", node.metrics.loadAverage, node.metrics.load5,
                    node.metrics.load15))
                detailLine(L.text("metric.connections"), "\(node.metrics.connectionCount)")
                detailLine(L.text("metric.processes"), "\(node.metrics.processCount)")
                if node.metrics.stealPercent > 0.05 {
                  detailLine(
                    L.text("metric.steal"),
                    String(format: "%.1f%%", node.metrics.stealPercent))
                }
              }
            }
            if let sensors = store.sensorsByNode[nodeID] ?? nil, sensors.available {
              SensorsCard(sensors: sensors)
            }
          }
  }

  /// Identity card in the visual language of desktop system-info dashboards:
  /// muted label above a bold value, one cell per fact.
  private func infoCard(_ node: NodeSnapshot) -> some View {
    let meta = store.metaByMachine[nodeID]
    return GlassCard {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 160), spacing: AsterSpacing.md, alignment: .leading)],
        alignment: .leading, spacing: AsterSpacing.sm
      ) {
        infoCell(L.text("meta.hostname"), meta?.hostname ?? node.info.name)
        infoCell(L.text("meta.os"), meta?.os ?? node.info.operatingSystem)
        infoCell(L.text("meta.kernel"), meta?.kernel ?? "—")
        infoCell(L.text("meta.arch"), meta?.architecture ?? "—")
        infoCell(
          L.text("meta.cpu"),
          meta.map { String(format: L.text("hardware.format"), $0.cpuModel, $0.cpuCores) }
            ?? (node.info.hardware.isEmpty ? "—" : node.info.hardware))
        infoCell(L.text("meta.agent"), meta.map { "v\($0.agentVersion)" } ?? "—")
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func infoCell(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(AsterTypography.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
      Text(value)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  private func detailLine(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title)
        .font(AsterTypography.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
      Spacer()
      Text(value)
        .font(AsterTypography.caption.monospacedDigit())
        .foregroundStyle(AsterColor.foregroundPrimary)
    }
  }

  private func detailHeader(_ node: NodeSnapshot) -> some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 8) {
          Text(node.info.flag).font(.title2)
          Text(node.info.name).font(AsterTypography.pageTitle)
          OSBadge(osID: node.info.operatingSystem)
        }
        Text(node.info.region)
          .foregroundStyle(AsterColor.foregroundSecondary)
        HStack { ForEach(node.info.tags, id: \.self) { TagChip(text: $0) } }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: AsterSpacing.xs) {
        Text(AsterFormat.uptime(node.metrics.uptime))
          .font(AsterTypography.metric).foregroundStyle(AsterColor.foregroundSecondary)
        Picker(L.text("services.tab.overview"), selection: $section) {
          ForEach(DetailSection.allCases) { Text(L.text($0.key)).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 170)
        .labelsHidden()
      }
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

/// Thermal card: fan rows plus temperature groups (max per group, colored by
/// severity). Shown only when the agent reports real sensors — VMs never do.
struct SensorsCard: View {
  let sensors: AgentSensors

  var body: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: AsterSpacing.sm) {
        Text(L.text("sensors.title")).font(AsterTypography.sectionTitle)
        ForEach(sensors.fans) { fan in
          HStack(spacing: AsterSpacing.xs) {
            Image(systemName: "fan.fill")
              .font(.system(size: 11))
              .foregroundStyle(AsterColor.chartPalette[1])
            Text(fan.label).font(AsterTypography.label)
            Spacer()
            Text(verbatim: "\(Int(fan.rpm)) RPM")
              .font(AsterTypography.metric)
          }
        }
        if !sensors.temps.isEmpty {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130), spacing: AsterSpacing.xs)],
            spacing: AsterSpacing.xs
          ) {
            ForEach(sensors.groupedTemps, id: \.group) { group in
              VStack(alignment: .leading, spacing: 2) {
                HStack {
                  Text(L.text(group.group))
                    .font(AsterTypography.caption)
                    .foregroundStyle(AsterColor.foregroundSecondary)
                  Spacer()
                  Text(verbatim: "×\(group.count)")
                    .font(.system(size: 8.5).monospacedDigit())
                    .foregroundStyle(AsterColor.foregroundSecondary.opacity(0.6))
                }
                Text(verbatim: "\(Int(group.max.rounded()))°C")
                  .font(AsterTypography.metricMedium)
                  .foregroundStyle(temperatureColor(group.max))
              }
              .padding(AsterSpacing.xs)
              .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: AsterRadius.control, style: .continuous))
            }
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func temperatureColor(_ celsius: Double) -> Color {
    switch celsius {
    case ..<60: AsterColor.foregroundPrimary
    case ..<80: AsterColor.warning
    default: AsterColor.offline
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
  let store = MonitorStore.preview
  return NavigationStack {
    NodeDetailView(nodeID: store.nodes[0].id).environment(store)
  }.frame(width: 1000, height: 700)
}
