import SwiftUI

/// Globe page: fleet distribution with a server counter, per-country markers
/// and arcs back to this Mac's own location.
struct GlobePage: View {
  @Environment(MonitorStore.self) private var store
  @Environment(\.colorScheme) private var colorScheme
  @State private var selected: GlobeMarker?
  @State private var home: (lat: Double, lon: Double)?

  private var markers: [GlobeMarker] {
    let grouped = Dictionary(grouping: store.visibleNodes.filter { $0.info.countryCode != nil }) {
      $0.info.countryCode!
    }
    return grouped.compactMap { code, nodes in
      guard let location = CountryCoordinates.location(for: code) else { return nil }
      return GlobeMarker(
        id: code, code: code, flag: GeoLookup.flag(countryCode: code),
        lat: location.lat, lon: location.lon,
        names: nodes.map(\.info.name).sorted(),
        allOnline: nodes.allSatisfy { $0.info.status == .online })
    }
    .sorted { $0.code < $1.code }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ZStack(alignment: .topLeading) {
          GlobeSceneView(
            markers: markers, home: home, isDark: colorScheme == .dark,
            selected: $selected)
          counter
          if let selected {
            tooltip(for: selected)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
              .padding(AsterSpacing.lg)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        StatusBar()
      }
      .background(AsterColor.background1.opacity(0.65))
      .navigationTitle(L.text("sidebar.globe"))
    }
    .task {
      home = await GeoLookup.selfLocation()
    }
  }

  private var counter: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 4) {
        Text(L.text("globe.totalServers"))
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
          .textCase(.uppercase)
        Text("\(store.visibleNodes.count)")
          .font(AsterTypography.metricLarge)
          .foregroundStyle(AsterColor.accent)
        Text(String(format: L.text("globe.regions"), markers.count))
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
      }
    }
    .frame(width: 160)
    .padding(AsterSpacing.lg)
  }

  private func tooltip(for marker: GlobeMarker) -> some View {
    GlassCard {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Text(marker.flag)
          Text(CountryNaming.name(for: marker.code))
            .font(AsterTypography.sectionTitle)
          Text("(\(marker.names.count))")
            .font(AsterTypography.caption)
            .foregroundStyle(AsterColor.foregroundSecondary)
        }
        Divider().opacity(0.4)
        ForEach(marker.names, id: \.self) { name in
          HStack(spacing: 5) {
            Circle()
              .fill(AsterColor.accent)
              .frame(width: 4, height: 4)
            Text(name).font(AsterTypography.label)
          }
        }
      }
    }
    .frame(maxWidth: 220)
  }
}

#Preview {
  GlobePage().environment(MonitorStore.preview).frame(width: 900, height: 640)
}
