import AppKit
import Foundation

/// Remote brand icons with a two-tier cache. Service logos come from the
/// dashboard-icons collection (the de-facto standard of homelab dashboards,
/// via jsDelivr); website favicons from Google's favicon endpoint. Every miss
/// is negative-cached for the session and the caller falls back to the local
/// gradient glyph tile, so the UI never breaks offline.
@MainActor
final class IconStore {
  static let shared = IconStore()

  private let memory = NSCache<NSString, NSImage>()
  private var failedKeys: Set<String> = []
  private let diskDirectory: URL

  private init() {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    diskDirectory = base.appendingPathComponent("Aster/icons", isDirectory: true)
    try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
  }

  func serviceIcon(slug: String) async -> NSImage? {
    guard
      let url = URL(
        string: "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/\(slug).png")
    else { return nil }
    return await image(key: "svc-\(slug)", url: url)
  }

  func favicon(domain: String) async -> NSImage? {
    guard domain.contains("."), !domain.contains("/"),
      let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=64")
    else { return nil }
    return await image(key: "fav-\(domain)", url: url)
  }

  private func image(key: String, url: URL) async -> NSImage? {
    if let cached = memory.object(forKey: key as NSString) { return cached }
    if failedKeys.contains(key) { return nil }
    let file = diskDirectory.appendingPathComponent(sanitized(key))
    if let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
      memory.setObject(image, forKey: key as NSString)
      return image
    }
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200,
        let image = NSImage(data: data), image.size.width > 1
      else {
        failedKeys.insert(key)
        return nil
      }
      try? data.write(to: file)
      memory.setObject(image, forKey: key as NSString)
      return image
    } catch {
      failedKeys.insert(key)
      return nil
    }
  }

  private func sanitized(_ key: String) -> String {
    key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
      .reduce(into: "") { $0.append($1) }
  }
}

/// Maps process / image / package names to dashboard-icons slugs. Returns nil
/// when there is no well-known logo — callers keep the gradient glyph.
enum ServiceIconCatalog {
  private static let mapping: [(fragment: String, slug: String)] = [
    ("nginx", "nginx"), ("caddy", "caddy"), ("apache2", "apache"), ("httpd", "apache"),
    ("docker", "docker"), ("containerd", "docker"),
    ("postgres", "postgresql"), ("mysql", "mysql"), ("mariadb", "mariadb"),
    ("redis", "redis"), ("mongo", "mongodb"),
    ("emby", "emby"), ("jellyfin", "jellyfin"), ("plex", "plex"),
    ("grafana", "grafana"), ("prometheus", "prometheus"),
    ("gitea", "gitea"), ("git", "git"),
    ("node", "nodejs"), ("python", "python"), ("java", "java"), ("php", "php"),
    ("rustc", "rust"), ("go", "go"),
    ("fail2ban", "fail2ban"), ("tailscale", "tailscale"), ("wireguard", "wireguard"),
    ("ufw", "ubuntu"),
  ]

  static func slug(for name: String) -> String? {
    let lowered = name.lowercased()
    return mapping.first { lowered.contains($0.fragment) }?.slug
  }
}
