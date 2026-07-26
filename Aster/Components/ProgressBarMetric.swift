import SwiftUI

struct ProgressBarMetric: View {
  let value: Double
  let label: String
  var tint: Color = AsterColor.chartPalette[3]
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(label).font(AsterTypography.caption).foregroundStyle(AsterColor.foregroundSecondary)
        Spacer()
        Text(value, format: .percent.precision(.fractionLength(0))).font(
          AsterTypography.caption.monospacedDigit())
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(AsterColor.foregroundSecondary.opacity(0.13))
          Capsule().fill(tint).frame(width: proxy.size.width * min(max(value, 0), 1))
        }
      }.frame(height: 5)
    }.accessibilityElement(children: .combine)
  }
}

#Preview {
  ProgressBarMetric(value: 0.72, label: L.text("metric.disk")).frame(width: 180).padding()
    .background(AsterColor.background1)
}
