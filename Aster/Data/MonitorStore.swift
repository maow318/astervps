import Foundation
import Observation

@Observable
@MainActor
final class MonitorStore {
  var nodes: [NodeSnapshot]
  var groups: [NodeGroup]
  var alerts: [AlertItem]

  private var dataSource: any MonitorDataSource
  private var refreshTask: Task<Void, Never>?
  private var shouldRefreshHistory = false
  private var isWindowActive = true

  init(dataSource: any MonitorDataSource) {
    self.dataSource = dataSource
    nodes = dataSource.loadNodes()
    groups = dataSource.loadGroups()
    alerts = dataSource.loadAlerts()
    startRefreshLoop()
  }

  convenience init() {
    self.init(dataSource: MockDataSource())
  }

  func setWindowActive(_ isActive: Bool) {
    isWindowActive = isActive
  }

  func node(id: UUID) -> NodeSnapshot? {
    nodes.first { $0.id == id }
  }

  var connectionState: ConnectionState = .unconfigured

  var isDemoMode: Bool = true

  func restoreSavedConnectionIfNeeded() async {
    isDemoMode = ConnectionSettings.isDemoMode
    guard !isDemoMode, !ConnectionSettings.endpoint.isEmpty else { return }
    await connect(endpoint: ConnectionSettings.endpoint, token: KeychainStore.readToken())
  }

  func setDemoMode(_ enabled: Bool) {
    ConnectionSettings.isDemoMode = enabled
    isDemoMode = enabled
    if enabled {
      (dataSource as? AsterAgentDataSource)?.stopLiveUpdates()
      dataSource = MockDataSource()
      nodes = dataSource.loadNodes()
      groups = dataSource.loadGroups()
      alerts = dataSource.loadAlerts()
      connectionState = .unconfigured
    }
  }

  func connect(endpoint: String, token: String?) async {
    connectionState = .connecting
    do {
      let source = try AsterAgentDataSource(endpoint: endpoint, token: token ?? "")
      let dashboard = try await source.loadDashboard()
      dataSource = source
      nodes = dashboard.nodes
      groups = dashboard.groups
      alerts = dashboard.alerts
      isDemoMode = false
      ConnectionSettings.endpoint = endpoint
      ConnectionSettings.isDemoMode = false
      connectionState = .connected
      source.startLiveUpdates()
    } catch {
      connectionState = .failed(error.localizedDescription)
    }
  }

  func testConnection(endpoint: String, token: String?) async -> Result<Void, Error> {
    do {
      let source = try AsterAgentDataSource(endpoint: endpoint, token: token ?? "")
      try await source.testConnection()
      return .success(())
    } catch {
      return .failure(error)
    }
  }

  func loadHistory(for nodeID: UUID, hours: Int) async {
    guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
    if let source = dataSource as? MockDataSource {
      nodes[index].history = source.history(for: nodes[index], hours: hours)
      return
    }
    guard let source = dataSource as? AsterAgentDataSource else { return }
    do {
      nodes[index].history = try await source.loadHistory(for: nodes[index].info, hours: hours)
    } catch {
      historyErrorByNodeID[nodeID] = error.localizedDescription
    }
  }

  var historyErrorByNodeID: [UUID: String] = [:]

  func historyError(for nodeID: UUID) -> String? { historyErrorByNodeID[nodeID] }

  func clearHistoryError(for nodeID: UUID) { historyErrorByNodeID[nodeID] = nil }

  var onlineCount: Int {
    nodes.filter { $0.info.status == .online }.count
  }

  var offlineCount: Int {
    nodes.filter { $0.info.status == .offline }.count
  }

  private func startRefreshLoop() {
    refreshTask = Task { [weak self] in
      guard let self else { return }

      while !Task.isCancelled {
        let interval: UInt64 = self.isWindowActive ? 5_000_000_000 : 30_000_000_000
        try? await Task.sleep(nanoseconds: interval)

        guard !Task.isCancelled else { return }
        self.refreshMetrics()
      }
    }
  }

  private func refreshMetrics() {
    guard isDemoMode else { return }
    let includeHistory = shouldRefreshHistory
    let refreshedNodes = dataSource.refresh(nodes: nodes, includeHistory: includeHistory)

    for refreshedNode in refreshedNodes {
      guard let index = nodes.firstIndex(where: { $0.id == refreshedNode.id }) else { continue }
      nodes[index].metrics = refreshedNode.metrics
      nodes[index].info.status = refreshedNode.info.status

      if includeHistory {
        nodes[index].history = refreshedNode.history
      }
    }

    shouldRefreshHistory.toggle()
  }

  private func applyRealtimeSnapshots(_ snapshots: [NodeSnapshot]) {
    for snapshot in snapshots {
      guard let index = nodes.firstIndex(where: { $0.info.serverID == snapshot.info.serverID })
      else { continue }
      nodes[index].metrics = snapshot.metrics
      nodes[index].info.status = snapshot.info.status
    }
  }
}
