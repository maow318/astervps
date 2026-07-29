import Foundation

/// Demo fleet: every node differs in country, OS, hardware and load profile
/// so the whole UI vocabulary (flags, OS logos, adaptive units, status
/// colors) is visible at a glance without a single real server.
@MainActor final class MockDataSource: MonitorDataSource {
  private struct Blueprint {
    let name: String
    let city: String
    let country: String
    let os: String
    let hardware: String
    let status: NodeStatus
    let tags: [String]
    let cpu: Double
    let memory: Double
    let disk: Double
    let downBps: Double
    let upBps: Double
    let uptimeDays: Double
    let load: Double
    let group: Int
  }

  private let groups = [
    NodeGroup(id: UUID(), name: "Production", symbol: "shippingbox.fill", nodeIDs: []),
    NodeGroup(
      id: UUID(), name: "Edge", symbol: "point.3.connected.trianglepath.dotted", nodeIDs: []),
  ]

  private let blueprints: [Blueprint] = [
    Blueprint(
      name: "aurora-01", city: "Tokyo", country: "JP", os: "ubuntu",
      hardware: "AMD EPYC 7502P · 32核", status: .online, tags: ["prod", "api"],
      cpu: 62, memory: 71, disk: 58, downBps: 46_000_000, upBps: 12_500_000,
      uptimeDays: 213, load: 8.4, group: 0),
    Blueprint(
      name: "harbor-hkg", city: "Hong Kong", country: "HK", os: "windows",
      hardware: "Xeon Silver 4310 · 24核", status: .online, tags: ["rdp"],
      cpu: 34, memory: 66, disk: 81, downBps: 830_000, upBps: 214_000,
      uptimeDays: 46, load: 2.1, group: 0),
    Blueprint(
      name: "studio-cup", city: "Cupertino", country: "US", os: "darwin",
      hardware: "Apple M2 Ultra · 24核", status: .online, tags: ["ci", "build"],
      cpu: 88, memory: 63, disk: 44, downBps: 9_200_000, upBps: 31_000_000,
      uptimeDays: 12, load: 14.2, group: 0),
    Blueprint(
      name: "nimbus-sgp", city: "Singapore", country: "SG", os: "alpine",
      hardware: "EPYC 9124 · 4核", status: .warning, tags: ["edge"],
      cpu: 93, memory: 89, disk: 37, downBps: 3_400_000, upBps: 1_100_000,
      uptimeDays: 158, load: 5.7, group: 1),
    Blueprint(
      name: "outback-syd", city: "Sydney", country: "AU", os: "debian",
      hardware: "Ryzen 9 5950X · 16核", status: .offline, tags: ["backup"],
      cpu: 0, memory: 0, disk: 72, downBps: 0, upBps: 0,
      uptimeDays: 0, load: 0, group: 1),
    Blueprint(
      name: "dune-dxb", city: "Dubai", country: "AE", os: "arch",
      hardware: "i9-13900K · 24核", status: .online, tags: ["dev"],
      cpu: 7, memory: 22, disk: 19, downBps: 4_200, upBps: 1_800,
      uptimeDays: 3.2, load: 0.4, group: 1),
    Blueprint(
      name: "helios-fra", city: "Frankfurt", country: "DE", os: "debian",
      hardware: "EPYC 7443P · 24核", status: .online, tags: ["prod", "db"],
      cpu: 41, memory: 77, disk: 66, downBps: 18_700_000, upBps: 6_300_000,
      uptimeDays: 388, load: 6.8, group: 0),
    Blueprint(
      name: "bastion-lax", city: "Los Angeles", country: "US", os: "centos",
      hardware: "Xeon E5-2680 v4 · 28核", status: .online, tags: ["legacy"],
      cpu: 18, memory: 48, disk: 91, downBps: 96_000, upBps: 42_000,
      uptimeDays: 402, load: 1.9, group: 0),
    Blueprint(
      name: "glacier-hel", city: "Helsinki", country: "FI", os: "fedora",
      hardware: "Ryzen 7 7700 · 8核", status: .online, tags: ["staging"],
      cpu: 26, memory: 39, disk: 28, downBps: 510_000, upBps: 380_000,
      uptimeDays: 27, load: 1.1, group: 1),
    Blueprint(
      name: "pampa-gru", city: "São Paulo", country: "BR", os: "rocky",
      hardware: "EPYC 7302 · 16核", status: .online, tags: ["worker"],
      cpu: 54, memory: 58, disk: 49, downBps: 2_100_000, upBps: 940_000,
      uptimeDays: 96, load: 4.3, group: 1),
    Blueprint(
      name: "fjord-osl", city: "Oslo", country: "NO", os: "almalinux",
      hardware: "Xeon Gold 6338 · 32核", status: .online, tags: ["cache"],
      cpu: 12, memory: 84, disk: 23, downBps: 7_600_000, upBps: 2_800_000,
      uptimeDays: 71, load: 2.6, group: 1),
    Blueprint(
      name: "lotus-icn", city: "Seoul", country: "KR", os: "gentoo",
      hardware: "i7-12700 · 12核", status: .online, tags: ["exp"],
      cpu: 71, memory: 52, disk: 61, downBps: 1_300_000, upBps: 260_000,
      uptimeDays: 8.5, load: 7.9, group: 1),
  ]

  /// Capacities per node (GB): memory, swap (0 = OFF), disk.
  private let capacityByName: [String: (mem: Double, swap: Double, disk: Double)] = [
    "aurora-01": (64, 8, 960), "harbor-hkg": (32, 4, 500), "studio-cup": (192, 0, 4000),
    "nimbus-sgp": (8, 1, 160), "outback-syd": (32, 2, 1000), "dune-dxb": (64, 0, 2000),
    "helios-fra": (48, 8, 1920), "bastion-lax": (64, 16, 480), "glacier-hel": (32, 0, 512),
    "pampa-gru": (32, 4, 640), "fjord-osl": (128, 8, 960), "lotus-icn": (32, 0, 1000),
  ]

  func loadNodes() -> [NodeSnapshot] {
    blueprints.map { blueprint in
      let info = NodeInfo(
        id: UUID(), name: blueprint.name, region: blueprint.city, flag: GeoLookup.flag(countryCode: blueprint.country),
        operatingSystem: blueprint.os, status: blueprint.status, tags: blueprint.tags,
        groupID: groups[blueprint.group].id, createdAt: .now, hardware: blueprint.hardware,
        countryCode: blueprint.country)
      let capacity = capacityByName[blueprint.name] ?? (16, 0, 320)
      let gigabyte = 1_000_000_000.0
      let swapUsage = capacity.swap > 0 ? max(0, blueprint.memory - 62) : 0
      let uptimeSeconds = blueprint.uptimeDays * 86_400
      let metrics = NodeMetrics(
        cpuUsage: blueprint.cpu, memoryUsage: blueprint.memory,
        swapUsage: swapUsage, diskUsage: blueprint.disk,
        downloadBytesPerSecond: blueprint.downBps, uploadBytesPerSecond: blueprint.upBps,
        connectionCount: Int(blueprint.load * 34) + 8, processCount: Int(blueprint.load * 40) + 70,
        loadAverage: blueprint.load, uptime: uptimeSeconds,
        diskReadBytesPerSecond: blueprint.downBps * 0.3,
        diskWriteBytesPerSecond: blueprint.upBps * 0.5,
        memoryUsedBytes: capacity.mem * gigabyte * blueprint.memory / 100,
        memoryTotalBytes: capacity.mem * gigabyte,
        swapUsedBytes: capacity.swap * gigabyte * swapUsage / 100,
        swapTotalBytes: capacity.swap * gigabyte,
        diskUsedBytes: capacity.disk * gigabyte * blueprint.disk / 100,
        diskTotalBytes: capacity.disk * gigabyte,
        totalUploadBytes: blueprint.upBps * uptimeSeconds * 0.4,
        totalDownloadBytes: blueprint.downBps * uptimeSeconds * 0.4,
        load5: blueprint.load * 0.9, load15: blueprint.load * 0.75)
      return NodeSnapshot(
        info: info, metrics: metrics,
        history: history(cpu: blueprint.cpu, downBps: blueprint.downBps))
    }
  }

  func loadGroups() -> [NodeGroup] {
    groups
  }

  func loadAlerts() -> [AlertItem] {
    []
  }

  private lazy var baselineByName = Dictionary(
    uniqueKeysWithValues: blueprints.map { ($0.name, $0) })

  func refresh(nodes: [NodeSnapshot], includeHistory: Bool) -> [NodeSnapshot] {
    nodes.map { snapshot in
      var copy = snapshot
      guard copy.info.status != .offline, let base = baselineByName[copy.info.name] else {
        return copy
      }
      // Jitter around the blueprint baseline (mean reversion). A random walk
      // on the current value drifts without bound when left running — an
      // overnight session once inflated rates into the exa-scale.
      func around(_ value: Double, spread: Double, range: ClosedRange<Double> = 0...100) -> Double
      {
        min(max(value + Double.random(in: -spread...spread), range.lowerBound), range.upperBound)
      }
      copy.metrics.cpuUsage = around(base.cpu, spread: 6)
      copy.metrics.memoryUsage = around(base.memory, spread: 3)
      copy.metrics.diskUsage = around(base.disk, spread: 0.5)
      copy.metrics.downloadBytesPerSecond = base.downBps * Double.random(in: 0.75...1.3)
      copy.metrics.uploadBytesPerSecond = base.upBps * Double.random(in: 0.75...1.3)
      copy.metrics.loadAverage = max(0, base.load + Double.random(in: -0.4...0.4))
      if includeHistory {
        copy.history.cpu = append(copy.metrics.cpuUsage, to: copy.history.cpu)
        copy.history.memory = append(copy.metrics.memoryUsage, to: copy.history.memory)
        copy.history.download = append(
          copy.metrics.downloadBytesPerSecond / 1_000_000, to: copy.history.download)
        copy.history.upload = append(
          copy.metrics.uploadBytesPerSecond / 1_000_000, to: copy.history.upload)
      }
      return copy
    }
  }

  func history(for node: NodeSnapshot, hours: Int) -> MetricsHistory {
    history(cpu: node.metrics.cpuUsage, downBps: node.metrics.downloadBytesPerSecond, hours: hours)
  }

  private func history(cpu: Double, downBps: Double, hours: Int = 2) -> MetricsHistory {
    let count = hours <= 6 ? 36 : 60
    let interval = Double(hours * 3_600) / Double(count - 1)
    func series(_ base: Double, spread: Double) -> [MetricSample] {
      (0..<count).map { offset in
        MetricSample(
          id: UUID(), date: .now.addingTimeInterval(Double(offset - count + 1) * interval),
          value: max(0, base + Double.random(in: -spread...spread)))
      }
    }
    let downMB = downBps / 1_000_000
    return MetricsHistory(
      cpu: series(cpu, spread: 9), memory: series(min(cpu + 13, 92), spread: 6),
      download: series(downMB, spread: downMB * 0.45),
      upload: series(downMB * 0.35, spread: downMB * 0.2),
      diskRead: series(downMB * 0.3, spread: downMB * 0.1),
      diskWrite: series(downMB * 0.15, spread: downMB * 0.08))
  }

  private func append(_ value: Double, to samples: [MetricSample]) -> [MetricSample] {
    Array((samples + [MetricSample(id: UUID(), date: .now, value: value)]).suffix(28))
  }

  /// Sample /v1/sensors payload (Mac-mini-like SMC readout).
  static func sampleSensors() -> AgentSensors {
    AgentSensors(
      available: true,
      fans: [AgentFan(label: "Fan 1", rpm: 1001)],
      temps: [
        AgentTemp(label: "TC0a", celsius: 52.1), AgentTemp(label: "TCMz", celsius: 79.0),
        AgentTemp(label: "TG0b", celsius: 48.6), AgentTemp(label: "TH0a", celsius: 44.2),
        AgentTemp(label: "TH0b", celsius: 44.3), AgentTemp(label: "TMVR", celsius: 53.3),
        AgentTemp(label: "TPD0", celsius: 58.4), AgentTemp(label: "TW0P", celsius: 40.1),
        AgentTemp(label: "Ta00", celsius: 46.0),
      ])
  }

  /// Sample /v1/processes payload for the menu-bar hover popover.
  static func sampleProcesses() -> [AgentProcess] {
    [
      AgentProcess(pid: 612, name: "nginx", cpuPercent: 12.4, memBytes: 84_000_000, user: "root"),
      AgentProcess(pid: 890, name: "postgres", cpuPercent: 8.1, memBytes: 412_000_000, user: "postgres"),
      AgentProcess(pid: 2210, name: "node", cpuPercent: 6.8, memBytes: 265_000_000, user: "deploy"),
      AgentProcess(pid: 903, name: "redis-server", cpuPercent: 2.2, memBytes: 96_000_000, user: "redis"),
      AgentProcess(pid: 1102, name: "dockerd", cpuPercent: 1.4, memBytes: 152_000_000, user: "root"),
      AgentProcess(pid: 415, name: "systemd-journald", cpuPercent: 0.6, memBytes: 48_000_000, user: "root"),
    ]
  }

  /// Realistic /v1/services payload for previews and snapshot verification:
  /// public + local listeners, compose-grouped containers, an active swarm,
  /// a failed unit and both package sources.
  static func sampleServices() -> AgentServices {
    AgentServices(
      collectedAt: Int64(Date.now.timeIntervalSince1970) - 22,
      restricted: false,
      disks: [
        AgentDisk(mount: "/", total: 494_380_000_000, used: 189_850_000_000),
        AgentDisk(mount: "/Volumes/闪迪", total: 1_000_000_000_000, used: 48_040_000_000),
      ],
      listeners: [
        AgentListener(
          port: 443, protocol: "tcp", address: "0.0.0.0", scope: "public", pid: 612,
          process: "nginx", cmdline: "nginx: master process /usr/sbin/nginx", user: "root",
          container: nil),
        AgentListener(
          port: 80, protocol: "tcp", address: "0.0.0.0", scope: "public", pid: 612,
          process: "nginx", cmdline: "nginx: master process /usr/sbin/nginx", user: "root",
          container: nil),
        AgentListener(
          port: 22, protocol: "tcp", address: "0.0.0.0", scope: "public", pid: 1102,
          process: "sshd", cmdline: "sshd: /usr/sbin/sshd -D", user: "root", container: nil),
        AgentListener(
          port: 8080, protocol: "tcp", address: "0.0.0.0", scope: "public", pid: 2210,
          process: "docker-proxy", cmdline: "/usr/bin/docker-proxy -proto tcp", user: "root",
          container: "blog-web"),
        AgentListener(
          port: 5432, protocol: "tcp", address: "127.0.0.1", scope: "local", pid: 890,
          process: "postgres", cmdline: "/usr/lib/postgresql/16/bin/postgres", user: "postgres",
          container: nil),
        AgentListener(
          port: 6379, protocol: "tcp", address: "127.0.0.1", scope: "local", pid: 903,
          process: "redis-server", cmdline: "redis-server 127.0.0.1:6379", user: "redis",
          container: nil),
        AgentListener(
          port: 53, protocol: "udp", address: "127.0.0.53", scope: "local", pid: 401,
          process: "systemd-resolve", cmdline: "/lib/systemd/systemd-resolved", user: "systemd-resolve",
          container: nil),
      ],
      websites: [
        AgentWebsite(domain: "blog.example.com", server: "nginx", port: 443, tls: true, status: 200, latencyMs: 12, ok: true, certDaysLeft: 71),
        AgentWebsite(domain: "api.example.com", server: "nginx", port: 443, tls: true, status: 301, latencyMs: 8, ok: true, certDaysLeft: 9),
        AgentWebsite(domain: "status.example.com", server: "caddy", port: 443, tls: true, status: 502, latencyMs: 41, ok: false, certDaysLeft: 55),
        AgentWebsite(domain: "legacy.example.com", server: "nginx", port: 8080, tls: false, status: 200, latencyMs: 3, ok: true, certDaysLeft: nil),
      ],
      docker: AgentDocker(
        available: true, reason: nil, version: "27.1.1",
        swarm: AgentSwarm(
          active: true, role: "manager", nodes: 3,
          services: [
            AgentSwarmService(name: "ingress-proxy", replicas: "2"),
            AgentSwarmService(name: "metrics-shipper", replicas: "global"),
          ]),
        containers: [
          AgentContainer(
            id: "ab12cd34ef56", name: "blog-web", image: "ghcr.io/example/blog:1.4",
            state: "running", status: "Up 3 days", composeProject: "blog",
            composeService: "web", ports: [AgentContainerPort(host: 8080, container: 80, protocol: "tcp")],
            cpuPercent: 2.4, memUsed: 210_000_000, memLimit: 536_870_912, restarts: 0),
          AgentContainer(
            id: "cd34ef56ab12", name: "blog-db", image: "postgres:16-alpine",
            state: "running", status: "Up 3 days", composeProject: "blog",
            composeService: "db", ports: [],
            cpuPercent: 0.6, memUsed: 148_000_000, memLimit: 0, restarts: 1),
          AgentContainer(
            id: "ef56ab12cd34", name: "backup-runner", image: "restic/restic:0.17",
            state: "exited", status: "Exited (0) 5 hours ago", composeProject: nil,
            composeService: nil, ports: [],
            cpuPercent: 0, memUsed: 0, memLimit: 0, restarts: 0),
        ]),
      systemd: AgentSystemd(
        running: [
          AgentSystemdUnit(name: "nginx.service", description: "A high performance web server"),
          AgentSystemdUnit(name: "docker.service", description: "Docker Application Container Engine"),
          AgentSystemdUnit(name: "postgresql.service", description: "PostgreSQL RDBMS"),
          AgentSystemdUnit(name: "redis-server.service", description: "Advanced key-value store"),
          AgentSystemdUnit(name: "ssh.service", description: "OpenBSD Secure Shell server"),
          AgentSystemdUnit(name: "fail2ban.service", description: "Fail2Ban Service"),
          AgentSystemdUnit(name: "cron.service", description: "Regular background program processing daemon"),
          AgentSystemdUnit(name: "aster-agent.service", description: "Aster Agent"),
          AgentSystemdUnit(name: "systemd-journald.service", description: "Journal Service"),
          AgentSystemdUnit(name: "unattended-upgrades.service", description: "Unattended Upgrades Shutdown"),
        ],
        failed: ["certbot-renew.service"]),
      packages: [
        AgentPackage(name: "docker", version: "27.1.1", source: "bin"),
        AgentPackage(name: "fail2ban", version: "1.0.2-3", source: "pkg"),
        AgentPackage(name: "go", version: "1.22.5", source: "bin"),
        AgentPackage(name: "nginx", version: "1.24.0-2ubuntu7", source: "pkg"),
        AgentPackage(name: "node", version: "20.11.1", source: "bin"),
        AgentPackage(name: "postgresql", version: "16.3-1", source: "pkg"),
        AgentPackage(name: "python3", version: "3.12.3", source: "bin"),
        AgentPackage(name: "redis-server", version: "7.0.15-1", source: "pkg"),
        AgentPackage(name: "ufw", version: "0.36.2-6", source: "pkg"),
      ])
  }
}
