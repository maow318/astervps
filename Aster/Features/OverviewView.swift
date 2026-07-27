import SwiftUI

struct OverviewView: View {
  @Environment(MonitorStore.self) private var store
  @State private var country: String?

  private var filteredNodes: [NodeSnapshot] {
    guard let country else { return store.visibleNodes }
    return store.visibleNodes.filter { $0.info.countryCode == country }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: AsterSpacing.lg) {
            HeaderStatistics()
            CountryFilterBar(nodes: store.visibleNodes, selection: $country)
            if store.visibleNodes.isEmpty {
              VStack(spacing: AsterSpacing.md) {
                EmptyStateView(
                  symbol: "network", title: L.text("connection.unconfigured"),
                  message: L.text("machines.empty"))
                Button {
                  store.isAddMachinePresented = true
                } label: {
                  Label(L.text("add.title"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
              }
              .frame(maxWidth: .infinity)
            } else {
              NodesDisplay(nodes: filteredNodes)
            }
          }.padding(AsterSpacing.lg)
        }
        StatusBar()
      }
      .background(AsterColor.background1.opacity(0.65))
      .navigationTitle(L.text("overview.title"))
      .navigationDestination(for: UUID.self) { id in
        if let node = store.node(id: id) { NodeDetailView(nodeID: node.id) }
      }
    }
  }
}

private struct HeaderStatistics: View {
  @Environment(MonitorStore.self) private var store
  var body: some View {
    // A plain HStack with equal flexible widths: ViewThatFits could never
    // pick the horizontal variant because maxWidth-infinity cards report an
    // unbounded ideal width.
    HStack(spacing: AsterSpacing.sm) {
      stat(L.text("overview.nodes"), "\(store.visibleNodes.count)", "server.rack")
      stat(
        L.text("overview.availability"), "\(store.onlineCount)/\(store.visibleNodes.count)",
        "checkmark.circle")
      stat(L.text("overview.traffic"), totalTraffic, "arrow.left.arrow.right")
      stat(
        L.text("overview.load"),
        String(
          format: "%.2f",
          store.visibleNodes.map(\.metrics.loadAverage).reduce(0, +) / Double(max(store.visibleNodes.count, 1))),
        "gauge.with.dots.needle.50percent")
    }
  }

  private var totalTraffic: String {
    let total = store.visibleNodes.reduce(0.0) {
      $0 + $1.metrics.downloadBytesPerSecond + $1.metrics.uploadBytesPerSecond
    }
    let rate = AsterFormat.rate(total)
    return "\(rate.value) \(rate.unit)"
  }
  private func stat(_ title: String, _ value: String, _ symbol: String) -> some View {
    GlassCard {
      // Single container view: GlassCard's builder would otherwise style each
      // sibling as its own card.
      VStack(alignment: .leading, spacing: 6) {
        Label(title, systemImage: symbol).font(AsterTypography.caption).foregroundStyle(
          AsterColor.foregroundSecondary)
        Text(value).font(AsterTypography.metricLarge).foregroundStyle(AsterColor.foregroundPrimary)
          .contentTransition(.numericText())
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct NodeGrid: View {
  let nodes: [NodeSnapshot]
  private let columns = [GridItem(.adaptive(minimum: 285, maximum: 380), spacing: AsterSpacing.md)]
  var body: some View {
    LazyVGrid(columns: columns, spacing: AsterSpacing.md) {
      ForEach(nodes) {
        NodeCard(node: $0).transition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }.animation(AsterAnimation.gentle, value: nodes)
  }
}

struct StatusBar: View {
  @Environment(MonitorStore.self) private var store
  var body: some View {
    BottomStatusBar(
      summary: String(format: L.text("status.summary"), store.onlineCount, store.offlineCount)
    ) {
      HStack {
        StatusDot(status: store.connectionState.dotStatus, diameter: 7)
        Button {
          store.isAddMachinePresented = true
        } label: {
          Image(systemName: "plus")
        }.help(L.text("action.add"))
      }
    } trailing: {
      Button(action: {}) { Image(systemName: "magnifyingglass") }.help(L.text("action.search"))
      Button(action: {}) { Image(systemName: "clock.arrow.circlepath") }.help(
        L.text("action.history"))
      Button(action: {}) { Image(systemName: "questionmark.circle") }.help(L.text("action.help"))
    }
  }
}

#Preview { OverviewView().environment(MonitorStore.preview).frame(width: 1100, height: 750) }
