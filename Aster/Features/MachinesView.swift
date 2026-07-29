import AppKit
import SwiftUI

/// Machine management as a first-class sidebar page, styled like the rest of
/// the app: glass rows with identity, connection state, fingerprint and
/// billing at a glance.
struct MachinesView: View {
  @Environment(MonitorStore.self) private var store
  @State private var pendingDeletion: MachineConfig?
  @State private var editTarget: MachineConfig?

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: AsterSpacing.sm) {
            if store.machines.isEmpty {
              emptyState
            } else {
              ForEach(store.machines) { machine in
                MachineRow(
                  machine: machine,
                  onEdit: { editTarget = machine },
                  onDelete: { pendingDeletion = machine })
              }
              addButton
            }
          }
          .padding(AsterSpacing.lg)
        }
        StatusBar()
      }
      .background(AsterColor.background1.opacity(0.65))
      .navigationTitle(L.text("settings.machines"))
    }
    .confirmationDialog(
      L.text("machines.deleteConfirm"),
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } })
    ) {
      if let uninstall = AgentDistribution.uninstallCommand {
        Button(L.text("delete.copyAndRemove"), role: .destructive) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(uninstall, forType: .string)
          if let machine = pendingDeletion {
            store.removeMachine(machine.id)
          }
          pendingDeletion = nil
        }
      }
      Button(L.text("machines.delete"), role: .destructive) {
        if let machine = pendingDeletion {
          store.removeMachine(machine.id)
        }
        pendingDeletion = nil
      }
    } message: {
      Text(L.text("delete.uninstallHint"))
    }
    .sheet(item: $editTarget) { machine in
      MachineEditSheet(machine: machine)
    }
  }

  private var emptyState: some View {
    VStack(spacing: AsterSpacing.md) {
      EmptyStateView(
        symbol: "server.rack", title: L.text("connection.unconfigured"),
        message: L.text("machines.empty"))
      Button {
        store.isAddMachinePresented = true
      } label: {
        Label(L.text("add.title"), systemImage: "plus")
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, AsterSpacing.xl)
  }

  private var addButton: some View {
    Button {
      store.isAddMachinePresented = true
    } label: {
      Label(L.text("add.title"), systemImage: "plus")
        .frame(maxWidth: .infinity)
        .padding(.vertical, AsterSpacing.sm)
    }
    .buttonStyle(.plain)
    .background(
      AsterColor.accent.opacity(0.12),
      in: RoundedRectangle(cornerRadius: AsterRadius.control, style: .continuous))
    .foregroundStyle(AsterColor.accent)
  }
}

private struct MachineRow: View {
  @Environment(MonitorStore.self) private var store
  let machine: MachineConfig
  let onEdit: () -> Void
  let onDelete: () -> Void
  @State private var hovered = false

  private var node: NodeSnapshot? {
    store.node(id: machine.id)
  }

  private var state: ConnectionState {
    store.machineState(machine.id)
  }

  var body: some View {
    GlassCard {
      HStack(spacing: AsterSpacing.md) {
        StatusDot(status: state.dotStatus, diameter: 9)
        identity
        Spacer()
        billing
        status
        actions
      }
    }
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        if let node, !node.info.flag.isEmpty {
          Text(node.info.flag)
        }
        Text(machine.name)
          .font(AsterTypography.sectionTitle)
          .foregroundStyle(AsterColor.foregroundPrimary)
        if let node {
          OSBadge(osID: node.info.operatingSystem, size: 11)
        }
        if machine.hidden {
          Image(systemName: "eye.slash")
            .font(.caption)
            .foregroundStyle(AsterColor.foregroundSecondary)
            .help(L.text("edit.hidden"))
        }
      }
      Text(subtitleText)
        .font(AsterTypography.caption)
        .foregroundStyle(AsterColor.foregroundSecondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  private var subtitleText: String {
    var parts = [machine.endpoint]
    if let node, !node.info.region.isEmpty {
      parts.append(node.info.region)
    }
    return parts.joined(separator: "  ·  ")
  }

  private var billing: some View {
    HStack(spacing: 6) {
      if let price = machine.displayPrice {
        Text(price)
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.warning)
      }
      if let expiry = machine.expiresAt {
        let days = AsterFormat.daysLeft(until: expiry)
        Text(String(format: L.text("billing.daysLeft"), days))
          .font(AsterTypography.caption)
          .foregroundStyle(days < 14 ? AsterColor.offline : AsterColor.foregroundSecondary)
      }
    }
  }

  private var status: some View {
    VStack(alignment: .trailing, spacing: 3) {
      Text(state.localizedText)
        .font(AsterTypography.caption)
        .foregroundStyle(
          state.dotStatus == .online
            ? AsterColor.online : AsterColor.foregroundSecondary
        )
        .lineLimit(1)
      Text("\(L.text("machines.fingerprint")) …\(machine.certFingerprint.suffix(8))")
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(AsterColor.foregroundSecondary)
    }
  }

  private var actions: some View {
    HStack(spacing: 4) {
      Menu {
        if let command = AgentDistribution.statusCommand {
          Button(L.text("machines.copyStatus")) { copy(command) }
        }
        if let command = AgentDistribution.uninstallCommand {
          Button(L.text("machines.copyUninstall")) { copy(command) }
        }
      } label: {
        Image(systemName: "wrench.and.screwdriver")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .frame(width: 22)
      .help(L.text("machines.tools"))
      Button(action: onEdit) {
        Image(systemName: "pencil")
      }
      .help(L.text("machines.edit"))
      Button(action: onDelete) {
        Image(systemName: "trash")
      }
      .help(L.text("machines.delete"))
    }
    .buttonStyle(.borderless)
    .foregroundStyle(AsterColor.foregroundSecondary)
  }

  private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }
}

#Preview {
  MachinesView().environment(MonitorStore.preview).frame(width: 900, height: 600)
}
