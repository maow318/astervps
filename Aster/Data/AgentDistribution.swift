import Foundation

/// Where the published agent lives. Modeled on Komari's distribution: the
/// install script is served raw from the GitHub repository and binaries come
/// from GitHub Releases' `latest/download` URLs, so no self-hosted
/// infrastructure is needed.
enum AgentDistribution {
  /// Set to "owner/repo" once the GitHub repository and first release exist.
  /// The install command and script derive everything from this one value.
  static let repository: String? = nil

  static func installCommand(token: String) -> String? {
    guard let repository else { return nil }
    let script = "https://raw.githubusercontent.com/\(repository)/main/agent/install.sh"
    return "curl -fsSL \(script) | sudo sh -s -- --token \(token) --listen :9977"
  }
}
