import SwiftUI

struct StatusDot: View {
    let status: NodeStatus
    var diameter: CGFloat = 9

    @State private var isVisible = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { timeline in
            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
                .shadow(color: color.opacity(breathingOpacity(at: timeline.date)), radius: status == .online && isVisible ? 3 : 0)
                .opacity(status == .online && isVisible ? breathingOpacity(at: timeline.date) : 1)
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
            .accessibilityLabel(L.text("status.\(status.rawValue)"))
    }

    private var color: Color {
        switch status {
        case .online: AsterColor.online
        case .offline: AsterColor.offline
        case .warning: AsterColor.warning
        }
    }

    private func breathingOpacity(at date: Date) -> Double {
        guard status == .online, isVisible else { return 1 }
        return 0.76 + (sin(date.timeIntervalSinceReferenceDate * .pi) + 1) * 0.12
    }
}

#Preview { HStack { StatusDot(status: .online); StatusDot(status: .warning); StatusDot(status: .offline) }.padding().background(AsterColor.background1) }
