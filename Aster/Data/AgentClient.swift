import CryptoKit
import Foundation

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

/// HTTPS client for one aster-agent. Trust is anchored exclusively to the
/// machine's pinned certificate fingerprint — system CA evaluation is not
/// used because agents serve self-signed certificates.
final class AgentClient {
  private let baseURL: URL
  private let token: String
  private let delegate: PinningDelegate
  private let session: URLSession

  init(endpoint: String, token: String, fingerprint: String) throws {
    guard let url = URL(string: endpoint), url.scheme == "https" else {
      throw AgentError.invalidEndpoint
    }
    baseURL = url
    self.token = token
    delegate = PinningDelegate(mode: .pinned(fingerprint))
    session = URLSession(
      configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
  }

  /// Connects once without credentials purely to observe the server's leaf
  /// certificate. No token is transmitted, so a man-in-the-middle learns
  /// nothing; the returned fingerprint is what the user confirms (TOFU).
  static func probeFingerprint(endpoint: String) async throws -> String {
    guard let url = URL(string: endpoint), url.scheme == "https" else {
      throw AgentError.invalidEndpoint
    }
    let delegate = PinningDelegate(mode: .probe)
    let session = URLSession(
      configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    let request = URLRequest(url: url.appendingPathComponent("/v1/meta"), timeoutInterval: 8)
    _ = try await session.data(for: request)
    guard let fingerprint = delegate.observedFingerprint else {
      throw AgentError.invalidEndpoint
    }
    return fingerprint
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

  func invalidate() {
    session.finishTasksAndInvalidate()
  }

  private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
    guard
      var components = URLComponents(
        url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
    else { throw AgentError.invalidEndpoint }
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else { throw AgentError.invalidEndpoint }

    var request = URLRequest(url: url, timeoutInterval: 8)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      if delegate.sawMismatch { throw AgentError.certificateMismatch }
      throw error
    }
    guard let http = response as? HTTPURLResponse else { throw AgentError.badResponse(0) }
    if http.statusCode == 401 { throw AgentError.unauthorized }
    guard 200..<300 ~= http.statusCode else { throw AgentError.badResponse(http.statusCode) }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: data)
  }
}

/// Evaluates the server certificate by SHA-256 fingerprint of its DER bytes.
/// `.probe` accepts any certificate but records what it saw; `.pinned` only
/// accepts an exact fingerprint match and never falls back to system trust.
final class PinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
  enum Mode {
    case probe
    case pinned(String)
  }

  private let mode: Mode
  private let lock = NSLock()
  private var _observedFingerprint: String?
  private var _sawMismatch = false

  init(mode: Mode) {
    self.mode = mode
  }

  var observedFingerprint: String? {
    lock.lock()
    defer { lock.unlock() }
    return _observedFingerprint
  }

  var sawMismatch: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _sawMismatch
  }

  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      let trust = challenge.protectionSpace.serverTrust,
      let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
      let leaf = chain.first
    else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    let der = SecCertificateCopyData(leaf) as Data
    let fingerprint = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()

    lock.lock()
    _observedFingerprint = fingerprint
    lock.unlock()

    switch mode {
    case .probe:
      completionHandler(.useCredential, URLCredential(trust: trust))
    case .pinned(let expected):
      if fingerprint == expected.lowercased() {
        completionHandler(.useCredential, URLCredential(trust: trust))
      } else {
        lock.lock()
        _sawMismatch = true
        lock.unlock()
        completionHandler(.cancelAuthenticationChallenge, nil)
      }
    }
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
      diskWriteBytesPerSecond: 0)
  }
}

struct AgentSnapshot: Decodable {
  let timestamp: Int64
  let metrics: AgentMetrics
}
