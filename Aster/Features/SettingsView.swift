import SwiftUI

struct SettingsView: View {
    @State private var selected = "general"; @State private var launchAtLogin = false; @State private var showOffline = true
    var body: some View { TabView(selection: $selected) { general.tag("general"); appearance.tag("appearance"); connection.tag("connection"); about.tag("about") }.padding(AsterSpacing.lg).navigationTitle(L.text("settings.title")) }
    private var general: some View { Form { Toggle(L.text("settings.launch"), isOn: $launchAtLogin); Toggle(L.text("settings.offline"), isOn: $showOffline) }.tabItem { Label(L.text("settings.general"), systemImage: "gearshape") } }
    private var appearance: some View { Form { Picker(L.text("settings.theme"), selection: .constant("system")) { Text(L.text("settings.system")).tag("system"); Text(L.text("settings.dark")).tag("dark"); Text(L.text("settings.light")).tag("light") } }.tabItem { Label(L.text("settings.appearance"), systemImage: "circle.lefthalf.filled") } }
    private var connection: some View { Form { TextField(L.text("settings.endpoint"), text: .constant("")); SecureField(L.text("settings.token"), text: .constant("")); Text(L.text("settings.connectionHint")).font(.caption).foregroundStyle(.secondary) }.tabItem { Label(L.text("settings.connection"), systemImage: "network") } }
    private var about: some View { VStack(spacing: AsterSpacing.sm) { Image(systemName: "waveform.path.ecg").font(.system(size: 42)).foregroundStyle(AsterColor.accent); Text(L.text("app.name")).font(AsterTypography.pageTitle); Text(L.text("settings.aboutText")).foregroundStyle(AsterColor.foregroundSecondary) }.frame(maxWidth: .infinity, maxHeight: .infinity).tabItem { Label(L.text("settings.about"), systemImage: "info.circle") } }
}

#Preview { SettingsView().frame(width: 700, height: 480) }
