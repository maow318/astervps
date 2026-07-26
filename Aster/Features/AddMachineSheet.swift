import AppKit
import Security
import SwiftUI

/// Two-step add-machine flow: ① generate a token and hand the user an install
/// command, ② verify the endpoint, confirm the TLS fingerprint (TOFU) and save.
struct AddMachineSheet: View {
  @Environment(MonitorStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  @State private var step = 1
  @State private var name = ""
  @State private var token = AddMachineSheet.generateToken()
  @State private var endpoint = ""
  @State private var fingerprint: String?
  @State private var meta: AgentMeta?
  @State private var isBusy = false
  @State private var errorMessage: String?
  @State private var showManual = false

  var body: some View {
    VStack(alignment: .leading, spacing: AsterSpacing.md) {
      Text(L.text("add.title")).font(AsterTypography.pageTitle)
      if step == 1 {
        stepOne
      } else {
        stepTwo
      }
      Spacer(minLength: 0)
      footer
    }
    .padding(AsterSpacing.lg)
    .frame(width: 560, height: 480)
  }

  // MARK: - Step 1: token + install command

  private var stepOne: some View {
    VStack(alignment: .leading, spacing: AsterSpacing.md) {
      Text(L.text("add.step1.hint"))
        .foregroundStyle(AsterColor.foregroundSecondary)
      TextField(L.text("add.name"), text: $name)
        .textFieldStyle(.roundedBorder)
      copyField(label: L.text("add.token"), value: token)
      copyField(label: L.text("add.installCommand"), value: installCommand)
      DisclosureGroup(L.text("add.manualTitle"), isExpanded: $showManual) {
        VStack(alignment: .leading, spacing: AsterSpacing.sm) {
          Text(L.text("add.manualHint"))
            .font(AsterTypography.caption)
            .foregroundStyle(AsterColor.foregroundSecondary)
          copyField(label: L.text("add.systemdUnit"), value: systemdUnit)
        }
        .padding(.top, AsterSpacing.xs)
      }
    }
  }

  // MARK: - Step 2: verify + fingerprint confirmation

  private var stepTwo: some View {
    VStack(alignment: .leading, spacing: AsterSpacing.md) {
      HStack {
        TextField(L.text("add.endpoint"), text: $endpoint)
          .textFieldStyle(.roundedBorder)
          .disableAutocorrection(true)
        Button(L.text("add.verify")) { probe() }
          .disabled(isBusy || endpoint.isEmpty)
      }
      if let errorMessage {
        Text(errorMessage)
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.offline)
      }
      if let fingerprint {
        GlassCard {
          VStack(alignment: .leading, spacing: AsterSpacing.sm) {
            Text(L.text("add.fingerprintTitle")).font(AsterTypography.sectionTitle)
            Text(formattedFingerprint(fingerprint))
              .font(.system(size: 12, design: .monospaced))
              .textSelection(.enabled)
            Text(L.text("add.fingerprintHint"))
              .font(AsterTypography.caption)
              .foregroundStyle(AsterColor.foregroundSecondary)
            if meta == nil {
              Button(L.text("add.confirm")) { confirmAndVerify() }
                .disabled(isBusy)
            }
          }
        }
      }
      if let meta {
        GlassCard {
          HStack(spacing: AsterSpacing.sm) {
            StatusDot(status: .online, diameter: 8)
            Text(L.text("add.verified")).font(AsterTypography.sectionTitle)
            Spacer()
            Text("\(L.text("add.hostInfo")): \(meta.hostname) · \(meta.os) · \(meta.cpuModel)")
              .font(AsterTypography.caption)
              .foregroundStyle(AsterColor.foregroundSecondary)
              .lineLimit(1)
          }
        }
      }
      if isBusy {
        ProgressView().controlSize(.small)
      }
    }
  }

  private var footer: some View {
    HStack {
      Button(L.text("action.cancel")) { dismiss() }
      Spacer()
      if step == 2 {
        Button(L.text("add.back")) {
          step = 1
          errorMessage = nil
        }
      }
      if step == 1 {
        Button(L.text("add.next")) { step = 2 }
          .buttonStyle(.borderedProminent)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
      } else {
        Button(L.text("add.save")) { save() }
          .buttonStyle(.borderedProminent)
          .disabled(meta == nil || fingerprint == nil)
      }
    }
  }

  // MARK: - Actions

  private func probe() {
    errorMessage = nil
    fingerprint = nil
    meta = nil
    let trimmed = endpoint.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("https://") else {
      errorMessage = L.text("agent.error.invalidEndpoint")
      return
    }
    guard !store.hasMachine(endpoint: trimmed) else {
      errorMessage = L.text("add.duplicate")
      return
    }
    endpoint = trimmed
    isBusy = true
    Task {
      defer { isBusy = false }
      do {
        fingerprint = try await AgentClient.probeFingerprint(endpoint: trimmed)
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func confirmAndVerify() {
    guard let fingerprint else { return }
    isBusy = true
    errorMessage = nil
    Task {
      defer { isBusy = false }
      do {
        meta = try await store.verifyMachine(
          endpoint: endpoint, token: token, fingerprint: fingerprint)
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func save() {
    guard let fingerprint, meta != nil else { return }
    store.addMachine(
      name: name.trimmingCharacters(in: .whitespaces), endpoint: endpoint, token: token,
      fingerprint: fingerprint)
    dismiss()
  }

  // MARK: - Helpers

  private var installCommand: String {
    AgentDistribution.installCommand(token: token) ?? L.text("add.installPending")
  }

  private var systemdUnit: String {
    """
    [Unit]
    Description=Aster Agent
    After=network-online.target

    [Service]
    ExecStart=/usr/local/bin/aster-agent --listen :9977 --token \(token)
    Restart=always

    [Install]
    WantedBy=multi-user.target
    """
  }

  private func copyField(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(AsterTypography.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
      HStack(alignment: .top) {
        Text(value)
          .font(.system(size: 12, design: .monospaced))
          .textSelection(.enabled)
          .lineLimit(4)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(value, forType: .string)
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help(L.text("action.copy"))
      }
      .padding(AsterSpacing.xs)
      .background(
        AsterColor.background3.opacity(0.5),
        in: RoundedRectangle(cornerRadius: AsterRadius.control))
    }
  }

  private func formattedFingerprint(_ value: String) -> String {
    stride(from: 0, to: value.count, by: 16).map { offset in
      let start = value.index(value.startIndex, offsetBy: offset)
      let end = value.index(start, offsetBy: min(16, value.count - offset))
      return String(value[start..<end])
    }.joined(separator: "\n")
  }

  private static func generateToken() -> String {
    var bytes = [UInt8](repeating: 0, count: 24)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

#Preview {
  AddMachineSheet().environment(MonitorStore())
}
