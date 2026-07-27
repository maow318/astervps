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

  init() {
    startRefreshLoop()
  }

  func bootstrap() async {
    MachineStore.migrateLegacyIfNeeded()
    machines = MachineStore.load()
    #if DEBUG
      applyDebugLaunchArguments()
    #endif
    activateMachines()
    await pollAgents()
    for machine in machines {
      ensureGeo(for: machine.id)
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

  // MARK: - Machine management

  func addMachine(name: String, endpoint: String, token: String, fingerprint: String) {
    let machine = MachineConfig(
      id: UUID(), name: name, endpoint: endpoint, certFingerprint: fingerprint, createdAt: .now)
    try? KeychainStore.saveToken(token, for: machine.id)
    machines.append(machine)
    MachineStore.save(machines)
    nodes.append(placeholderNode(for: machine))
    makeClient(for: machine)
    Task { await pollAgents() }
    ensureGeo(for: machine.id)
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
    nodes.removeAll { $0.id == id }
  }

  func hasMachine(endpoint: String) -> Bool {
    machines.contains { $0.endpoint == endpoint }
  }

  func renameMachine(_ id: UUID, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, let index = machines.firstIndex(where: { $0.id == id }) else { return }
    machines[index].name = trimmed
    MachineStore.save(machines)
    if let nodeIndex = nodes.firstIndex(where: { $0.id == id }) {
      nodes[nodeIndex].info.name = trimmed
    }
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
      id: machine.id, name: machine.name, region: machine.city ?? "",
      flag: machine.countryCode.map(GeoLookup.flag) ?? "", operatingSystem: "",
      status: .offline, tags: [], groupID: nil, createdAt: machine.createdAt)
    return NodeSnapshot(
      info: info, metrics: .empty,
      history: historyStore.metricsHistory(for: machine.id, hours: 1))
  }

  // MARK: - History

  func loadHistory(for nodeID: UUID, hours: Int) async {
    guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
    detailHours[nodeID] = hours
    nodes[index].history = historyStore.metricsHistory(for: nodeID, hours: hours)
  }

  /// One-shot, cached IP geolocation: flag + city ride along on the node.
  private func ensureGeo(for machineID: UUID) {
    guard let machine = machines.first(where: { $0.id == machineID }),
      machine.countryCode == nil,
      let host = URL(string: machine.endpoint)?.host,
      !GeoLookup.isPrivateHost(host)
    else { return }
    Task {
      guard let info = await GeoLookup.lookup(host: host),
        let index = machines.firstIndex(where: { $0.id == machineID })
      else { return }
      machines[index].countryCode = info.countryCode
      machines[index].city = info.city
      MachineStore.save(machines)
      if let nodeIndex = nodes.firstIndex(where: { $0.id == machineID }) {
        nodes[nodeIndex].info.flag = info.flag
        nodes[nodeIndex].info.region = subtitle(machineID: machineID)
      }
    }
  }

  /// Card subtitle: "hostname · city" once both are known.
  func subtitle(machineID: UUID) -> String {
    let city = machines.first(where: { $0.id == machineID })?.city
    let hostname = metaByMachine[machineID]?.hostname
    return [hostname, city].compactMap { $0 }.joined(separator: " · ")
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
