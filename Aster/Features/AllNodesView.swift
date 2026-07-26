import SwiftUI

struct AllNodesView: View {
  @Environment(MonitorStore.self) private var store
  @State private var query = ""
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          NodeGrid(
            nodes: store.nodes.filter {
              query.isEmpty || $0.info.name.localizedCaseInsensitiveContains(query)
                || $0.info.region.localizedCaseInsensitiveContains(query)
            }
          ).padding(AsterSpacing.lg)
        }
        StatusBar()
      }.navigationTitle(L.text("sidebar.nodes")).searchable(
        text: $query, prompt: L.text("search.nodes")
      ).navigationDestination(for: UUID.self) { id in
        if store.node(id: id) != nil { NodeDetailView(nodeID: id) }
      }
    }
  }
}

struct GroupNodesView: View {
  @Environment(MonitorStore.self) private var store
  let groupID: UUID
  var body: some View {
    let group = store.groups.first { $0.id == groupID }
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          NodeGrid(nodes: store.nodes.filter { $0.info.groupID == groupID }).padding(
            AsterSpacing.lg)
        }
        StatusBar()
      }.navigationTitle(group?.name ?? L.text("sidebar.groups")).navigationDestination(
        for: UUID.self
      ) { NodeDetailView(nodeID: $0) }
    }
  }
}

#Preview { AllNodesView().environment(MonitorStore()).frame(width: 1000, height: 700) }
