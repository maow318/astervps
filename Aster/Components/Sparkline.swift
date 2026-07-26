import SwiftUI
import Charts

struct Sparkline: View {
    let samples: [MetricSample]; var tint: Color = AsterColor.accent; var height: CGFloat = 30
    var body: some View {
        Chart(samples) { sample in
            AreaMark(x: .value("time", sample.date), y: .value("value", sample.value)).foregroundStyle(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0.01)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("time", sample.date), y: .value("value", sample.value)).foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }.chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden).frame(height: height).accessibilityLabel(L.text("accessibility.trend"))
    }
}

#Preview { Sparkline(samples: MockDataSource().loadNodes()[0].history.cpu).padding().background(AsterColor.background1) }
