import SwiftUI

struct AlertsView: View {
  @Environment(MonitorStore.self) private var store
  var body: some View {
    Group {
      if store.alerts.isEmpty {
        EmptyStateView(
          symbol: "bell.slash", title: L.text("alerts.empty.title"),
          message: L.text("alerts.empty.message"))
      } else {
        List(store.alerts) { alert in
          HStack {
            StatusDot(status: alert.severity)
            VStack(alignment: .leading) {
              Text(alert.title)
              Text(alert.date, style: .relative).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
    }.navigationTitle(L.text("sidebar.alerts"))
  }
}

#Preview { AlertsView().environment(MonitorStore()).frame(width: 600, height: 400) }
