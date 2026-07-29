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
}
