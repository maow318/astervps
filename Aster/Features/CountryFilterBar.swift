import SwiftUI

/// Region names come from the system, so the bar reads "日本 / 中国 / 美国"
/// in Chinese and "Japan / China / United States" in English for free.
enum CountryNaming {
  static func name(for code: String) -> String {
    Locale.current.localizedString(forRegionCode: code) ?? code
  }

  /// Region codes offered in the manual-correction picker: two-letter ISO
  /// entries only, sorted by their localized name.
  static var pickerRegions: [(code: String, name: String)] {
    Locale.Region.isoRegions
      .map(\.identifier)
      .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
      .map { (code: $0, name: name(for: $0)) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

/// Auto-derived country tabs: every country present in the fleet becomes a
/// chip, no manual grouping needed.
struct CountryFilterBar: View {
  let nodes: [NodeSnapshot]
  @Binding var selection: String?

  private var countries: [(code: String, count: Int)] {
    Dictionary(grouping: nodes.compactMap(\.info.countryCode), by: { $0 })
      .map { (code: $0.key, count: $0.value.count) }
      .sorted {
        $0.count != $1.count
          ? $0.count > $1.count
          : CountryNaming.name(for: $0.code).localizedStandardCompare(
            CountryNaming.name(for: $1.code)) == .orderedAscending
      }
  }

  var body: some View {
    if countries.count > 1 {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          Label(L.text("filter.region"), systemImage: "globe.asia.australia.fill")
            .font(AsterTypography.caption)
            .foregroundStyle(AsterColor.foregroundSecondary)
            .padding(.trailing, 2)
          chip(title: L.text("filter.all"), flag: nil, code: nil)
          ForEach(countries, id: \.code) { country in
            chip(
              title: CountryNaming.name(for: country.code),
              flag: GeoLookup.flag(countryCode: country.code),
              code: country.code)
          }
        }
        .padding(.vertical, 2)
      }
      .background(
        .ultraThinMaterial,
        in: RoundedRectangle(cornerRadius: AsterRadius.control, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: AsterRadius.control, style: .continuous)
          .stroke(Color.white.opacity(0.08), lineWidth: 1)
      }
    }
  }

  private func chip(title: String, flag: String?, code: String?) -> some View {
    let isSelected = selection == code
    return Button {
      selection = code
    } label: {
      HStack(spacing: 4) {
        Text(title)
        if let flag {
          Text(flag)
        }
      }
      .font(AsterTypography.label)
      .foregroundStyle(isSelected ? .white : AsterColor.foregroundPrimary)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        isSelected ? AsterColor.accent : Color.clear,
        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  CountryFilterBar(nodes: MockDataSource().loadNodes(), selection: .constant(nil))
    .padding()
    .background(AsterColor.background1)
    .frame(width: 900)
}
