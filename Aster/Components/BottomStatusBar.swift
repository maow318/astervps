import SwiftUI

struct BottomStatusBar<Leading: View, Trailing: View>: View {
  let summary: String
  @ViewBuilder let leading: Leading
  @ViewBuilder let trailing: Trailing
  var body: some View {
    HStack {
      leading
      Spacer()
      Text(summary).font(AsterTypography.label).foregroundStyle(AsterColor.foregroundSecondary)
        .lineLimit(1)
      Spacer()
      HStack(spacing: 8) { trailing }
    }.padding(.horizontal, AsterSpacing.md).frame(height: 48).background(.ultraThinMaterial)
      .overlay(alignment: .top) { Divider().opacity(0.45) }
  }
}

#Preview {
  BottomStatusBar(summary: "12 online · 1 offline") {
    Button("+") {}
  } trailing: {
    Button("?") {}
  }.padding().background(AsterColor.background1)
}
