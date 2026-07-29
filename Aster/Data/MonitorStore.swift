import Foundation
import Observation

/// Orchestrates the fleet of configured agent machines. Each machine gets its
/// own AgentClient; one machine failing never affects the others.
/// Node identity: NodeInfo.id == MachineConfig.id.
@Observable
@MainActor
final class MonitorStore {
  var nodes: [NodeSnapshot] = []
  var groups: [NodeGroup] = []
  var alerts: [AlertItem] = []
  var machines: [MachineConfig] = []
  var machineStates: [UUID: ConnectionState] = [:]
  var isAddMachinePresented = false
  var historyErrorByNodeID: [UUID: String] = [:]

  var clients: [UUID: AgentClient] = [:]
  var metaByMachine: [UUID: AgentMeta] = [:]
  let historyStore = HistoryStore()
  var refreshTask: Task<Void, Never>?
  var isWindowActive = true
  var isPolling = false
  var lastHistorySync: [UUID: Date] = [:]
  var detailHours: [UUID: Int] = [:]
  /// Service inspection results, fetched on demand while the services tab is
  /// visible (see MonitorStoreServices.swift).
  var servicesByNode: [UUID: ServicesState] = [:]
  /// Per-node alert bookkeeping (thresholds, cooldowns; see MonitorStoreAlerts.swift).
  var alertRuntime: [UUID: AlertRuntime] = [:]
  /// Top-process snapshots for the menu-bar hover popover; nil value means the
  /// agent predates /v1/processes.
  var processesByNode: [UUID: [AgentProcess]?] = [:]
  var processesFetchedAt: [UUID: Date] = [:]
  /// Thermal sensors (nil = agent too old or endpoint failed; available=false
  /// means "a VM with nothing to report" — both hide the card).
  var sensorsByNode: [UUID: AgentSensors?] = [:]
  var sensorsFetchedAt: [UUID: Date] = [:]
  /// Sidebar groups derive from machine group names (see extension).
  var groupIDByName: [String: UUID] = [:]

  init() {
    startRefreshLoop()
  }

  func bootstrap() async {
    MachineStore.migrateLegacyIfNeeded()
    restoreAlerts()
    machines = MachineStore.load()
    #if DEBUG
      applyDebugLaunchArguments()
    #endif
    processAutoRenewals()
    rebuildGroups()
    activateMachines()
    await pollAgents()
    for machine in machines {
      ensureGeo(for: machine.id)
    }
  }

  /// Nodes not marked hidden; what the list pages render.
  var visibleNodes: [NodeSnapshot] {
    nodes.filter { node in
      !(machines.first { $0.id == node.id }?.hidden ?? false)
    }
  }

  func setWindowActive(_ isActive: Bool) {
    let wasActive = isWindowActive
    isWindowActive = isActive
    // Refresh immediately on refocus instead of finishing a 30s background
    // sleep with stale data on screen.
    if isActive && !wasActive {
      Task { await pollAgents() }
    }
  }

  func node(id: UUID) -> NodeSnapshot? {
    nodes.first { $0.id == id }
  }

  var onlineCount: Int {
    visibleNodes.filter { $0.info.status == .online }.count
  }

  var offlineCount: Int {
    visibleNodes.filter { $0.info.status == .offline }.count
  }

  /// Aggregate indicator for the bottom bar: the worst individual state wins.
  var connectionState: ConnectionState {
    if machines.isEmpty { return .unconfigured }
    var hasPending = false
    for machine in machines {
      switch machineStates[machine.id] ?? .connecting {
      case .certificateMismatch: return .certificateMismatch
      case .unauthorized: return .unauthorized
      case .failed(let message): return .failed(message)
      case .connecting, .reconnecting: hasPending = true
      case .connected, .unconfigured: break
      }
    }
    return hasPending ? .connecting : .connected
  }

  func machineState(_ id: UUID) -> ConnectionState {
    machineStates[id] ?? .connecting
  }

  // MARK: - History

  func loadHistory(for nodeID: UUID, hours: Int) async {
    guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
    detailHours[nodeID] = hours
    nodes[index].history = historyStore.metricsHistory(for: nodeID, hours: hours)
  }

  func historyError(for nodeID: UUID) -> String? {
    historyErrorByNodeID[nodeID]
  }

  func clearHistoryError(for nodeID: UUID) {
    historyErrorByNodeID[nodeID] = nil
  }

  #if DEBUG
    /// SwiftUI previews only: a store pre-filled with the sample fleet, never
    /// reachable from the shipping UI.
    static var preview: MonitorStore {
      let store = MonitorStore()
      let mock = MockDataSource()
      store.nodes = mock.loadNodes()
      store.groups = mock.loadGroups()
      for node in store.nodes.prefix(2) {
        store.servicesByNode[node.id] = .loaded(MockDataSource.sampleServices())
        store.processesByNode[node.id] = MockDataSource.sampleProcesses()
        store.sensorsByNode[node.id] = MockDataSource.sampleSensors()
      }
      return store
    }

    /// Test hooks, passed AppKit-style (`-asterSeedEndpoint x -asterSeedToken y
    /// -asterSeedFingerprint z -asterShowAddSheet YES`) so they land in the
    /// NSArgumentDomain instead of being mistaken for documents to open —
    /// bare URL-like positional arguments stall window registration.
    private func applyDebugLaunchArguments() {
      let defaults = UserDefaults.standard
      if let endpoint = defaults.string(forKey: "asterSeedEndpoint"),
        let token = defaults.string(forKey: "asterSeedToken"),
        let fingerprint = defaults.string(forKey: "asterSeedFingerprint")
      {
        for machine in machines where machine.endpoint == endpoint {
          removeMachine(machine.id)
        }
        addMachine(name: "seed", endpoint: endpoint, token: token, fingerprint: fingerprint)
      }
      if defaults.bool(forKey: "asterShowAddSheet") {
        isAddMachinePresented = true
      }
      if let probeEndpoint = defaults.string(forKey: "asterProbe") {
        Task {
          do {
            let fingerprint = try await AgentClient.probeFingerprint(endpoint: probeEndpoint)
            print("[aster-debug] probe fingerprint: \(fingerprint)")
          } catch {
            print("[aster-debug] probe error: \(error)")
          }
          fflush(stdout)
        }
      }
    }
  #endif
}

extension NodeMetrics {
  static let empty = NodeMetrics(
    cpuUsage: 0, memoryUsage: 0, swapUsage: 0, diskUsage: 0, downloadBytesPerSecond: 0,
    uploadBytesPerSecond: 0, connectionCount: 0, processCount: 0, loadAverage: 0, uptime: 0,
    diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0)
}
