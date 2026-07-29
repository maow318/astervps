import Foundation

/// Where the published agent lives. Modeled on Komari's distribution: the
/// install script is served raw from the GitHub repository and binaries come
/// from GitHub Releases' `latest/download` URLs, so no self-hosted
/// infrastructure is needed.
enum AgentDistribution {
  /// The install command and script derive everything from this one value.
  static let repository: String? = "maow318/astervps"

  private static var script: String? {
    repository.map { "https://raw.githubusercontent.com/\($0)/main/agent/install.sh" }
  }

  /// Bare-IP mode: agent exposed on :9977, TOFU fingerprint pinning.
  static func installCommand(token: String) -> String? {
    script.map { "curl -fsSL \($0) | sudo sh -s -- --token \(token) --listen :9977" }
  }

  /// Domain mode: agent on loopback behind Caddy/nginx with a CA certificate.
  /// `proxy` is nil for auto-detection.
  static func installCommand(token: String, domain: String, proxy: String?) -> String? {
    script.map {
      var command = "curl -fsSL \($0) | sudo sh -s -- --token \(token) --domain \(domain)"
      if let proxy { command += " --proxy \(proxy)" }
      return command
    }
  }

  static var uninstallCommand: String? {
    script.map { "curl -fsSL \($0) | sudo sh -s -- --uninstall" }
  }

  /// One command that prints a full health report of a machine — what the
  /// user runs (or pastes to support) when something looks wrong.
  static var statusCommand: String? {
    script.map { "curl -fsSL \($0) | sudo sh -s -- --status" }
  }
}
