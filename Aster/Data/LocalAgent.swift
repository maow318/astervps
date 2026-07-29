import AppKit
import Foundation

/// Zero-setup monitoring of the Mac the app runs on: launches the bundled
/// agent on loopback and registers it as a machine automatically — no install
/// command, no manual fingerprint step. The agent lives only while the app
/// runs and is never reachable from the network.
@MainActor
final class LocalAgentManager {
  static let shared = LocalAgentManager()

  private static let endpoint = "https://127.0.0.1:9976"
  private static let tokenKey = "aster.localAgentToken"

  private var process: Process?
  private var terminationObserver: NSObjectProtocol?

  private init() {
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.process?.terminate()
      }
    }
  }

  func startIfNeeded(store: MonitorStore) async {
    guard let binary = Bundle.main.url(forResource: "aster-agent", withExtension: nil) else {
      return
    }
    let token = persistedToken()
    spawn(binary: binary, token: token)

    // The agent prints its certificate immediately; probe (TOFU is safe on
    // loopback against a process we just launched ourselves) then register.
    var fingerprint: String?
    for _ in 0..<5 {
      try? await Task.sleep(for: .milliseconds(700))
      fingerprint = try? await AgentClient.probeFingerprint(endpoint: Self.endpoint)
      if fingerprint != nil { break }
    }
    guard let fingerprint else { return }

    if let existing = store.machines.first(where: { $0.endpoint == Self.endpoint }) {
      if existing.certFingerprint != fingerprint {
        // State directory was wiped; re-pin the fresh certificate.
        let name = existing.name
        store.removeMachine(existing.id)
        store.addMachine(name: name, endpoint: Self.endpoint, token: token, fingerprint: fingerprint)
      }
    } else {
      store.addMachine(
        name: Host.current().localizedName ?? "Mac",
        endpoint: Self.endpoint, token: token, fingerprint: fingerprint)
    }
  }

  private func spawn(binary: URL, token: String) {
    guard process == nil else { return }
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let stateDir = base.appendingPathComponent("Aster/local-agent", isDirectory: true)
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    let tokenFile = stateDir.appendingPathComponent("token")
    try? Data(token.utf8).write(to: tokenFile)
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: tokenFile.path)

    let child = Process()
    child.executableURL = binary
    child.arguments = [
      "--listen", "127.0.0.1:9976",
      "--token-file", tokenFile.path,
      "--state-dir", stateDir.path,
    ]
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    do {
      try child.run()
      process = child
    } catch {
      // Binding fails when an earlier instance is still serving the port;
      // the probe step below talks to whichever agent answers.
    }
  }

  private func persistedToken() -> String {
    if let token = UserDefaults.standard.string(forKey: Self.tokenKey) {
      return token
    }
    let token = (0..<32).map { _ in "0123456789abcdef".randomElement()! }
    let value = String(token)
    UserDefaults.standard.set(value, forKey: Self.tokenKey)
    return value
  }
}
