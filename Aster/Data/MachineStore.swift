import Foundation
import Security

/// One monitored machine as configured by the user. The bearer token lives in
/// the Keychain (see KeychainStore); everything else is UserDefaults JSON.
struct MachineConfig: Identifiable, Codable, Hashable {
  let id: UUID
  var name: String
  var endpoint: String
  var certFingerprint: String
  var createdAt: Date
  /// Cached geo lookup (see GeoLookup); nil until the first resolution.
  var countryCode: String? = nil
  var city: String? = nil
  /// Manual correction: geo databases misplace hosts often enough that the
  /// user needs the last word. Wins over the detected code when set.
  var countryOverride: String? = nil
  /// User-entered billing note and expiry, shown on cards and in the table.
  /// `price` is the legacy free-text form; the structured fields below win
  /// when set. All additions stay optional so stored JSON keeps decoding.
  var price: String? = nil
  var expiresAt: Date? = nil
  var priceAmount: Double? = nil
  var currency: String? = nil
  var billingCycle: String? = nil
  var autoRenew: Bool? = nil
  /// Semicolon-separated tags, Komari-style.
  var tags: String? = nil
  var group: String? = nil
  var note: String? = nil
  var isHidden: Bool? = nil

  var effectiveCountryCode: String? {
    let code = countryOverride ?? countryCode
    return code?.isEmpty == false ? code : nil
  }

  var effectiveFlag: String {
    effectiveCountryCode.map(GeoLookup.flag) ?? ""
  }

  var tagList: [String] {
    (tags ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  var hidden: Bool { isHidden ?? false }

  var cycle: BillingCycle? {
    billingCycle.flatMap(BillingCycle.init(rawValue:))
  }

  /// "$17.93/年" composed from the structured fields, or the legacy text.
  var displayPrice: String? {
    guard let priceAmount else { return price }
    if priceAmount < 0 { return L.text("billing.free") }
    if priceAmount == 0 { return nil }
    let base = "\(currency ?? "$")\(String(format: "%.2f", priceAmount))"
    guard let cycle else { return base }
    return "\(base)/\(L.text(cycle.shortKey))"
  }
}

enum BillingCycle: String, CaseIterable, Identifiable {
  case monthly, quarterly, semiannual, yearly, biennial, triennial

  var id: String { rawValue }
  var shortKey: String { "cycle.\(rawValue)" }

  var months: Int {
    switch self {
    case .monthly: 1
    case .quarterly: 3
    case .semiannual: 6
    case .yearly: 12
    case .biennial: 24
    case .triennial: 36
    }
  }
}

enum MachineStore {
  private static let machinesKey = "aster.machines"
  private static let demoModeKey = "aster.demoMode"
  private static let legacyEndpointKey = "komari.endpoint"
  private static let legacyDemoModeKey = "komari.demoMode"

  static func load() -> [MachineConfig] {
    guard let data = UserDefaults.standard.data(forKey: machinesKey) else { return [] }
    return (try? JSONDecoder().decode([MachineConfig].self, from: data)) ?? []
  }

  static func save(_ machines: [MachineConfig]) {
    guard let data = try? JSONEncoder().encode(machines) else { return }
    UserDefaults.standard.set(data, forKey: machinesKey)
  }

  /// Carries the single-machine era (komari.* keys) into the machine list.
  /// The old endpoint has no pinned fingerprint, so the entry surfaces as
  /// "certificate refused" until the user re-verifies it in the add flow.
  static func migrateLegacyIfNeeded() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: demoModeKey)
    if let endpoint = defaults.string(forKey: legacyEndpointKey), !endpoint.isEmpty {
      var machines = load()
      if !machines.contains(where: { $0.endpoint == endpoint }) {
        let machine = MachineConfig(
          id: UUID(),
          name: URL(string: endpoint)?.host ?? endpoint,
          endpoint: endpoint,
          certFingerprint: "",
          createdAt: .now)
        if let legacyToken = KeychainStore.readLegacyToken() {
          try? KeychainStore.saveToken(legacyToken, for: machine.id)
        }
        machines.append(machine)
        save(machines)
      }
    }
    defaults.removeObject(forKey: legacyEndpointKey)
    defaults.removeObject(forKey: legacyDemoModeKey)
    KeychainStore.deleteLegacyToken()
  }
}

enum KeychainStore {
  private static let legacyAccount = "komari-api-token"

  private static func account(for machineID: UUID) -> String {
    "aster-machine-\(machineID.uuidString)"
  }

  private static func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account,
    ]
  }

  static func saveToken(_ token: String, for machineID: UUID) throws {
    let account = account(for: machineID)
    guard !token.isEmpty else {
      SecItemDelete(baseQuery(account: account) as CFDictionary)
      return
    }
    SecItemDelete(baseQuery(account: account) as CFDictionary)
    var item = baseQuery(account: account)
    item[kSecValueData as String] = Data(token.utf8)
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
      throw KeychainError.saveFailed
    }
  }

  static func readToken(for machineID: UUID) -> String? {
    read(account: account(for: machineID))
  }

  static func deleteToken(for machineID: UUID) {
    SecItemDelete(baseQuery(account: account(for: machineID)) as CFDictionary)
  }

  static func readLegacyToken() -> String? {
    read(account: legacyAccount)
  }

  static func deleteLegacyToken() {
    SecItemDelete(baseQuery(account: legacyAccount) as CFDictionary)
  }

  private static func read(account: String) -> String? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  enum KeychainError: Error {
    case saveFailed
  }
}
