import Foundation
import Observation

/// Orchestrates demo data and the fleet of configured agent machines. Each
/// machine gets its own AgentClient; one machine failing never affects the
/// others. Node identity: NodeInfo.id == MachineConfig.id.
@Observable
@MainActor
final class MonitorStore {
  var nodes: [NodeSnapshot] = []
  var groups: [NodeGroup] = []
  var alerts: [AlertItem] = []
  var machines: [MachineConfig] = []
  var machineStates: [UUID: ConnectionState] = [:]
  var isDemoMode = true
  var isAddMachinePresented = false
  var historyErrorByNodeID: [UUID: String] = [:]

  private let mock = MockDataSource()
  var clients: [UUID: AgentClient] = [:]
  var metaByMachine: [UUID: AgentMeta] = [:]
  let historyStore = HistoryStore()
  var refreshTask: Task<Void, Never>?
  private var shouldRefreshHistory = false
  var isWindowActive = true
  var isPolling = false
  var lastHistorySync: [UUID: Date] = [:]
  var detailHours: [UUID: Int] = [:]

  init() {
    startRefreshLoop()
  }

  func bootstrap() async {
    MachineStore.migrateLegacyIfNeeded()
    machines = MachineStore.load()
    isDemoMode = MachineStore.isDemoMode
    #if DEBUG
      applyDebugLaunchArguments()
    #endif
    if isDemoMode {
      loadDemo()
    } else {
      activateMachines()
      await pollAgents()
    }
  }

  func setWindowActive(_ isActive: Bool) {
    isWindowActive = isActive
  }

  func node(id: UUID) -> NodeSnapshot? {
    nodes.first { $0.id == id }
  }

  var onlineCount: Int {
    nodes.filter { $0.info.status == .online }.count
  }

  var offlineCount: Int {
    nodes.filter { $0.info.status == .offline }.count
  }

  /// Aggregate indicator for the bottom bar: the worst individual state wins.
  var connectionState: ConnectionState {
    if isDemoMode || machines.isEmpty { return .unconfigured }
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

  // MARK: - Demo mode

  func setDemoMode(_ enabled: Bool) {
    MachineStore.isDemoMode = enabled
    isDemoMode = enabled
    if enabled {
      teardownClients()
      loadDemo()
    } else {
      activateMachines()
      Task { await pollAgents() }
    }
  }

  private func loadDemo() {
    nodes = mock.loadNodes()
    groups = mock.loadGroups()
    alerts = mock.loadAlerts()
  }

  func refreshDemo() {
    let includeHistory = shouldRefreshHistory
    let refreshed = mock.refresh(nodes: nodes, includeHistory: includeHistory)
    for node in refreshed {
      guard let index = nodes.firstIndex(where: { $0.id == node.id }) else { continue }
      nodes[index].metrics = node.metrics
      nodes[index].info.status = node.info.status
      if includeHistory {
        nodes[index].history = node.history
      }
    }
    shouldRefreshHistory.toggle()
  }

  // MARK: - Machine management

  func addMachine(name: String, endpoint: String, token: String, fingerprint: String) {
    let machine = MachineConfig(
      id: UUID(), name: name, endpoint: endpoint, certFingerprint: fingerprint, createdAt: .now)
    try? KeychainStore.saveToken(token, for: machine.id)
    machines.append(machine)
    MachineStore.save(machines)
    if isDemoMode {
      setDemoMode(false)
    } else {
      nodes.append(placeholderNode(for: machine))
      makeClient(for: machine)
      Task { await pollAgents() }
    }
  }

  func removeMachine(_ id: UUID) {
    machines.removeAll { $0.id == id }
    MachineStore.save(machines)
    KeychainStore.deleteToken(for: id)
    historyStore.delete(for: id)
    clients[id]?.invalidate()
    clients[id] = nil
    machineStates[id] = nil
    metaByMachine[id] = nil
    lastHistorySync[id] = nil
    if !isDemoMode {
      nodes.removeAll { $0.id == id }
    }
  }

  func hasMachine(endpoint: String) -> Bool {
    machines.contains { $0.endpoint == endpoint }
  }

  /// Authenticated, pinned verification used by the add-machine flow after
  /// the user confirmed the fingerprint.
  func verifyMachine(endpoint: String, token: String, fingerprint: String) async throws -> AgentMeta
  {
    let client = try AgentClient(endpoint: endpoint, token: token, fingerprint: fingerprint)
    defer { client.invalidate() }
    return try await client.meta()
  }

  private func activateMachines() {
    teardownClients()
    groups = []
    alerts = []
    nodes = machines.map { placeholderNode(for: $0) }
    for machine in machines {
      makeClient(for: machine)
    }
  }

  private func makeClient(for machine: MachineConfig) {
    guard
      let token = KeychainStore.readToken(for: machine.id),
      let client = try? AgentClient(
        endpoint: machine.endpoint, token: token, fingerprint: machine.certFingerprint)
    else {
      machineStates[machine.id] = .failed(L.text("machines.missingToken"))
      return
    }
    clients[machine.id] = client
    machineStates[machine.id] = .connecting
  }

  private func teardownClients() {
    for client in clients.values {
      client.invalidate()
    }
    clients = [:]
    machineStates = [:]
    isPolling = false
  }

  private func placeholderNode(for machine: MachineConfig) -> NodeSnapshot {
    let info = NodeInfo(
      id: machine.id, name: machine.name, region: "", flag: "", operatingSystem: "",
      status: .offline, tags: [], groupID: nil, createdAt: machine.createdAt)
    return NodeSnapshot(
      info: info, metrics: .empty,
      history: historyStore.metricsHistory(for: machine.id, hours: 1))
  }

  // MARK: - History

  func loadHistory(for nodeID: UUID, hours: Int) async {
    guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
    if isDemoMode {
      nodes[index].history = mock.history(for: nodes[index], hours: hours)
      return
    }
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
        MachineStore.isDemoMode = false
        isDemoMode = false
        addMachine(name: "seed", endpoint: endpoint, token: token, fingerprint: fingerprint)
      }
      if defaults.bool(forKey: "asterShowAddSheet") {
        isAddMachinePresented = true
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
