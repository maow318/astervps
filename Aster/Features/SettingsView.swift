import SwiftUI

struct SettingsView: View {
  @Environment(MonitorStore.self) private var store
  @State private var selected = "general"
  @State private var launchAtLogin = false
  @State private var showOffline = true
  @State private var endpoint = ConnectionSettings.endpoint
  @State private var token = KeychainStore.readToken() ?? ""
  @State private var demoMode = ConnectionSettings.isDemoMode
  @State private var testMessage: String?
  @State private var isTesting = false

  var body: some View {
    TabView(selection: $selected) {
      general.tag("general")
      appearance.tag("appearance")
      connection.tag("connection")
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

  private var connection: some View {
    Form {
      Toggle(L.text("settings.demo"), isOn: $demoMode)
        .onChange(of: demoMode) { _, value in store.setDemoMode(value) }

      TextField(L.text("settings.endpoint"), text: $endpoint)
        .textContentType(.URL)
        .disabled(demoMode)

      SecureField(L.text("settings.token"), text: $token)
        .disabled(demoMode)

      HStack {
        Button(L.text("settings.test")) { testConnection() }
          .disabled(demoMode || endpoint.isEmpty || isTesting)
        Button(L.text("settings.connect")) { saveAndConnect() }
          .disabled(demoMode || endpoint.isEmpty)
        connectionIndicator
      }

      Text(testMessage ?? L.text("settings.connectionHint"))
        .font(.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
    }
    .tabItem { Label(L.text("settings.connection"), systemImage: "network") }
  }

  private var connectionIndicator: some View {
    HStack(spacing: 6) {
      StatusDot(status: store.connectionState.dotStatus, diameter: 7)
      Text(connectionText)
        .font(AsterTypography.caption)
    }
  }

  private var connectionText: String {
    switch store.connectionState {
    case .unconfigured: L.text("connection.unconfigured")
    case .connecting: L.text("connection.connecting")
    case .connected: L.text("connection.connected")
    case .reconnecting: L.text("connection.reconnecting")
    case .failed: L.text("connection.failed")
    }
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

  private func testConnection() {
    isTesting = true
    Task {
      let result = await store.testConnection(endpoint: endpoint, token: token)
      isTesting = false
      switch result {
      case .success:
        testMessage = L.text("settings.testSuccess")
      case .failure(let error):
        testMessage = "\(L.text("settings.testFailed")) \(error.localizedDescription)"
      }
    }
  }

  private func saveAndConnect() {
    do {
      try KeychainStore.saveToken(token)
      Task { await store.connect(endpoint: endpoint, token: token) }
    } catch {
      testMessage = L.text("settings.testFailed")
    }
  }
}

extension Result where Success == Void, Failure == Error {
  fileprivate var isSuccess: Bool {
    if case .success = self { return true }
    return false
  }
}

#Preview {
  SettingsView()
    .environment(MonitorStore())
    .frame(width: 700, height: 480)
}
