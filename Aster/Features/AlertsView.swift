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
          AlertRow(alert: alert, nodeName: store.node(id: alert.nodeID)?.info.name ?? "—")
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
      }
    }
    .navigationTitle(L.text("sidebar.alerts"))
    .toolbar {
      if !store.alerts.isEmpty {
        ToolbarItem {
          Button(L.text("alerts.markRead"), systemImage: "checkmark.circle") {
            store.markAllAlertsRead()
          }
          .disabled(store.unreadAlertCount == 0)
        }
        ToolbarItem {
          Button(L.text("alerts.clear"), systemImage: "trash") {
            store.clearAlerts()
          }
        }
      }
    }
  }
}

private struct AlertRow: View {
  let alert: AlertItem
  let nodeName: String

  var body: some View {
    HStack(spacing: AsterSpacing.sm) {
      StatusDot(status: alert.severity, diameter: 8)
      VStack(alignment: .leading, spacing: 2) {
        Text(alert.title)
          .font(.system(size: 13, weight: alert.isRead ? .regular : .semibold, design: .rounded))
        HStack(spacing: AsterSpacing.xxs) {
          Text(nodeName)
          Text(verbatim: "·")
          Text(alert.date, style: .relative)
        }
        .font(AsterTypography.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
      }
      Spacer()
      if !alert.isRead {
        Circle().fill(AsterColor.accent).frame(width: 7, height: 7)
      }
    }
    .padding(AsterSpacing.sm)
    .background(
      Color.primary.opacity(alert.isRead ? 0.03 : 0.055),
      in: RoundedRectangle(cornerRadius: AsterRadius.control, style: .continuous))
  }
}

#Preview { AlertsView().environment(MonitorStore.preview).frame(width: 600, height: 400) }
