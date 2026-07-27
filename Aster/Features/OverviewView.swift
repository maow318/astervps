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
            FleetSummaryBar(nodes: store.visibleNodes)
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
