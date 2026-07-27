import AppKit
import SwiftUI

/// Komari-style machine editor: basic info (name/token/tags/group/note/
/// hidden), billing (currency/amount/cycle/expiry/auto-renew) and the deploy
/// command regenerated from this machine's stored token.
struct MachineEditSheet: View {
  @Environment(MonitorStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  let machine: MachineConfig

  @State private var section = "basic"
  @State private var name: String
  @State private var tags: String
  @State private var group: String
  @State private var note: String
  @State private var isHidden: Bool
  @State private var countryOverride: String
  @State private var currency: String
  @State private var amountText: String
  @State private var cycle: String
  @State private var hasExpiry: Bool
  @State private var expiresAt: Date
  @State private var autoRenew: Bool

  private static let currencies = ["$", "¥", "€", "£", "₽", "₣", "₹", "₫", "฿"]

  init(machine: MachineConfig) {
    self.machine = machine
    _name = State(initialValue: machine.name)
    _tags = State(initialValue: machine.tags ?? "")
    _group = State(initialValue: machine.group ?? "")
    _note = State(initialValue: machine.note ?? "")
    _isHidden = State(initialValue: machine.hidden)
    _countryOverride = State(initialValue: machine.countryOverride ?? "")
    _currency = State(initialValue: machine.currency ?? "$")
    _amountText = State(
      initialValue: machine.priceAmount.map { String(format: "%.2f", $0) } ?? "")
    _cycle = State(initialValue: machine.billingCycle ?? "")
    _hasExpiry = State(initialValue: machine.expiresAt != nil)
    _expiresAt = State(initialValue: machine.expiresAt ?? .now.addingTimeInterval(365 * 86_400))
    _autoRenew = State(initialValue: machine.autoRenew ?? false)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AsterSpacing.md) {
      Text(L.text("machines.edit")).font(AsterTypography.pageTitle)
      Picker("", selection: $section) {
        Text(L.text("edit.basic")).tag("basic")
        Text(L.text("edit.billing")).tag("billing")
        Text(L.text("edit.deploy")).tag("deploy")
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      Group {
        switch section {
        case "billing": billing
        case "deploy": deploy
        default: basic
        }
      }
      .frame(maxHeight: .infinity)

      HStack {
        Button(L.text("action.cancel")) { dismiss() }
        Spacer()
        Button(L.text("add.save")) { save() }
          .buttonStyle(.borderedProminent)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(AsterSpacing.lg)
    .frame(width: 500, height: 460)
  }

  private var basic: some View {
    Form {
      TextField(L.text("add.name"), text: $name)
      LabeledContent(L.text("edit.token")) {
        HStack {
          Text(KeychainStore.readToken(for: machine.id) ?? "—")
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
          Button {
            if let token = KeychainStore.readToken(for: machine.id) {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(token, forType: .string)
            }
          } label: {
            Image(systemName: "doc.on.doc")
          }
          .buttonStyle(.borderless)
        }
      }
      Picker(L.text("edit.country"), selection: $countryOverride) {
        Text(autoDetectedLabel).tag("")
        Divider()
        ForEach(CountryNaming.pickerRegions, id: \.code) { region in
          Text("\(GeoLookup.flag(countryCode: region.code)) \(region.name)").tag(region.code)
        }
      }
      TextField(L.text("edit.tags"), text: $tags, prompt: Text(verbatim: "prod;api"))
      TextField(L.text("edit.group"), text: $group)
      TextField(L.text("edit.note"), text: $note, axis: .vertical)
        .lineLimit(2...4)
      Toggle(isOn: $isHidden) {
        VStack(alignment: .leading, spacing: 2) {
          Text(L.text("edit.hidden"))
          Text(L.text("edit.hiddenHint"))
            .font(AsterTypography.caption)
            .foregroundStyle(AsterColor.foregroundSecondary)
        }
      }
    }
    .formStyle(.grouped)
  }

  private var billing: some View {
    Form {
      Picker(L.text("billing.currency"), selection: $currency) {
        ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
      }
      TextField(L.text("billing.amount"), text: $amountText, prompt: Text(verbatim: "17.93"))
      Text(L.text("billing.amountHint"))
        .font(AsterTypography.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
      Picker(L.text("billing.cycle"), selection: $cycle) {
        Text("—").tag("")
        ForEach(BillingCycle.allCases) { item in
          Text(L.text(item.shortKey)).tag(item.rawValue)
        }
      }
      Toggle(L.text("billing.expiresAt"), isOn: $hasExpiry)
      if hasExpiry {
        DatePicker(L.text("billing.expiryDate"), selection: $expiresAt, displayedComponents: .date)
        Toggle(isOn: $autoRenew) {
          VStack(alignment: .leading, spacing: 2) {
            Text(L.text("billing.autoRenew"))
            Text(L.text("billing.autoRenewHint"))
              .font(AsterTypography.caption)
              .foregroundStyle(AsterColor.foregroundSecondary)
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private var deploy: some View {
    VStack(alignment: .leading, spacing: AsterSpacing.sm) {
      Text(L.text("deploy.hint"))
        .font(AsterTypography.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
      let command =
        KeychainStore.readToken(for: machine.id)
        .flatMap { AgentDistribution.installCommand(token: $0) } ?? L.text("add.installPending")
      ScrollView {
        Text(command)
          .font(.system(size: 12, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(AsterSpacing.sm)
      }
      .background(
        AsterColor.background3.opacity(0.5),
        in: RoundedRectangle(cornerRadius: AsterRadius.control))
      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
      } label: {
        Label(L.text("action.copy"), systemImage: "doc.on.doc")
      }
    }
  }

  /// Shows what the geo lookup found so the user can tell whether the
  /// override is actually needed.
  private var autoDetectedLabel: String {
    guard let detected = machine.countryCode else { return L.text("edit.countryAuto") }
    return "\(L.text("edit.countryAuto")) (\(GeoLookup.flag(countryCode: detected)) \(CountryNaming.name(for: detected)))"
  }

  private func save() {
    var updated = machine
    updated.name = name.trimmingCharacters(in: .whitespaces)
    updated.tags = tags.isEmpty ? nil : tags
    updated.group = group.trimmingCharacters(in: .whitespaces).isEmpty ? nil : group
    updated.note = note.isEmpty ? nil : note
    updated.isHidden = isHidden ? true : nil
    updated.countryOverride = countryOverride.isEmpty ? nil : countryOverride
    updated.currency = currency
    updated.priceAmount = Double(amountText.replacingOccurrences(of: ",", with: "."))
    updated.billingCycle = cycle.isEmpty ? nil : cycle
    updated.expiresAt = hasExpiry ? expiresAt : nil
    updated.autoRenew = (hasExpiry && autoRenew) ? true : nil
    store.updateMachine(updated)
    dismiss()
  }
}

#Preview {
  MachineEditSheet(
    machine: MachineConfig(
      id: UUID(), name: "RN", endpoint: "https://1.2.3.4:9977", certFingerprint: "abc",
      createdAt: .now)
  ).environment(MonitorStore.preview)
}
