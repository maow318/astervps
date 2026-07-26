import SwiftUI

enum AsterColor {
  static let background1 = Color("AsterBackground1")
  static let background2 = Color("AsterBackground2")
  static let background3 = Color("AsterBackground3")
  static let foregroundPrimary = Color("AsterForegroundPrimary")
  static let foregroundSecondary = Color("AsterForegroundSecondary")
  static let accent = Color.accentColor
  static let online = Color("AsterOnline")
  static let offline = Color("AsterOffline")
  static let warning = Color("AsterWarning")
  static let chartPalette = (1...6).map { Color("AsterChart\($0)") }
}

enum AsterTypography {
  static let pageTitle = Font.system(size: 28, weight: .bold, design: .rounded)
  static let sectionTitle = Font.system(size: 17, weight: .semibold, design: .rounded)
  static let metricLarge = Font.system(size: 30, weight: .bold, design: .rounded).monospacedDigit()
  static let metric = Font.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit()
  static let label = Font.system(size: 12, weight: .medium)
  static let caption = Font.system(size: 11, weight: .regular)
}

enum AsterSpacing {
  static let xxs: CGFloat = 4
  static let xs: CGFloat = 8
  static let sm: CGFloat = 12
  static let md: CGFloat = 16
  static let lg: CGFloat = 24
  static let xl: CGFloat = 32
}

enum AsterRadius {
  static let card: CGFloat = 18
  static let control: CGFloat = 10
  static let chip: CGFloat = 999
}
enum AsterAnimation {
  static let gentle = Animation.easeOut(duration: 0.22)
  static let lift = Animation.spring(response: 0.28, dampingFraction: 0.8)
  static let breathe = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
}

enum L {
  static func text(_ key: String) -> String { String(localized: String.LocalizationValue(key)) }
}
