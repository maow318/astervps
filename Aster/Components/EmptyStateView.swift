import SwiftUI

struct EmptyStateView: View {
    let symbol: String; let title: String; let message: String
    var body: some View { VStack(spacing: AsterSpacing.sm) { Image(systemName: symbol).font(.system(size: 42, weight: .light)).foregroundStyle(AsterColor.foregroundSecondary.opacity(0.55)); Text(title).font(AsterTypography.sectionTitle); Text(message).font(.callout).foregroundStyle(AsterColor.foregroundSecondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(AsterSpacing.xl) }
}

#Preview { EmptyStateView(symbol: "bell.slash", title: L.text("alerts.empty.title"), message: L.text("alerts.empty.message")).frame(width: 360, height: 240).background(AsterColor.background1) }
