import SwiftUI

enum NodeDisplayMode: String, CaseIterable, Identifiable {
  case grid, table, compact

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .grid: "square.grid.2x2"
    case .table: "tablecells"
    case .compact: "list.bullet"
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
    LazyVStack(spacing: 6) {
      ForEach(nodes) { node in
        NodeCompactRow(node: node)
      }
    }
  }
}

/// One-line summary row: identity on the left, key percentages and network
/// rates on the right.
struct NodeCompactRow: View {
  let node: NodeSnapshot

  var body: some View {
    NavigationLink(value: node.id) {
      GlassCard {
        HStack(spacing: AsterSpacing.sm) {
          StatusDot(status: node.info.status, diameter: 8)
          Text(node.info.flag)
          Text(node.info.name)
            .font(AsterTypography.sectionTitle)
            .foregroundStyle(AsterColor.foregroundPrimary)
            .lineLimit(1)
          OSBadge(osID: node.info.operatingSystem, size: 12)
          Text(node.info.region)
            .font(AsterTypography.caption)
            .foregroundStyle(AsterColor.foregroundSecondary)
            .lineLimit(1)
          Spacer()
          percent("cpu", node.metrics.cpuUsage, AsterColor.chartPalette[0])
          percent("memorychip", node.metrics.memoryUsage, AsterColor.chartPalette[1])
          percent("internaldrive", node.metrics.diskUsage, AsterColor.chartPalette[3])
          rates
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func percent(_ symbol: String, _ value: Double, _ tint: Color) -> some View {
    HStack(spacing: 3) {
      Image(systemName: symbol).font(.caption).foregroundStyle(tint)
      Text("\(Int(value))%")
        .font(AsterTypography.label.monospacedDigit())
        .frame(width: 36, alignment: .trailing)
    }
  }

  private var rates: some View {
    let up = AsterFormat.rate(node.metrics.uploadBytesPerSecond)
    let down = AsterFormat.rate(node.metrics.downloadBytesPerSecond)
    return Text("↑\(up.value) \(up.unit)  ↓\(down.value) \(down.unit)")
      .font(AsterTypography.caption.monospacedDigit())
      .foregroundStyle(AsterColor.foregroundSecondary)
      .frame(width: 170, alignment: .trailing)
      .lineLimit(1)
  }
}

#Preview {
  ScrollView {
    NodesDisplay(nodes: MockDataSource().loadNodes()).padding()
  }
  .background(AsterColor.background1)
  .frame(width: 1000, height: 700)
}
