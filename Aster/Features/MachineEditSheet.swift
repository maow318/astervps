import SwiftUI

/// Edit a machine's display name and optional billing note (price text +
/// expiry date, Komari-style "余 X 天" on cards and in the table).
struct MachineEditSheet: View {
  @Environment(MonitorStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  let machine: MachineConfig
  @State private var name: String
  @State private var price: String
  @State private var hasExpiry: Bool
  @State private var expiresAt: Date

  init(machine: MachineConfig) {
    self.machine = machine
    _name = State(initialValue: machine.name)
    _price = State(initialValue: machine.price ?? "")
    _hasExpiry = State(initialValue: machine.expiresAt != nil)
    _expiresAt = State(initialValue: machine.expiresAt ?? .now.addingTimeInterval(365 * 86_400))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AsterSpacing.md) {
      Text(L.text("machines.edit")).font(AsterTypography.pageTitle)
      Form {
        TextField(L.text("add.name"), text: $name)
        TextField(L.text("billing.price"), text: $price, prompt: Text(verbatim: "$17.93/年"))
        Toggle(L.text("billing.expiresAt"), isOn: $hasExpiry)
        if hasExpiry {
          DatePicker(
            L.text("billing.expiryDate"), selection: $expiresAt, displayedComponents: .date)
        }
      }
      .formStyle(.grouped)
      HStack {
        Button(L.text("action.cancel")) { dismiss() }
        Spacer()
        Button(L.text("add.save")) {
          store.updateMachine(
            machine.id, name: name, price: price, expiresAt: hasExpiry ? expiresAt : nil)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(AsterSpacing.lg)
    .frame(width: 420, height: 320)
  }
}

#Preview {
  MachineEditSheet(
    machine: MachineConfig(
      id: UUID(), name: "RN", endpoint: "https://1.2.3.4:9977", certFingerprint: "abc",
      createdAt: .now)
  ).environment(MonitorStore.preview)
}
