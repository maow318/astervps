import SwiftUI

struct SettingsView: View {
  @Environment(MonitorStore.self) private var store
  @State private var selected = "general"
  @State private var launchAtLogin = false
  @State private var showOffline = true

  var body: some View {
    TabView(selection: $selected) {
      general.tag("general")
      appearance.tag("appearance")
      about.tag("about")
    }
    .padding(AsterSpacing.lg)
    .navigationTitle(L.text("settings.title"))
  }

  private var general: some View {
    Form {
      Toggle(L.text("settings.launch"), isOn: $launchAtLogin)
      Toggle(L.text("settings.offline"), isOn: $showOffline)
    }
    .tabItem { Label(L.text("settings.general"), systemImage: "gearshape") }
  }

  private var appearance: some View {
    Form {
      Picker(L.text("settings.theme"), selection: .constant("system")) {
        Text(L.text("settings.system")).tag("system")
        Text(L.text("settings.dark")).tag("dark")
        Text(L.text("settings.light")).tag("light")
      }
    }
    .tabItem { Label(L.text("settings.appearance"), systemImage: "circle.lefthalf.filled") }
  }

  private var about: some View {
    VStack(spacing: AsterSpacing.sm) {
      Image(systemName: "waveform.path.ecg")
        .font(.system(size: 42))
        .foregroundStyle(AsterColor.accent)
      Text(L.text("app.name"))
        .font(AsterTypography.pageTitle)
      Text(L.text("settings.aboutText"))
        .foregroundStyle(AsterColor.foregroundSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .tabItem { Label(L.text("settings.about"), systemImage: "info.circle") }
  }
}

#Preview {
  SettingsView()
    .environment(MonitorStore.preview)
    .frame(width: 700, height: 480)
}
