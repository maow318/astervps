import SwiftUI

/// Fleet-wide summary strip: live clock, online ratio, lit regions,
/// cumulative traffic, current network speed and average load.
struct FleetSummaryBar: View {
  let nodes: [NodeSnapshot]

  private var onlineCount: Int {
    nodes.filter { $0.info.status == .online }.count
  }

  private var regionCount: Int {
    Set(nodes.compactMap(\.info.countryCode)).count
  }

  private var totalUp: Double {
    nodes.reduce(0) { $0 + $1.metrics.totalUploadBytes }
  }

  private var totalDown: Double {
    nodes.reduce(0) { $0 + $1.metrics.totalDownloadBytes }
  }

  private var upRate: Double {
    nodes.reduce(0) { $0 + $1.metrics.uploadBytesPerSecond }
  }

  private var downRate: Double {
    nodes.reduce(0) { $0 + $1.metrics.downloadBytesPerSecond }
  }

  private var averageLoad: Double {
    guard !nodes.isEmpty else { return 0 }
    return nodes.reduce(0) { $0 + $1.metrics.loadAverage } / Double(nodes.count)
  }

  var body: some View {
    GlassCard {
      HStack(alignment: .top, spacing: AsterSpacing.sm) {
        column(L.text("summary.time")) { clock }
        column(L.text("summary.online")) { onlineValue }
        column(L.text("summary.regions")) {
          Text("\(regionCount)").font(AsterTypography.metricMedium)
        }
        column(L.text("summary.traffic")) {
          pair(up: AsterFormat.bytes(totalUp), down: AsterFormat.bytes(totalDown))
        }
        column(L.text("summary.speed")) {
          pair(up: rateText(upRate), down: rateText(downRate))
        }
        column(L.text("overview.load")) {
          Text(String(format: "%.2f", averageLoad)).font(AsterTypography.metricMedium)
        }
      }
    }
  }

  private func column<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(spacing: 5) {
      Text(title)
        .font(AsterTypography.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
      content()
        .foregroundStyle(AsterColor.foregroundPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .frame(maxWidth: .infinity)
  }

  /// A one-second timeline keeps the clock live without touching the rest of
  /// the view tree.
  private var clock: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      Text(
        context.date.formatted(
          .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
      )
      .font(AsterTypography.metricMedium)
    }
  }

  private var onlineValue: some View {
    Text("\(onlineCount) / \(nodes.count)")
      .font(AsterTypography.metricMedium)
      .foregroundStyle(
        onlineCount == nodes.count ? AsterColor.foregroundPrimary : AsterColor.warning)
  }

  private func pair(up: String, down: String) -> some View {
    VStack(spacing: 2) {
      Text("↑ \(up)")
      Text("↓ \(down)")
    }
    .font(AsterTypography.metric)
  }

  private func rateText(_ value: Double) -> String {
    let rate = AsterFormat.rate(value)
    return "\(rate.value) \(rate.unit)"
  }
}

#Preview {
  FleetSummaryBar(nodes: MockDataSource().loadNodes())
    .padding()
    .background(AsterColor.background1)
    .frame(width: 1100)
}
