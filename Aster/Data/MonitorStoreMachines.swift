import Foundation

/// Machine CRUD, grouping, billing auto-renew and geo enrichment.
/// Split from MonitorStore.swift to keep both files within the size budget.
extension MonitorStore {
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

  func updateMachine(_ updated: MachineConfig) {
    guard let index = machines.firstIndex(where: { $0.id == updated.id }) else { return }
    machines[index] = updated
    MachineStore.save(machines)
    rebuildGroups()
    refreshNodeInfo(for: updated.id)
  }

  private func refreshNodeInfo(for id: UUID) {
    guard let machine = machines.first(where: { $0.id == id }),
      let nodeIndex = nodes.firstIndex(where: { $0.id == id })
    else { return }
    nodes[nodeIndex].info.name = machine.name
    nodes[nodeIndex].info.tags = machine.tagList
    nodes[nodeIndex].info.groupID = groupID(for: machine.group)
    nodes[nodeIndex].info.flag = machine.effectiveFlag
    nodes[nodeIndex].info.countryCode = machine.effectiveCountryCode
    nodes[nodeIndex].info.billingPrice = machine.displayPrice
    nodes[nodeIndex].info.billingExpiresAt = machine.expiresAt
  }

  func rebuildGroups() {
    let names = Set(machines.compactMap(\.group).filter { !$0.isEmpty })
    for name in names where groupIDByName[name] == nil {
      groupIDByName[name] = UUID()
    }
    groups = names.sorted().map { name in
      NodeGroup(
        id: groupIDByName[name]!, name: name, symbol: "folder",
        nodeIDs: machines.filter { $0.group == name }.map(\.id))
    }
  }

  private func groupID(for name: String?) -> UUID? {
    guard let name, !name.isEmpty else { return nil }
    return groupIDByName[name]
  }

  /// Komari-style auto-renew: an expired machine rolls forward by whole
  /// billing cycles until the expiry is in the future again.
  func processAutoRenewals() {
    var changed = false
    for index in machines.indices {
      guard machines[index].autoRenew == true,
        let cycle = machines[index].cycle,
        var expiry = machines[index].expiresAt
      else { continue }
      while expiry < .now {
        let advanced = Calendar.current.date(byAdding: .month, value: cycle.months, to: expiry)
        expiry = advanced ?? expiry.addingTimeInterval(Double(cycle.months) * 2_592_000)
        changed = true
      }
      machines[index].expiresAt = expiry
    }
    if changed {
      MachineStore.save(machines)
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

  func activateMachines() {
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
      flag: machine.effectiveFlag, operatingSystem: "",
      status: .offline, tags: machine.tagList, groupID: groupID(for: machine.group),
      createdAt: machine.createdAt, countryCode: machine.effectiveCountryCode,
      billingPrice: machine.displayPrice, billingExpiresAt: machine.expiresAt)
    return NodeSnapshot(
      info: info, metrics: .empty,
      history: historyStore.metricsHistory(for: machine.id, hours: 1))
  }


  /// One-shot, cached IP geolocation: flag + city ride along on the node.
  func ensureGeo(for machineID: UUID) {
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
        nodes[nodeIndex].info.flag = machines[index].effectiveFlag
        nodes[nodeIndex].info.countryCode = machines[index].effectiveCountryCode
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
}
