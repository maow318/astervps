import Foundation

/// On-demand /v1/services fetching. Unlike metrics polling this only runs
/// while a node's services tab is actually visible; the view drives cadence.
extension MonitorStore {
  func loadServices(for nodeID: UUID, forceRefresh: Bool = false) async {
    guard let client = clients[nodeID] else {
      // Preview/demo nodes have no client; keep whatever mock state exists.
      return
    }
    if case .loaded = servicesByNode[nodeID] {
      // Keep showing current data while refreshing in place.
    } else {
      servicesByNode[nodeID] = .loading
    }
    do {
      let services = try await client.services(forceRefresh: forceRefresh)
      servicesByNode[nodeID] = .loaded(services)
      evaluateServiceAlerts(for: nodeID, services: services)
    } catch AgentError.badResponse(404) {
      servicesByNode[nodeID] = .unsupported
    } catch let error as AgentError {
      servicesByNode[nodeID] = .failed(error.localizedDescription)
    } catch {
      servicesByNode[nodeID] = .failed(error.localizedDescription)
    }
  }

  /// True for the machine this app launched its bundled agent on.
  func isLocalNode(_ nodeID: UUID) -> Bool {
    machines.first(where: { $0.id == nodeID })?.endpoint == LocalAgentManager.localEndpoint
  }

  /// Thermal sensors for the node detail overview, throttled to 15 s.
  func loadSensors(for nodeID: UUID) async {
    guard let client = clients[nodeID] else { return }
    if let fetched = sensorsFetchedAt[nodeID], Date.now.timeIntervalSince(fetched) < 15 {
      return
    }
    sensorsFetchedAt[nodeID] = .now
    do {
      sensorsByNode[nodeID] = try await client.sensors()
    } catch AgentError.badResponse(404) {
      sensorsByNode[nodeID] = AgentSensors?.none
    } catch {
      // Keep the previous snapshot on transient errors.
    }
  }

  /// Top processes for the menu-bar hover popover, throttled to the agent's
  /// own 10 s refresh cadence.
  func loadTopProcesses(for nodeID: UUID) async {
    guard let client = clients[nodeID] else { return }
    if let fetched = processesFetchedAt[nodeID], Date.now.timeIntervalSince(fetched) < 10 {
      return
    }
    processesFetchedAt[nodeID] = .now
    do {
      processesByNode[nodeID] = try await client.processes().processes
    } catch AgentError.badResponse(404) {
      processesByNode[nodeID] = [AgentProcess]?.none
    } catch {
      // Keep the previous snapshot on transient errors.
    }
  }
}
