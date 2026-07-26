import SwiftUI

struct TagChip: View {
    let text: String; var tint: Color = AsterColor.accent
    var body: some View { Text(text).font(AsterTypography.caption.weight(.medium)).foregroundStyle(tint).padding(.horizontal, 8).padding(.vertical, 4).background(tint.opacity(0.14), in: Capsule()) }
}

#Preview { TagChip(text: "production").padding().background(AsterColor.background1) }
