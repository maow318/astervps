import SwiftUI

enum SidebarDestination: Hashable {
  case overview, globe, billing, machines
  case group(UUID)
  case alerts, settings
}

struct MainSplitView: View {
  @Environment(MonitorStore.self) private var store
  @State private var selection: SidebarDestination? = MainSplitView.initialSelection

  /// DEBUG-only launch hook (`-asterPage globe`) so headless runs can land on
  /// a specific page for screenshots.
  private static var initialSelection: SidebarDestination {
    #if DEBUG
      switch UserDefaults.standard.string(forKey: "asterPage") {
      case "globe": return .globe
      case "billing": return .billing
      case "machines": return .machines
      default: return .overview
      }
    #else
      return .overview
    #endif
  }
  var body: some View {
    @Bindable var store = store
    NavigationSplitView {
      List(selection: $selection) {
        Section {
          Label(L.text("sidebar.overview"), systemImage: "rectangle.3.group.fill").tag(
            SidebarDestination.overview)
          Label(L.text("sidebar.globe"), systemImage: "globe.asia.australia.fill").tag(
            SidebarDestination.globe)
          Label(L.text("sidebar.billing"), systemImage: "creditcard").tag(
            SidebarDestination.billing)
          Label(L.text("settings.machines"), systemImage: "server.rack").tag(
            SidebarDestination.machines)
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
    case .globe: GlobePage()
    case .billing: BillingPage()
    case .machines: MachinesView()
    case .group(let id): GroupNodesView(groupID: id)
    case .alerts: AlertsView()
    case .settings: SettingsView()
    }
  }
}

#Preview { MainSplitView().environment(MonitorStore.preview) }
