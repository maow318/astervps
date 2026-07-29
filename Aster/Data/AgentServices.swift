import Foundation

// Wire types for GET /v1/services (docs/aster-protocol.md). Snake_case JSON
// decoded with the same convertFromSnakeCase strategy as the other endpoints.

struct AgentListener: Decodable, Hashable, Identifiable {
  let port: Int
  let `protocol`: String
  let address: String
  let scope: String
  let pid: Int
  let process: String
  let cmdline: String
  let user: String
  let container: String?

  var id: String { "\(`protocol`):\(address):\(port):\(pid)" }
  var isPublic: Bool { scope == "public" }
}

struct AgentWebsite: Decodable, Hashable, Identifiable {
  let domain: String
  let server: String
  let port: Int
  let tls: Bool
  /// Health probe fields, absent on agents older than 0.3.0.
  let status: Int?
  let latencyMs: Int?
  let ok: Bool?
  let certDaysLeft: Int?

  var id: String { "\(domain):\(port)" }
  var url: URL? { URL(string: "\(tls ? "https" : "http")://\(domain)\(portSuffix)") }
  private var portSuffix: String {
    (tls && port == 443) || (!tls && port == 80) ? "" : ":\(port)"
  }
}

struct AgentContainerPort: Decodable, Hashable {
  let host: Int
  let container: Int
  let `protocol`: String
}

struct AgentContainer: Decodable, Hashable, Identifiable {
  let id: String
  let name: String
  let image: String
  let state: String
  let status: String
  let composeProject: String?
  let composeService: String?
  let ports: [AgentContainerPort]
  let cpuPercent: Double
  let memUsed: Double
  let memLimit: Double
  let restarts: Int

  var isRunning: Bool { state == "running" }
  /// Memory as a 0-100 percentage when the container has a limit.
  var memoryPercent: Double? { memLimit > 0 ? min(memUsed / memLimit * 100, 100) : nil }
}

struct AgentSwarmService: Decodable, Hashable, Identifiable {
  let name: String
  let replicas: String
  var id: String { name }
}

struct AgentSwarm: Decodable, Hashable {
  let active: Bool
  let role: String?
  let nodes: Int?
  let services: [AgentSwarmService]?
}

struct AgentDocker: Decodable, Hashable {
  let available: Bool
  let reason: String?
  let version: String?
  let swarm: AgentSwarm
  let containers: [AgentContainer]?
}

struct AgentSystemdUnit: Decodable, Hashable, Identifiable {
  let name: String
  let description: String
  var id: String { name }
}

struct AgentSystemd: Decodable, Hashable {
  let running: [AgentSystemdUnit]
  let failed: [String]
}

struct AgentPackage: Decodable, Hashable, Identifiable {
  let name: String
  let version: String
  let source: String
  var id: String { name }
}

struct AgentServices: Decodable, Hashable {
  let collectedAt: Int64
  let restricted: Bool
  let listeners: [AgentListener]
  let websites: [AgentWebsite]
  let docker: AgentDocker
  let systemd: AgentSystemd?
  let packages: [AgentPackage]
}

/// Per-node fetch state for the services tab.
enum ServicesState {
  case loading
  case loaded(AgentServices)
  /// Agent predates /v1/services (HTTP 404): show the upgrade hint.
  case unsupported
  case failed(String)
}
