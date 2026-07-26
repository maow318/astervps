import SwiftUI

struct GlassCard<Content: View>: View {
    var selected = false; @ViewBuilder let content: Content; @State private var hovered = false
    var body: some View {
        content.padding(AsterSpacing.md).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AsterRadius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: AsterRadius.card, style: .continuous).stroke(selected ? AsterColor.accent.opacity(0.7) : Color.white.opacity(hovered ? 0.20 : 0.08), lineWidth: selected ? 1.5 : 1) }
            .shadow(color: .black.opacity(hovered ? 0.16 : 0.08), radius: hovered ? 16 : 8, y: hovered ? 7 : 3)
            .scaleEffect(hovered ? 1.008 : 1).offset(y: hovered ? -2 : 0).animation(AsterAnimation.lift, value: hovered).onHover { hovered = $0 }
    }
}

#Preview { GlassCard { Text("Aster").font(AsterTypography.sectionTitle); Text("Glass card") }.frame(width: 220).padding().background(AsterColor.background1) }
