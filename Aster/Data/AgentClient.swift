import AppKit
import Foundation
import UniformTypeIdentifiers

/// Resolves Mac model identifiers to the system's own product render and
/// marketing name — the same assets About This Mac uses, via public UTType
/// device-model-code tagging. Works for remote Macs too.
@MainActor
enum DeviceIdentity {
  static func deviceType(for modelIdentifier: String?) -> UTType? {
    guard let modelIdentifier, !modelIdentifier.isEmpty else { return nil }
    return UTType(
      tag: modelIdentifier,
      tagClass: UTTagClass(rawValue: "com.apple.device-model-code"),
      conformingTo: nil)
  }

  static func productImage(for modelIdentifier: String?) -> NSImage? {
    guard let type = deviceType(for: modelIdentifier) else { return nil }
    return NSWorkspace.shared.icon(for: type)
  }

  /// "Mac mini (2024)" — marketing name plus the year hidden in the UTI.
  static func marketingName(for modelIdentifier: String?) -> String? {
    guard let type = deviceType(for: modelIdentifier),
      let name = type.localizedDescription, name != modelIdentifier
    else { return nil }
    let year = type.identifier.split(separator: "-").last.flatMap { Int($0) }
    if let year, year > 2000 {
      return "\(name) (\(year))"
    }
    return name
  }
}

enum AgentError: Error, LocalizedError {
  case invalidEndpoint
  case certificateMismatch
  case unauthorized
  case badResponse(Int)

  var errorDescription: String? {
    switch self {
    case .invalidEndpoint: L.text("agent.error.invalidEndpoint")
    case .certificateMismatch: L.text("connection.certMismatch")
    case .unauthorized: L.text("connection.unauthorized")
    case .badResponse(let status): "\(L.text("agent.error.badResponse")) (\(status))"
    }
  }
}

/// Client for one aster-agent. Trust is anchored exclusively to the machine's
/// pinned certificate fingerprint via AgentTransport's TLS verify block;
/// system CA evaluation and ATS never participate.
final class AgentClient {
  private let baseURL: URL
  private let token: String
  private let fingerprint: String

  init(endpoint: String, token: String, fingerprint: String) throws {
    guard let url = URL(string: endpoint), url.scheme == "https" else {
      throw AgentError.invalidEndpoint
    }
    baseURL = url
    self.token = token
    self.fingerprint = fingerprint
  }

  /// Connects once without credentials purely to observe the server's leaf
  /// certificate. No token is transmitted, so a man-in-the-middle learns
  /// nothing; the returned fingerprint is what the user confirms (TOFU).
  static func probeFingerprint(endpoint: String) async throws -> String {
    guard let url = URL(string: endpoint), url.scheme == "https" else {
      throw AgentError.invalidEndpoint
    }
    let response = try await AgentTransport.get(
      url: url.appendingPathComponent("/v1/meta"), token: nil, trust: .probe)
    return response.fingerprint
  }

  func meta() async throws -> AgentMeta {
    try await get("/v1/meta")
  }

  func metrics() async throws -> AgentMetrics {
    try await get("/v1/metrics")
  }

  func history(since: Int64) async throws -> [AgentSnapshot] {
    try await get("/v1/history", query: [URLQueryItem(name: "since", value: "\(since)")])
  }

  func processes() async throws -> AgentProcessList {
    try await get("/v1/processes")
  }

  func sensors() async throws -> AgentSensors {
    try await get("/v1/sensors")
  }

  func services(forceRefresh: Bool = false) async throws -> AgentServices {
    try await get(
      "/v1/services",
      query: forceRefresh ? [URLQueryItem(name: "refresh", value: "1")] : [])
  }

  func invalidate() {
    // Connections are one-shot; nothing persistent to tear down.
  }

  private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
    guard
      var components = URLComponents(
        url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
    else { throw AgentError.invalidEndpoint }
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else { throw AgentError.invalidEndpoint }

    let response = try await AgentTransport.get(
      url: url, token: token, trust: .pinned(fingerprint))
    if response.status == 401 { throw AgentError.unauthorized }
    guard 200..<300 ~= response.status else { throw AgentError.badResponse(response.status) }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: response.body)
  }
}

// MARK: - Wire types (docs/aster-protocol.md)

struct AgentMeta: Decodable {
  let hostname: String
  let os: String
  let kernel: String
  let architecture: String
  let cpuModel: String
  let cpuCores: Int
  let agentVersion: String
  let collectIntervalSeconds: Int
  /// Agent >= 0.6.0: "Mac16,10" and "macOS 26.5.2" / "Ubuntu 22.04".
  let modelIdentifier: String?
  let osPretty: String?

  /// SF Symbol for the dashboard hero, picked from what the host reports.
  var deviceSymbol: String {
    let model = (modelIdentifier ?? "").lowercased()
    if model.contains("book") { return "laptopcomputer" }
    if model.contains("macmini") || model.contains("mac1") { return "macmini.fill" }
    switch os.lowercased() {
    case "darwin", "macos": return "desktopcomputer"
    case "windows": return "pc"
    default: return "server.rack"
    }
  }
}

struct AgentPair: Decodable {
  let used: Double
  let total: Double

  var percentage: Double {
    total > 0 ? min(used / total * 100, 100) : 0
  }
}

struct AgentNetwork: Decodable {
  let up: Double
  let down: Double
  let totalUp: Double
  let totalDown: Double
}

struct AgentConnections: Decodable {
  let tcp: Int
  let udp: Int
}

struct AgentLoad: Decodable {
  let load1: Double
  let load5: Double
  let load15: Double
}

struct AgentMetrics: Decodable {
  let timestamp: Int64
  let cpuUsage: Double
  /// Absent on agents older than 0.5.0.
  let steal: Double?
  let memory: AgentPair
  let swap: AgentPair
  let disk: AgentPair
  let network: AgentNetwork
  let connections: AgentConnections
  let processCount: Int
  let load: AgentLoad
  let uptime: Double

  var nodeMetrics: NodeMetrics {
    NodeMetrics(
      cpuUsage: cpuUsage,
      stealPercent: steal ?? 0,
      memoryUsage: memory.percentage,
      swapUsage: swap.percentage,
      diskUsage: disk.percentage,
      downloadBytesPerSecond: network.down,
      uploadBytesPerSecond: network.up,
      connectionCount: connections.tcp + connections.udp,
      processCount: processCount,
      loadAverage: load.load1,
      uptime: uptime,
      diskReadBytesPerSecond: 0,
      diskWriteBytesPerSecond: 0,
      memoryUsedBytes: memory.used,
      memoryTotalBytes: memory.total,
      swapUsedBytes: swap.used,
      swapTotalBytes: swap.total,
      diskUsedBytes: disk.used,
      diskTotalBytes: disk.total,
      totalUploadBytes: network.totalUp,
      totalDownloadBytes: network.totalDown,
      load5: load.load5,
      load15: load.load15)
  }
}

struct AgentSnapshot: Decodable {
  let timestamp: Int64
  let metrics: AgentMetrics
}
