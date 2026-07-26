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
      machines.tag("machines")
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

  private var machines: some View {
    MachineManagementView()
      .tabItem { Label(L.text("settings.machines"), systemImage: "server.rack") }
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

struct MachineManagementView: View {
  @Environment(MonitorStore.self) private var store
  @State private var pendingDeletion: MachineConfig?

  var body: some View {
    VStack(alignment: .leading, spacing: AsterSpacing.md) {
      Toggle(
        L.text("settings.demo"),
        isOn: Binding(
          get: { store.isDemoMode },
          set: { store.setDemoMode($0) }))

      if store.machines.isEmpty {
        VStack(spacing: AsterSpacing.sm) {
          Text(L.text("machines.empty"))
            .foregroundStyle(AsterColor.foregroundSecondary)
          Button(L.text("action.add")) { store.isAddMachinePresented = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List {
          ForEach(store.machines) { machine in
            machineRow(machine)
          }
        }
        .listStyle(.inset)
        HStack {
          Button {
            store.isAddMachinePresented = true
          } label: {
            Label(L.text("action.add"), systemImage: "plus")
          }
          Spacer()
        }
      }
    }
    .confirmationDialog(
      L.text("machines.deleteConfirm"),
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } })
    ) {
      Button(L.text("machines.delete"), role: .destructive) {
        if let machine = pendingDeletion {
          store.removeMachine(machine.id)
        }
        pendingDeletion = nil
      }
    }
  }

  private func machineRow(_ machine: MachineConfig) -> some View {
    let state = store.machineState(machine.id)
    return HStack(spacing: AsterSpacing.sm) {
      StatusDot(status: store.isDemoMode ? .offline : state.dotStatus, diameter: 8)
      VStack(alignment: .leading, spacing: 2) {
        Text(machine.name).font(AsterTypography.sectionTitle)
        Text(machine.endpoint)
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(store.isDemoMode ? L.text("settings.demo") : state.localizedText)
          .font(AsterTypography.caption)
          .lineLimit(1)
        Text("\(L.text("machines.fingerprint")) …\(machine.certFingerprint.suffix(8))")
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
          .monospaced()
      }
      Button(role: .destructive) {
        pendingDeletion = machine
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help(L.text("machines.delete"))
    }
    .padding(.vertical, 3)
  }
}

#Preview {
  SettingsView()
    .environment(MonitorStore())
    .frame(width: 700, height: 480)
}
