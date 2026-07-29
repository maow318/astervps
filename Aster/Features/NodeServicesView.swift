import AppKit
import SwiftUI

/// Service inspection tab of the node detail page: websites, listening ports,
/// Docker containers, systemd units and installed software. Data comes from
/// /v1/services and refreshes every 60 s while this tab stays visible.
struct NodeServicesView: View {
  @Environment(MonitorStore.self) private var store
  let nodeID: UUID

  var body: some View {
    Group {
      switch store.servicesByNode[nodeID] ?? .loading {
      case .loading:
        loadingState
      case .unsupported:
        EmptyStateView(
          symbol: "arrow.up.circle.dotted", title: L.text("services.unsupported.title"),
          message: L.text("services.unsupported.message"))
      case .failed(let message):
        VStack(spacing: AsterSpacing.sm) {
          EmptyStateView(
            symbol: "exclamationmark.triangle", title: L.text("services.error"), message: message)
          Button(L.text("services.retry")) {
            Task { await store.loadServices(for: nodeID) }
          }
        }
      case .loaded(let services):
        ServicesContent(nodeID: nodeID, services: services)
      }
    }
    .task(id: nodeID) {
      while !Task.isCancelled {
        await store.loadServices(for: nodeID)
        try? await Task.sleep(for: .seconds(60))
      }
    }
  }

  private var loadingState: some View {
    VStack(spacing: AsterSpacing.md) {
      ForEach(0..<3, id: \.self) { _ in
        GlassCard {
          VStack(alignment: .leading, spacing: AsterSpacing.sm) {
            Text(verbatim: "Loading section").font(AsterTypography.sectionTitle)
            Text(verbatim: "Placeholder row while service data loads from the agent")
            Text(verbatim: "Placeholder row while service data loads")
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .redacted(reason: .placeholder)
  }
}

// MARK: - Loaded content

private struct ServicesContent: View {
  @Environment(MonitorStore.self) private var store
  let nodeID: UUID
  let services: AgentServices

  var body: some View {
    VStack(alignment: .leading, spacing: AsterSpacing.lg) {
      statusRow
      if !services.websites.isEmpty { WebsitesCard(websites: services.websites) }
      if !services.listeners.isEmpty { ListenersCard(listeners: services.listeners) }
      DockerCard(docker: services.docker)
      if let systemd = services.systemd { SystemdCard(systemd: systemd) }
      if !services.packages.isEmpty { PackagesCard(packages: services.packages) }
    }
  }

  private var statusRow: some View {
    HStack(spacing: AsterSpacing.xs) {
      Text(L.text("services.updated"))
      Text(Date(timeIntervalSince1970: TimeInterval(services.collectedAt)), style: .relative)
      if services.restricted {
        Label(L.text("services.restricted"), systemImage: "lock.shield")
          .foregroundStyle(AsterColor.warning)
      }
      Spacer()
      Button {
        Task { await store.loadServices(for: nodeID, forceRefresh: true) }
      } label: {
        Label(L.text("services.refresh"), systemImage: "arrow.clockwise")
      }
      .buttonStyle(.borderless)
    }
    .font(AsterTypography.caption)
    .foregroundStyle(AsterColor.foregroundSecondary)
  }
}

// MARK: - Websites

private struct WebsitesCard: View {
  let websites: [AgentWebsite]

  var body: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: AsterSpacing.sm) {
        SectionHeader(
          icon: "globe", title: L.text("services.websites"), count: websites.count,
          colors: [
            Color(hue: 0.6, saturation: 0.7, brightness: 0.9),
            Color(hue: 0.7, saturation: 0.65, brightness: 0.7),
          ])
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 300), spacing: AsterSpacing.xs)],
          spacing: AsterSpacing.xxs
        ) {
          ForEach(websites) { site in
            WebsiteRow(site: site)
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct WebsiteRow: View {
  let site: AgentWebsite
  @State private var hovered = false

  private var healthColor: Color {
    switch site.ok {
    case .some(true): AsterColor.online
    case .some(false): AsterColor.offline
    case .none: AsterColor.foregroundSecondary.opacity(0.4)
    }
  }

  var body: some View {
    Button {
      if let url = site.url { NSWorkspace.shared.open(url) }
    } label: {
      HStack(spacing: AsterSpacing.sm) {
        ZStack(alignment: .bottomTrailing) {
          WebsiteTile(domain: site.domain)
          Circle()
            .fill(healthColor)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(.background, lineWidth: 1.5))
            .offset(x: 2, y: 2)
        }
        VStack(alignment: .leading, spacing: 1) {
          Text(site.domain)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .lineLimit(1)
          HStack(spacing: 5) {
            Image(systemName: site.tls ? "lock.fill" : "lock.open")
              .font(.system(size: 8))
            Text(verbatim: ":\(site.port) · \(site.server)")
            if let status = site.status, status > 0 {
              Text(verbatim: "HTTP \(status)")
                .foregroundStyle(site.ok == true ? AsterColor.foregroundSecondary : AsterColor.offline)
            }
            if let latency = site.latencyMs {
              Text(verbatim: "\(latency) ms")
            }
          }
          .font(.system(size: 10, design: .rounded).monospacedDigit())
          .foregroundStyle(AsterColor.foregroundSecondary)
        }
        Spacer(minLength: AsterSpacing.xxs)
        if let days = site.certDaysLeft, days <= 30 {
          CertBadge(days: days)
        }
      }
      .padding(.horizontal, AsterSpacing.xs)
      .padding(.vertical, 6)
      .background(
        Color.primary.opacity(hovered ? 0.08 : 0.04),
        in: RoundedRectangle(cornerRadius: AsterRadius.control, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: AsterRadius.control, style: .continuous))
    }
    .buttonStyle(.plain)
    .animation(AsterAnimation.gentle, value: hovered)
    .onHover { hovered = $0 }
  }
}

/// Real favicon on a white plate; the letter avatar only while loading or
/// when the domain has no reachable favicon.
private struct WebsiteTile: View {
  let domain: String
  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        ZStack {
          RoundedRectangle(cornerRadius: 8.5, style: .continuous)
            .fill(.white)
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
          Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 8.5, style: .continuous)
            .fill(
              LinearGradient(
                colors: ServiceGlyph.letter(for: domain).colors,
                startPoint: .topLeading, endPoint: .bottomTrailing))
          Text(domain.prefix(1).uppercased())
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
        }
      }
    }
    .frame(width: 30, height: 30)
    .task(id: domain) {
      image = await IconStore.shared.favicon(domain: domain)
    }
  }
}

private struct CertBadge: View {
  let days: Int

  private var tint: Color {
    days <= 7 ? AsterColor.offline : days <= 14 ? AsterColor.warning : AsterColor.foregroundSecondary
  }

  var body: some View {
    Label(String(format: L.text("services.certDays"), days), systemImage: "checkmark.seal")
      .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(tint.opacity(0.13), in: Capsule())
      .foregroundStyle(tint)
  }
}

// MARK: - Listeners

private struct ListenersCard: View {
  let listeners: [AgentListener]
  @State private var query = ""

  private var filtered: [AgentListener] {
    let sorted = listeners.sorted { $0.port < $1.port }
    guard !query.isEmpty else { return sorted }
    return sorted.filter {
      "\($0.port)".contains(query)
        || $0.process.localizedCaseInsensitiveContains(query)
        || ($0.container ?? "").localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: AsterSpacing.sm) {
        HStack {
          SectionHeader(
            icon: "point.3.connected.trianglepath.dotted",
            title: L.text("services.listeners"), count: listeners.count,
            colors: [
              Color(hue: 0.45, saturation: 0.65, brightness: 0.8),
              Color(hue: 0.52, saturation: 0.7, brightness: 0.6),
            ])
          Spacer()
          TextField(L.text("services.searchPorts"), text: $query)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
        }
        VStack(spacing: 0) {
          ForEach(Array(filtered.enumerated()), id: \.element.id) { index, listener in
            ListenerRow(listener: listener)
            if index < filtered.count - 1 {
              Divider().opacity(0.35).padding(.leading, 42)
            }
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct ListenerRow: View {
  let listener: AgentListener

  var body: some View {
    HStack(spacing: AsterSpacing.sm) {
      RemoteIconTile(
        slugSource: listener.process,
        fallback: ServiceGlyph.for(port: listener.port, process: listener.process))
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: AsterSpacing.xxs) {
          Text(listener.process.isEmpty ? "—" : listener.process)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
          if let container = listener.container {
            TagChip(text: container)
          }
        }
        if !listener.cmdline.isEmpty {
          Text(listener.cmdline)
            .font(AsterTypography.caption)
            .foregroundStyle(AsterColor.foregroundSecondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: AsterSpacing.sm)
      VStack(alignment: .trailing, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(verbatim: "\(listener.port)")
            .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
          Text(listener.protocol.uppercased())
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(AsterColor.foregroundSecondary)
        }
        HStack(spacing: 5) {
          ScopeBadge(isPublic: listener.isPublic)
          if !listener.user.isEmpty {
            Text(listener.user)
              .font(.system(size: 10))
              .foregroundStyle(AsterColor.foregroundSecondary)
          }
          Text(listener.address)
            .font(.system(size: 10, design: .rounded).monospacedDigit())
            .foregroundStyle(AsterColor.foregroundSecondary.opacity(0.75))
        }
      }
    }
    .padding(.vertical, 7)
  }
}

/// Brand icon tile: loads the official logo (dashboard-icons CDN) on a white
/// plate and falls back to the gradient glyph while loading or when no logo
/// exists. `slugSource` is a process/image/package name; `domain` switches to
/// favicon mode for websites.
struct RemoteIconTile: View {
  var slugSource: String? = nil
  var domain: String? = nil
  let fallback: ServiceGlyph
  var size: CGFloat = 30
  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        ZStack {
          RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(.white)
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
          Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size * 0.68, height: size * 0.68)
        }
        .frame(width: size, height: size)
      } else {
        GlyphTile(glyph: fallback, size: size)
      }
    }
    .task(id: (slugSource ?? "") + (domain ?? "")) {
      if let domain {
        image = await IconStore.shared.favicon(domain: domain)
      } else if let slugSource, let slug = ServiceIconCatalog.slug(for: slugSource) {
        image = await IconStore.shared.serviceIcon(slug: slug)
      }
    }
  }
}

/// System-Settings-style colored icon tile: white symbol on a small gradient
/// rounded square. The gradient pair is what sells the premium look.
struct GlyphTile: View {
  let glyph: ServiceGlyph
  var size: CGFloat = 30

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        .fill(
          LinearGradient(
            colors: glyph.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .shadow(color: glyph.colors[0].opacity(0.35), radius: 3, y: 1)
      Image(systemName: glyph.symbol)
        .font(.system(size: size * 0.42, weight: .semibold))
        .foregroundStyle(.white)
    }
    .frame(width: size, height: size)
  }
}

struct ServiceGlyph {
  let symbol: String
  let colors: [Color]

  static func `for`(port: Int, process: String) -> ServiceGlyph {
    let name = process.lowercased()
    if name.contains("ssh") {
      return .init(symbol: "terminal.fill", colors: [Color(hue: 0.36, saturation: 0.65, brightness: 0.72), Color(hue: 0.42, saturation: 0.7, brightness: 0.55)])
    }
    if name.contains("aster-agent") {
      return .init(symbol: "waveform.path.ecg", colors: [AsterColor.accent, AsterColor.chartPalette[4]])
    }
    if name.contains("docker") || name.contains("containerd") {
      return .init(symbol: "shippingbox.fill", colors: [Color(hue: 0.55, saturation: 0.75, brightness: 0.85), Color(hue: 0.6, saturation: 0.8, brightness: 0.65)])
    }
    if ["nginx", "caddy", "httpd", "apache2"].contains(where: name.contains) || [80, 443, 8080, 8443].contains(port) {
      return .init(symbol: "globe", colors: [Color(hue: 0.6, saturation: 0.7, brightness: 0.9), Color(hue: 0.7, saturation: 0.65, brightness: 0.7)])
    }
    if ["postgres", "mysql", "mariadb", "redis", "mongo", "kvrocks"].contains(where: name.contains) || [5432, 3306, 6379, 27017].contains(port) {
      return .init(symbol: "cylinder.split.1x2.fill", colors: [Color(hue: 0.78, saturation: 0.55, brightness: 0.85), Color(hue: 0.85, saturation: 0.6, brightness: 0.65)])
    }
    if name.contains("resolve") || name.contains("dns") || port == 53 {
      return .init(symbol: "network", colors: [Color(hue: 0.08, saturation: 0.7, brightness: 0.92), Color(hue: 0.04, saturation: 0.75, brightness: 0.75)])
    }
    if ["node", "python", "java", "php", "ruby", "deno", "bun"].contains(where: name.contains) {
      return .init(symbol: "chevron.left.forwardslash.chevron.right", colors: [Color(hue: 0.66, saturation: 0.55, brightness: 0.85), Color(hue: 0.72, saturation: 0.6, brightness: 0.62)])
    }
    return .init(
      symbol: "point.3.connected.trianglepath.dotted",
      colors: [
        AsterColor.foregroundSecondary.opacity(0.75), AsterColor.foregroundSecondary.opacity(0.5),
      ])
  }

  static func letter(for domain: String) -> ServiceGlyph {
    let hue = Double(abs(domain.hashValue % 256)) / 256
    return .init(
      symbol: "", colors: [
        Color(hue: hue, saturation: 0.6, brightness: 0.85),
        Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.68, brightness: 0.62),
      ])
  }
}

private struct ScopeBadge: View {
  let isPublic: Bool

  var body: some View {
    Text(L.text(isPublic ? "services.scope.public" : "services.scope.local"))
      .font(.system(size: 9, weight: .semibold))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        (isPublic ? AsterColor.warning : AsterColor.foregroundSecondary).opacity(0.14),
        in: Capsule()
      )
      .foregroundStyle(isPublic ? AsterColor.warning : AsterColor.foregroundSecondary)
  }
}

// MARK: - Docker

private struct DockerCard: View {
  let docker: AgentDocker

  private var grouped: [(project: String?, containers: [AgentContainer])] {
    let containers = docker.containers ?? []
    let projects = Dictionary(grouping: containers, by: { $0.composeProject })
    return projects.sorted { ($0.key ?? "\u{FFFF}") < ($1.key ?? "\u{FFFF}") }
      .map { (project: $0.key, containers: $0.value) }
  }

  var body: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: AsterSpacing.sm) {
        HStack(spacing: AsterSpacing.xs) {
          SectionHeader(
            icon: "shippingbox.fill", title: "Docker", count: docker.containers?.count ?? 0,
            colors: [
              Color(hue: 0.55, saturation: 0.75, brightness: 0.85),
              Color(hue: 0.6, saturation: 0.8, brightness: 0.65),
            ])
          if let version = docker.version {
            Text("v\(version)")
              .font(AsterTypography.caption)
              .foregroundStyle(AsterColor.foregroundSecondary)
          }
          if docker.swarm.active {
            SwarmChip(swarm: docker.swarm)
          }
          Spacer()
        }
        if !docker.available {
          Text(L.text("services.dockerUnavailable"))
            .font(AsterTypography.caption)
            .foregroundStyle(AsterColor.foregroundSecondary)
        } else {
          ForEach(grouped, id: \.project) { group in
            VStack(alignment: .leading, spacing: AsterSpacing.xxs) {
              Text(group.project ?? L.text("services.standalone"))
                .font(AsterTypography.label)
                .foregroundStyle(AsterColor.foregroundSecondary)
              ForEach(group.containers) { container in
                ContainerRow(container: container)
              }
            }
          }
          if let swarmServices = docker.swarm.services, !swarmServices.isEmpty {
            Divider().opacity(0.4)
            Text(verbatim: "Swarm services")
              .font(AsterTypography.label)
              .foregroundStyle(AsterColor.foregroundSecondary)
            ForEach(swarmServices) { service in
              HStack {
                Image(systemName: "circle.hexagongrid")
                  .font(.system(size: 10))
                  .foregroundStyle(AsterColor.chartPalette[4])
                Text(service.name).font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(L.text("services.replicas")) \(service.replicas)")
                  .font(AsterTypography.caption.monospacedDigit())
                  .foregroundStyle(AsterColor.foregroundSecondary)
              }
            }
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct SwarmChip: View {
  let swarm: AgentSwarm

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "circle.hexagongrid.fill").font(.system(size: 9))
      Text(swarmText).font(.system(size: 10, weight: .semibold))
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 3)
    .background(AsterColor.chartPalette[4].opacity(0.14), in: Capsule())
    .foregroundStyle(AsterColor.chartPalette[4])
  }

  private var swarmText: String {
    var parts = ["Swarm"]
    if let role = swarm.role {
      parts.append(L.text(role == "manager" ? "services.swarm.manager" : "services.swarm.worker"))
    }
    if let nodes = swarm.nodes {
      parts.append(String(format: L.text("services.swarm.nodes"), nodes))
    }
    return parts.joined(separator: " · ")
  }
}

private struct ContainerRow: View {
  let container: AgentContainer

  private var tile: ServiceGlyph {
    container.isRunning
      ? ServiceGlyph(
        symbol: "shippingbox.fill",
        colors: [
          Color(hue: 0.55, saturation: 0.75, brightness: 0.85),
          Color(hue: 0.6, saturation: 0.8, brightness: 0.65),
        ])
      : ServiceGlyph(
        symbol: "shippingbox",
        colors: [
          AsterColor.foregroundSecondary.opacity(0.6),
          AsterColor.foregroundSecondary.opacity(0.4),
        ])
  }

  var body: some View {
    HStack(spacing: AsterSpacing.sm) {
      RemoteIconTile(slugSource: container.image + " " + container.name, fallback: tile, size: 26)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: AsterSpacing.xxs) {
          Text(container.name).font(.system(size: 12, weight: .semibold, design: .rounded))
          if container.restarts > 0 {
            Text(String(format: L.text("services.restarts"), container.restarts))
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(AsterColor.warning)
          }
        }
        Text(container.image)
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: AsterSpacing.xs)
      if container.isRunning {
        UsagePill(
          label: L.text("metric.cpu"),
          text: String(format: "%.1f%%", container.cpuPercent),
          fraction: min(container.cpuPercent / 100, 1), tint: AsterColor.chartPalette[0])
        UsagePill(
          label: L.text("metric.memory"),
          text: AsterFormat.bytes(container.memUsed),
          fraction: (container.memoryPercent ?? 0) / 100, tint: AsterColor.chartPalette[1])
      }
      if !container.ports.isEmpty {
        Text(portsText)
          .font(AsterTypography.caption.monospacedDigit())
          .foregroundStyle(AsterColor.foregroundSecondary)
      } else {
        Text(container.status)
          .font(AsterTypography.caption)
          .foregroundStyle(AsterColor.foregroundSecondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 3)
    .opacity(container.isRunning ? 1 : 0.6)
  }

  private var portsText: String {
    container.ports.map { port in
      port.host > 0 ? "\(port.host)→\(port.container)" : "\(port.container)"
    }.joined(separator: " ")
  }
}

private struct UsagePill: View {
  let label: String
  let text: String
  let fraction: Double
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 3) {
        Text(label).font(.system(size: 8.5, weight: .medium))
          .foregroundStyle(AsterColor.foregroundSecondary)
        Text(text).font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
      }
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(tint.opacity(0.18))
          Capsule().fill(fraction >= 0.85 ? AsterColor.warning : tint)
            .frame(width: geo.size.width * min(max(fraction, 0), 1))
        }
      }
      .frame(height: 3)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 5)
    .frame(width: 88)
    .background(
      tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
  }
}

// MARK: - systemd

private struct SystemdCard: View {
  let systemd: AgentSystemd
  @State private var query = ""
  @State private var expanded = false

  private var filtered: [AgentSystemdUnit] {
    guard !query.isEmpty else { return systemd.running }
    return systemd.running.filter {
      $0.name.localizedCaseInsensitiveContains(query)
        || $0.description.localizedCaseInsensitiveContains(query)
    }
  }

  private var visible: [AgentSystemdUnit] {
    expanded || !query.isEmpty ? filtered : Array(filtered.prefix(8))
  }

  var body: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: AsterSpacing.sm) {
        HStack {
          SectionHeader(
            icon: "gearshape.2.fill", title: L.text("services.systemd"),
            count: systemd.running.count,
            colors: [
              Color(hue: 0.08, saturation: 0.7, brightness: 0.92),
              Color(hue: 0.04, saturation: 0.75, brightness: 0.75),
            ])
          Spacer()
          TextField(L.text("services.searchUnits"), text: $query)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
        }
        if !systemd.failed.isEmpty {
          HStack(spacing: AsterSpacing.xs) {
            Image(systemName: "exclamationmark.octagon.fill")
              .foregroundStyle(AsterColor.offline)
            Text("\(L.text("services.failedUnits")): \(systemd.failed.joined(separator: ", "))")
              .font(AsterTypography.caption)
              .foregroundStyle(AsterColor.offline)
          }
          .padding(AsterSpacing.xs)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            AsterColor.offline.opacity(0.10),
            in: RoundedRectangle(cornerRadius: AsterRadius.control, style: .continuous))
        }
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 360), spacing: AsterSpacing.xs)],
          spacing: AsterSpacing.xxs
        ) {
          ForEach(visible) { unit in
            HStack(spacing: AsterSpacing.xs) {
              StatusDot(status: .online, diameter: 5)
              Text(unit.name.replacingOccurrences(of: ".service", with: ""))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .layoutPriority(1)
              Spacer(minLength: AsterSpacing.sm)
              Text(unit.description)
                .font(AsterTypography.caption)
                .foregroundStyle(AsterColor.foregroundSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .padding(.horizontal, AsterSpacing.xs)
            .padding(.vertical, 6)
            .background(
              Color.primary.opacity(0.035),
              in: RoundedRectangle(cornerRadius: 7, style: .continuous))
          }
        }
        if query.isEmpty && systemd.running.count > 8 {
          Button(
            expanded
              ? L.text("services.collapse")
              : "\(L.text("services.showAll")) (\(systemd.running.count))"
          ) {
            withAnimation(AsterAnimation.gentle) { expanded.toggle() }
          }
          .buttonStyle(.borderless)
          .font(AsterTypography.caption)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

// MARK: - Packages

private struct PackagesCard: View {
  let packages: [AgentPackage]

  var body: some View {
    GlassCard {
      VStack(alignment: .leading, spacing: AsterSpacing.sm) {
        SectionHeader(
          icon: "square.stack.3d.up.fill", title: L.text("services.packages"),
          count: packages.count,
          colors: [
            Color(hue: 0.66, saturation: 0.55, brightness: 0.85),
            Color(hue: 0.72, saturation: 0.6, brightness: 0.62),
          ])
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 150), spacing: AsterSpacing.xs)],
          spacing: AsterSpacing.xs
        ) {
          ForEach(packages) { item in
            HStack(spacing: AsterSpacing.xxs) {
              RemoteIconTile(
                slugSource: item.name,
                fallback: ServiceGlyph.for(port: 0, process: item.name), size: 18)
              Text(item.name)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
              Spacer(minLength: 2)
              Text(item.version)
                .font(.system(size: 10.5, design: .rounded).monospacedDigit())
                .foregroundStyle(AsterColor.foregroundSecondary)
                .lineLimit(1)
            }
            .padding(.horizontal, AsterSpacing.xs)
            .padding(.vertical, 5)
            .background(
              Color.primary.opacity(0.045),
              in: RoundedRectangle(cornerRadius: AsterRadius.control, style: .continuous))
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

// MARK: - Shared bits

private struct SectionHeader: View {
  let icon: String
  let title: String
  var count: Int? = nil
  var colors: [Color] = [AsterColor.accent, AsterColor.chartPalette[4]]

  var body: some View {
    HStack(spacing: AsterSpacing.xs) {
      GlyphTile(glyph: ServiceGlyph(symbol: icon, colors: colors), size: 26)
      Text(title).font(AsterTypography.sectionTitle)
      if let count, count > 0 {
        Text(verbatim: "\(count)")
          .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(colors[0].opacity(0.12), in: Capsule())
          .foregroundStyle(colors[0])
      }
    }
  }
}

#Preview {
  let store = MonitorStore.preview
  return ScrollView {
    NodeServicesView(nodeID: store.nodes[0].id)
      .environment(store)
      .padding()
  }
  .frame(width: 900, height: 1200)
  .background(AsterColor.background1)
}
