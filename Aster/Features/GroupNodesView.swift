import SwiftUI

struct GroupNodesView: View {
  @Environment(MonitorStore.self) private var store
  let groupID: UUID
  var body: some View {
    let group = store.groups.first { $0.id == groupID }
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          NodesDisplay(nodes: store.visibleNodes.filter { $0.info.groupID == groupID }).padding(
            AsterSpacing.lg)
        }
        StatusBar()
      }.navigationTitle(group?.name ?? L.text("sidebar.groups")).navigationDestination(
        for: UUID.self
      ) { NodeDetailView(nodeID: $0) }
    }
  }
}

#Preview {
  GroupNodesView(groupID: UUID()).environment(MonitorStore.preview)
    .frame(width: 900, height: 600)
}
