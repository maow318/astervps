import SwiftUI

enum SidebarDestination: Hashable {
  case overview, allNodes
  case group(UUID)
  case alerts, settings
}

struct MainSplitView: View {
  @Environment(MonitorStore.self) private var store
  @State private var selection: SidebarDestination? = .overview
  var body: some View {
    @Bindable var store = store
    NavigationSplitView {
      List(selection: $selection) {
        Section {
          Label(L.text("sidebar.overview"), systemImage: "rectangle.3.group.fill").tag(
            SidebarDestination.overview)
          Label(L.text("sidebar.nodes"), systemImage: "server.rack").tag(
            SidebarDestination.allNodes)
        }
        Section(L.text("sidebar.groups")) {
          ForEach(store.groups) { group in
            Label(group.name, systemImage: group.symbol).tag(SidebarDestination.group(group.id))
          }
        }
        Section {
          Label(L.text("sidebar.alerts"), systemImage: "bell").tag(SidebarDestination.alerts)
          Label(L.text("sidebar.settings"), systemImage: "gearshape").tag(
            SidebarDestination.settings)
        }
      }.listStyle(.sidebar).navigationTitle(L.text("app.name"))
    } detail: {
      destinationView
    }
    .navigationSplitViewStyle(.balanced)
    .sheet(isPresented: $store.isAddMachinePresented) {
      AddMachineSheet().environment(store)
    }
  }
  @ViewBuilder private var destinationView: some View {
    switch selection ?? .overview {
    case .overview: OverviewView()
    case .allNodes: AllNodesView()
    case .group(let id): GroupNodesView(groupID: id)
    case .alerts: AlertsView()
    case .settings: SettingsView()
    }
  }
}

#Preview { MainSplitView().environment(MonitorStore.preview) }
