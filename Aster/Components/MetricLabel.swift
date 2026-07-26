import SwiftUI

struct MetricLabel: View {
  let symbol: String
  let value: String
  let unit: String
  var tint: Color = AsterColor.foregroundSecondary
  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: symbol).font(.caption).foregroundStyle(tint)
      Text(value).font(AsterTypography.metric).contentTransition(.numericText())
      Text(unit).font(AsterTypography.caption).foregroundStyle(AsterColor.foregroundSecondary)
    }.accessibilityElement(children: .combine)
  }
}

#Preview {
  MetricLabel(symbol: "arrow.down", value: "2.3", unit: "MB/s", tint: AsterColor.chartPalette[1])
    .padding().background(AsterColor.background1)
}
