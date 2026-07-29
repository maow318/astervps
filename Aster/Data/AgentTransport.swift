import CryptoKit
import Foundation
import Network

/// Minimal HTTPS transport for talking to aster-agents, built on
/// Network.framework instead of URLSession. URLSession's ATS policy refuses
/// self-signed certificates on public addresses regardless of the auth
/// challenge delegate's decision (verified on macOS 26), while NWConnection
/// lets the fingerprint check in the TLS verify block be the sole authority —
/// which is exactly the TOFU model this app implements.
///
/// Requests are issued as HTTP/1.0 with `Connection: close` so responses end
/// at EOF and no chunked-transfer parsing is needed.
// The project defaults to MainActor isolation (SWIFT_DEFAULT_ACTOR_ISOLATION);
// this transport and its lock-based boxes run on Network.framework queues, so
// they opt out explicitly.
nonisolated enum AgentTransport {
  struct Response {
    let status: Int
    let body: Data
    let fingerprint: String
    /// True when the chain validates against the system CA store for this
    /// hostname (domain deployments behind a real certificate).
    let caVerified: Bool
  }

  enum TrustPolicy {
    /// Accept any certificate, but report its fingerprint and CA status
    /// (add-machine probe; no credentials may be sent under this policy).
    case probe
    /// Accept only a certificate whose DER SHA-256 matches.
    case pinned(String)
    /// Accept a chain the system CA store validates for this hostname —
    /// survives Let's Encrypt rotations, so domains stay pin-free.
    case system
  }

  static func get(
    url: URL, token: String?, trust: TrustPolicy, timeout: TimeInterval = 8
  ) async throws -> Response {
    guard url.scheme == "https", let host = url.host else { throw AgentError.invalidEndpoint }
    let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 443))!
    let observed = FingerprintBox()
    let caBox = CABox()

    let tlsOptions = NWProtocolTLS.Options()
    sec_protocol_options_set_verify_block(
      tlsOptions.securityProtocolOptions,
      { _, secTrust, complete in
        let trustRef = sec_trust_copy_ref(secTrust).takeRetainedValue()
        guard
          let chain = SecTrustCopyCertificateChain(trustRef) as? [SecCertificate],
          let leaf = chain.first
        else {
          complete(false)
          return
        }
        let der = SecCertificateCopyData(leaf) as Data
        let fingerprint = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        observed.value = fingerprint
        SecTrustSetPolicies(trustRef, SecPolicyCreateSSL(true, host as CFString))
        let caVerified = SecTrustEvaluateWithError(trustRef, nil)
        caBox.value = caVerified
        switch trust {
        case .probe:
          complete(true)
        case .pinned(let expected):
          complete(fingerprint == expected.lowercased())
        case .system:
          complete(caVerified)
        }
      }, DispatchQueue.global(qos: .userInitiated))

    let parameters = NWParameters(tls: tlsOptions)
    let connection = NWConnection(host: .init(host), port: port, using: parameters)

    do {
      let data = try await perform(connection, url: url, token: token, timeout: timeout)
      guard let fingerprint = observed.value else { throw AgentError.badResponse(0) }
      let (status, body) = try parseHTTP(data)
      return Response(
        status: status, body: body, fingerprint: fingerprint, caVerified: caBox.value)
    } catch let error as NWError {
      // A refused verify block surfaces as a TLS handshake failure; translate
      // it so callers can distinguish trust rejections from network issues.
      if case .tls = error, observed.value != nil {
        switch trust {
        case .pinned, .system: throw AgentError.certificateMismatch
        case .probe: break
        }
      }
      throw error
    }
  }

  private static func perform(
    _ connection: NWConnection, url: URL, token: String?, timeout: TimeInterval
  ) async throws -> Data {
    let path = url.path.isEmpty ? "/" : url.path
    let query = url.query.map { "?\($0)" } ?? ""
    var request = "GET \(path)\(query) HTTP/1.0\r\nHost: \(url.host ?? "")\r\n"
    if let token {
      request += "Authorization: Bearer \(token)\r\n"
    }
    request += "Connection: close\r\n\r\n"
    let requestData = Data(request.utf8)

    let queue = DispatchQueue(label: "aster.agent.transport")
    let guardBox = CompletionGuard()

    return try await withCheckedThrowingContinuation { continuation in
      var received = Data()

      func finish(_ result: Result<Data, Error>) {
        guard guardBox.claim() else { return }
        connection.cancel()
        continuation.resume(with: result)
      }

      queue.asyncAfter(deadline: .now() + timeout) {
        finish(.failure(URLError(.timedOut)))
      }

      func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) {
          data, _, isComplete, error in
          if let data {
            received.append(data)
          }
          if isComplete {
            finish(.success(received))
          } else if let error {
            finish(.failure(error))
          } else {
            receiveLoop()
          }
        }
      }

      connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          connection.send(
            content: requestData,
            completion: .contentProcessed { error in
              if let error {
                finish(.failure(error))
              }
            })
          receiveLoop()
        case .failed(let error):
          finish(.failure(error))
        case .cancelled:
          finish(.failure(URLError(.cancelled)))
        default:
          break
        }
      }
      connection.start(queue: queue)
    }
  }

  private static func parseHTTP(_ data: Data) throws -> (status: Int, body: Data) {
    guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
      throw AgentError.badResponse(0)
    }
    let head = String(decoding: data[..<separator.lowerBound], as: UTF8.self)
    let statusLine = head.components(separatedBy: "\r\n").first ?? ""
    let parts = statusLine.split(separator: " ")
    guard parts.count >= 2, let status = Int(parts[1]) else {
      throw AgentError.badResponse(0)
    }
    return (status, Data(data[separator.upperBound...]))
  }
}

private nonisolated final class FingerprintBox: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: String?

  var value: String? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _value
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      _value = newValue
    }
  }
}

private nonisolated final class CABox: @unchecked Sendable {
  private let lock = NSLock()
  private var _value = false

  var value: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _value
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      _value = newValue
    }
  }
}

private nonisolated final class CompletionGuard: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false

  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if claimed { return false }
    claimed = true
    return true
  }
}
