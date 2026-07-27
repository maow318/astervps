import Foundation

/// Currency conversion for the billing page. Rates are fetched from a free
/// keyless endpoint and cached; bundled fallbacks keep the page usable
/// offline. All internal math runs in CNY, matching the stored prices.
@Observable
@MainActor
final class ExchangeRates {
  static let supported = ["CNY", "USD", "HKD", "EUR", "GBP", "JPY"]

  static let symbols: [String: String] = [
    "CNY": "¥", "USD": "$", "HKD": "HK$", "EUR": "€", "GBP": "£", "JPY": "¥",
  ]

  /// Units of the given currency per 1 CNY.
  private(set) var rates: [String: Double] = [
    "CNY": 1, "USD": 0.1425, "HKD": 1.1084, "EUR": 0.1210, "GBP": 0.1056, "JPY": 22.2316,
  ]
  private(set) var updatedAt: Date?

  func refresh() async {
    guard let url = URL(string: "https://open.er-api.com/v6/latest/CNY") else { return }
    var request = URLRequest(url: url, timeoutInterval: 10)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      let http = response as? HTTPURLResponse, http.statusCode == 200,
      let payload = try? JSONDecoder().decode(RatesResponse.self, from: data),
      Self.supported.allSatisfy({ $0 == "CNY" || payload.rates[$0] != nil })
    else { return }
    var merged = payload.rates
    merged["CNY"] = 1
    rates = merged
    updatedAt = .now
  }

  func convert(_ cnyAmount: Double, to currency: String) -> Double {
    cnyAmount * (rates[currency] ?? 1)
  }

  /// Normalizes a machine's stored price (any supported currency) into CNY.
  func toCNY(amount: Double, currency: String?) -> Double {
    let code = Self.currencyCode(for: currency)
    guard let rate = rates[code], rate > 0 else { return amount }
    return amount / rate
  }

  static func currencyCode(for symbol: String?) -> String {
    switch symbol {
    case "$", "USD": "USD"
    case "HK$", "HKD": "HKD"
    case "€", "EUR": "EUR"
    case "£", "GBP": "GBP"
    case "¥", "CNY": "CNY"
    default: "CNY"
    }
  }

  static func format(_ amount: Double, currency: String) -> String {
    let symbol = symbols[currency] ?? currency
    return "\(symbol) \(String(format: "%.2f", amount))"
  }

  private struct RatesResponse: Decodable {
    let rates: [String: Double]
  }
}
