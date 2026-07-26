import Foundation

@MainActor
final class AsterAgentDataSource: MonitorDataSource {
  private let baseURL: URL
  private let token: String
  private let session = URLSession.shared
  private var snapshot: NodeSnapshot?

  init(endpoint: String, token: String) throws {
    guard let url = URL(string: endpoint), url.scheme == "https" else { throw URLError(.badURL) }
    baseURL = url
    self.token = token
  }

  func loadNodes() -> [NodeSnapshot] { snapshot.map { [$0] } ?? [] }
  func loadGroups() -> [NodeGroup] { [] }
  func loadAlerts() -> [AlertItem] { [] }
  func refresh(nodes: [NodeSnapshot], includeHistory: Bool) -> [NodeSnapshot] { nodes }

  func testConnection() async throws { _ = try await request(path: "/v1/meta", as: AgentMeta.self) }

  func loadDashboard() async throws -> MonitorDashboard {
    let meta = try await request(path: "/v1/meta", as: AgentMeta.self)
    let info = NodeInfo(
      id: UUID(), name: meta.hostname, region: "", flag: "", operatingSystem: meta.os,
      status: .offline, tags: [], groupID: nil, createdAt: .now, serverID: baseURL.host)
    let node = NodeSnapshot(info: info, metrics: .empty, history: .empty)
    snapshot = node
    return MonitorDashboard(nodes: [node], groups: [], alerts: [])
  }

  func loadHistory(for node: NodeInfo, hours: Int) async throws -> MetricsHistory { .empty }
  func startLiveUpdates() {}
  func stopLiveUpdates() {}

  private func request<T: Decodable>(path: String, as type: T.Type) async throws -> T {
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw URLError(.userAuthenticationRequired)
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
}

private struct AgentMeta: Decodable {
  let hostname: String
  let os: String
}

extension NodeMetrics {
  fileprivate static let empty = NodeMetrics(
    cpuUsage: 0, memoryUsage: 0, swapUsage: 0, diskUsage: 0, downloadBytesPerSecond: 0,
    uploadBytesPerSecond: 0, connectionCount: 0, processCount: 0, loadAverage: 0, uptime: 0,
    diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0)
}
extension MetricsHistory {
  fileprivate static let empty = MetricsHistory(
    cpu: [], memory: [], download: [], upload: [], diskRead: [], diskWrite: [])
}
