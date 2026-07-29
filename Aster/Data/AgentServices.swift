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

struct AgentProcess: Decodable, Hashable, Identifiable {
  let pid: Int
  let name: String
  let cpuPercent: Double
  let memBytes: Double
  let user: String
  var id: Int { pid }
}

struct AgentProcessList: Decodable {
  let timestamp: Int64
  let processes: [AgentProcess]
}

struct AgentFan: Decodable, Hashable, Identifiable {
  let label: String
  let rpm: Double
  var id: String { label }
}

struct AgentTemp: Decodable, Hashable, Identifiable {
  let label: String
  let celsius: Double
  var id: String { label }
}

struct AgentSensors: Decodable, Hashable {
  let available: Bool
  let fans: [AgentFan]
  let temps: [AgentTemp]

  /// SMC key prefixes / hwmon labels grouped the way humans think about them.
  var groupedTemps: [(group: String, max: Double, count: Int)] {
    var buckets: [String: [Double]] = [:]
    for temp in temps {
      buckets[Self.groupKey(for: temp.label), default: []].append(temp.celsius)
    }
    return buckets.map { (group: $0.key, max: $0.value.max() ?? 0, count: $0.value.count) }
      .sorted { $0.max > $1.max }
  }

  private static func groupKey(for label: String) -> String {
    let lowered = label.lowercased()
    if lowered.contains("core") || lowered.contains("package") || lowered.contains("cpu")
      || label.hasPrefix("TC")
    {
      return "sensors.group.cpu"
    }
    if label.hasPrefix("TG") || lowered.contains("gpu") { return "sensors.group.gpu" }
    if label.hasPrefix("TH") || lowered.contains("nvme") || lowered.contains("ssd")
      || lowered.contains("composite")
    {
      return "sensors.group.storage"
    }
    if label.hasPrefix("TM") || lowered.contains("dimm") || lowered.contains("mem") {
      return "sensors.group.memory"
    }
    if label.hasPrefix("TP") || label.hasPrefix("Tp") || lowered.contains("power") {
      return "sensors.group.power"
    }
    if label.hasPrefix("TW") || lowered.contains("wifi") || lowered.contains("wireless") {
      return "sensors.group.wireless"
    }
    if label.hasPrefix("Ta") || label.hasPrefix("TA") || lowered.contains("ambient") {
      return "sensors.group.ambient"
    }
    return "sensors.group.other"
  }
}

/// Per-node fetch state for the services tab.
enum ServicesState {
  case loading
  case loaded(AgentServices)
  /// Agent predates /v1/services (HTTP 404): show the upgrade hint.
  case unsupported
  case failed(String)
}
