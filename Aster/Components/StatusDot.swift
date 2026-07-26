import SwiftUI

struct StatusDot: View {
    let status: NodeStatus
    var diameter: CGFloat = 9

    @State private var appeared = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .shadow(color: color.opacity(status == .online ? 0.55 : 0), radius: appeared ? 3 : 0)
            .scaleEffect(appeared ? 1 : 0.72)
        .onAppear {
            guard !appeared else { return }
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
        }
            .accessibilityLabel(L.text("status.\(status.rawValue)"))
    }

    private var color: Color {
        switch status {
        case .online: AsterColor.online
        case .offline: AsterColor.offline
        case .warning: AsterColor.warning
        }
    }

}

#Preview { HStack { StatusDot(status: .online); StatusDot(status: .warning); StatusDot(status: .offline) }.padding().background(AsterColor.background1) }
