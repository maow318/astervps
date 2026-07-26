import SwiftUI

struct MetricRing: View {
    let value: Double; let label: String; var size: CGFloat = 92; var tint: Color = AsterColor.accent
    private var progress: Double { min(max(value / 100, 0), 1) }
    var body: some View {
        ZStack {
            Circle().stroke(AsterColor.foregroundSecondary.opacity(0.14), lineWidth: 7)
            Circle().trim(from: 0, to: progress).stroke(AngularGradient(colors: [tint.opacity(0.55), tint, AsterColor.chartPalette[4]], center: .center), style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 1) { Text(value, format: .number.precision(.fractionLength(0))).font(AsterTypography.metric).contentTransition(.numericText()); Text(label).font(AsterTypography.caption).foregroundStyle(AsterColor.foregroundSecondary) }
        }.frame(width: size, height: size).accessibilityElement(children: .combine)
    }
}

#Preview { MetricRing(value: 63, label: L.text("metric.cpu")).padding().background(AsterColor.background1) }
