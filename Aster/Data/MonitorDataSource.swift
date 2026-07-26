import Foundation

/// Boundary for Komari networking. Replace MockDataSource with a URLSession-backed implementation later.
@MainActor
protocol MonitorDataSource: AnyObject {
  func loadNodes() -> [NodeSnapshot]
  func loadGroups() -> [NodeGroup]
  func loadAlerts() -> [AlertItem]
  /// `includeHistory` is false on most ticks so chart data is not continuously re-rendered.
  func refresh(nodes: [NodeSnapshot], includeHistory: Bool) -> [NodeSnapshot]
}
