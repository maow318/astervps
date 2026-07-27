import SwiftUI

/// Asset overview: what the fleet costs, what it costs per month, and how
/// much prepaid value is still left in it.
struct BillingPage: View {
  @Environment(MonitorStore.self) private var store
  @State private var rates = ExchangeRates()
  @AppStorage("aster.billingCurrency") private var currency = "CNY"
  @AppStorage("aster.billingSort") private var sort = "value_desc"
  @AppStorage("aster.billingExcludeFree") private var excludeFree = true

  private struct Entry: Identifiable {
    let id: UUID
    let name: String
    let flag: String
    let priceCNY: Double
    let monthlyCNY: Double
    let remainingCNY: Double
    let isFree: Bool
    let hasCycle: Bool
    let expiresAt: Date?
  }

  private var entries: [Entry] {
    let computed = store.machines.map { machine -> Entry in
      let amount = machine.priceAmount ?? 0
      let isFree = amount < 0 || amount == 0
      let priceCNY = isFree ? 0 : rates.toCNY(amount: amount, currency: machine.currency)
      // Without a billing cycle there is no honest way to derive a monthly
      // rate or prorate what's left, so those stay at zero and the row asks
      // the user to fill it in.
      let months = Double(machine.cycle?.months ?? 0)
      let monthly = months > 0 ? priceCNY / months : 0
      return Entry(
        id: machine.id, name: machine.name,
        flag: machine.effectiveFlag, priceCNY: priceCNY, monthlyCNY: monthly,
        remainingCNY: remaining(machine: machine, priceCNY: priceCNY),
        isFree: isFree, hasCycle: machine.cycle != nil, expiresAt: machine.expiresAt)
    }
    switch sort {
    case "value_asc": return computed.sorted { $0.remainingCNY < $1.remainingCNY }
    case "price_desc": return computed.sorted { $0.priceCNY > $1.priceCNY }
    case "price_asc": return computed.sorted { $0.priceCNY < $1.priceCNY }
    default: return computed.sorted { $0.remainingCNY > $1.remainingCNY }
    }
  }

  /// Prepaid value left in the current cycle, prorated by time remaining.
  private func remaining(machine: MachineConfig, priceCNY: Double) -> Double {
    guard let expiry = machine.expiresAt, let cycle = machine.cycle else { return 0 }
    let secondsLeft = expiry.timeIntervalSinceNow
    guard secondsLeft > 0 else { return 0 }
    let cycleSeconds = Double(cycle.months) * 30.44 * 86_400
    guard cycleSeconds > 0 else { return 0 }
    // A far-future expiry means a lifetime deal; count it at full price.
    if secondsLeft > 100 * 365 * 86_400 { return priceCNY }
    return priceCNY * min(secondsLeft / cycleSeconds, 1)
  }

  private var counted: [Entry] {
    excludeFree ? entries.filter { !$0.isFree } : entries
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: AsterSpacing.lg) {
            summary
            controls
            list
            ratesSection
          }
          .padding(AsterSpacing.lg)
        }
        StatusBar()
      }
      .background(AsterColor.background1.opacity(0.65))
      .navigationTitle(L.text("sidebar.billing"))
    }
    .task { await rates.refresh() }
  }

  private var summary: some View {
    HStack(spacing: AsterSpacing.sm) {
      stat(L.text("billing.count"), "\(store.machines.count)", "server.rack")
      stat(L.text("billing.totalValue"), money(counted.reduce(0) { $0 + $1.priceCNY }), "creditcard")
      stat(
        L.text("billing.monthly"), money(counted.reduce(0) { $0 + $1.monthlyCNY }),
        "calendar")
      stat(
        L.text("billing.remaining"), money(counted.reduce(0) { $0 + $1.remainingCNY }),
        "hourglass")
    }
  }

  private func stat(_ title: String, _ value: String, _ symbol: String) -> some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 6) {
        Label(title, systemImage: symbol)
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
        Text(value)
          .font(AsterTypography.metricMedium)
          .foregroundStyle(AsterColor.foregroundPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var controls: some View {
    HStack(spacing: AsterSpacing.sm) {
      Picker(L.text("billing.currency"), selection: $currency) {
        ForEach(ExchangeRates.supported, id: \.self) { code in
          Text("\(code) \(ExchangeRates.symbols[code] ?? "")").tag(code)
        }
      }
      .frame(width: 170)
      Picker(L.text("billing.sort"), selection: $sort) {
        Text(L.text("billing.sortValueDesc")).tag("value_desc")
        Text(L.text("billing.sortValueAsc")).tag("value_asc")
        Text(L.text("billing.sortPriceDesc")).tag("price_desc")
        Text(L.text("billing.sortPriceAsc")).tag("price_asc")
      }
      .frame(width: 200)
      Toggle(L.text("billing.excludeFree"), isOn: $excludeFree)
      Spacer()
      Button {
        Task { await rates.refresh() }
      } label: {
        Label(L.text("billing.refreshRates"), systemImage: "arrow.clockwise")
      }
    }
  }

  private var list: some View {
    VStack(spacing: 6) {
      ForEach(entries) { entry in
        GlassCard {
          HStack(spacing: AsterSpacing.sm) {
            Text(entry.flag)
            Text(entry.name)
              .font(AsterTypography.sectionTitle)
              .foregroundStyle(AsterColor.foregroundPrimary)
            if entry.isFree {
              chip(L.text("billing.free"), tint: AsterColor.online)
            } else if !entry.hasCycle {
              chip(L.text("billing.noCycle"), tint: AsterColor.warning)
            }
            Spacer()
            if let expiry = entry.expiresAt {
              Text(expiry.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
                .font(AsterTypography.caption)
                .foregroundStyle(AsterColor.foregroundSecondary)
            }
            VStack(alignment: .trailing, spacing: 1) {
              Text(money(entry.remainingCNY))
                .font(AsterTypography.metric)
                .foregroundStyle(AsterColor.accent)
              Text("\(L.text("billing.originalPrice")) \(money(entry.priceCNY))")
                .font(AsterTypography.caption)
                .foregroundStyle(AsterColor.foregroundSecondary)
            }
          }
        }
      }
    }
  }

  private func chip(_ text: String, tint: Color) -> some View {
    Text(text)
      .font(AsterTypography.caption)
      .foregroundStyle(tint)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(tint.opacity(0.13), in: Capsule())
  }

  private var ratesSection: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(L.text("billing.rates")).font(AsterTypography.sectionTitle)
          Spacer()
          Text(
            rates.updatedAt.map {
              "\(L.text("billing.ratesUpdated")) \($0.formatted(date: .omitted, time: .shortened))"
            } ?? L.text("billing.ratesDefault")
          )
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
        }
        ForEach(ExchangeRates.supported.filter { $0 != currency }, id: \.self) { code in
          HStack {
            Text("1 \(code) \(ExchangeRates.symbols[code] ?? "")")
              .font(AsterTypography.caption)
              .foregroundStyle(AsterColor.foregroundSecondary)
            Spacer()
            Text(
              ExchangeRates.format(
                (rates.rates[currency] ?? 1) / (rates.rates[code] ?? 1), currency: currency)
            )
            .font(AsterTypography.caption.monospacedDigit())
          }
        }
      }
    }
  }

  private func money(_ cnyAmount: Double) -> String {
    ExchangeRates.format(rates.convert(cnyAmount, to: currency), currency: currency)
  }
}

#Preview {
  BillingPage().environment(MonitorStore.preview).frame(width: 1000, height: 700)
}
