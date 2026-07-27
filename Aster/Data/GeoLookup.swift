import Foundation

/// Resolves a machine's public address to a country flag and city, once per
/// machine (the result is cached in MachineConfig). Free keyless services are
/// plenty here: one lookup at add time, none afterwards. api.ip.sb is tried
/// first (Cloudflare-fronted, reachable from CN), ipwho.is as fallback.
enum GeoLookup {
  struct Info {
    let countryCode: String
    let city: String?

    var flag: String {
      GeoLookup.flag(countryCode: countryCode)
    }
  }

  static func lookup(host: String) async -> Info? {
    guard !isPrivateHost(host) else { return nil }
    if let info = await queryIPSB(host) { return info }
    return await queryIPWhois(host)
  }

  /// Country code → regional-indicator emoji, e.g. "US" → 🇺🇸.
  nonisolated static func flag(countryCode: String) -> String {
    let scalars = countryCode.uppercased().unicodeScalars.compactMap { scalar in
      UnicodeScalar(127_397 + scalar.value)
    }
    guard scalars.count == 2 else { return "" }
    return String(String.UnicodeScalarView(scalars))
  }

  /// Loopback, RFC1918 and link-local hosts have no meaningful public
  /// location, and geo services would report the resolver's address instead.
  nonisolated static func isPrivateHost(_ host: String) -> Bool {
    if host == "localhost" || host.hasPrefix("127.") || host.hasPrefix("10.")
      || host.hasPrefix("192.168.") || host.hasPrefix("169.254.") || host == "::1"
    {
      return true
    }
    let parts = host.split(separator: ".").compactMap { Int($0) }
    if parts.count == 4, parts[0] == 172, (16...31).contains(parts[1]) {
      return true
    }
    return false
  }

  private struct IPSBResponse: Decodable {
    let countryCode: String
    let city: String?
  }

  private static func queryIPSB(_ host: String) async -> Info? {
    guard let url = URL(string: "https://api.ip.sb/geoip/\(host)") else { return nil }
    guard let data = await fetch(url) else { return nil }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let response = try? decoder.decode(IPSBResponse.self, from: data),
      response.countryCode.count == 2
    else { return nil }
    return Info(countryCode: response.countryCode, city: response.city)
  }

  private struct IPWhoisResponse: Decodable {
    let success: Bool
    let countryCode: String?
    let city: String?
  }

  private static func queryIPWhois(_ host: String) async -> Info? {
    guard let url = URL(string: "https://ipwho.is/\(host)") else { return nil }
    guard let data = await fetch(url) else { return nil }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let response = try? decoder.decode(IPWhoisResponse.self, from: data),
      response.success, let code = response.countryCode, code.count == 2
    else { return nil }
    return Info(countryCode: code, city: response.city)
  }

  private static func fetch(_ url: URL) async -> Data? {
    var request = URLRequest(url: url, timeoutInterval: 10)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      let http = response as? HTTPURLResponse, http.statusCode == 200
    else { return nil }
    return data
  }
}
