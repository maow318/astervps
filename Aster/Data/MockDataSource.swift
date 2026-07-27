import Foundation

/// Demo fleet: every node differs in country, OS, hardware and load profile
/// so the whole UI vocabulary (flags, OS logos, adaptive units, status
/// colors) is visible at a glance without a single real server.
@MainActor final class MockDataSource: MonitorDataSource {
  private struct Blueprint {
    let name: String
    let city: String
    let flag: String
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
      name: "aurora-01", city: "Tokyo", flag: "🇯🇵", os: "ubuntu",
      hardware: "AMD EPYC 7502P · 32核", status: .online, tags: ["prod", "api"],
      cpu: 62, memory: 71, disk: 58, downBps: 46_000_000, upBps: 12_500_000,
      uptimeDays: 213, load: 8.4, group: 0),
    Blueprint(
      name: "harbor-hkg", city: "Hong Kong", flag: "🇭🇰", os: "windows",
      hardware: "Xeon Silver 4310 · 24核", status: .online, tags: ["rdp"],
      cpu: 34, memory: 66, disk: 81, downBps: 830_000, upBps: 214_000,
      uptimeDays: 46, load: 2.1, group: 0),
    Blueprint(
      name: "studio-cup", city: "Cupertino", flag: "🇺🇸", os: "darwin",
      hardware: "Apple M2 Ultra · 24核", status: .online, tags: ["ci", "build"],
      cpu: 88, memory: 63, disk: 44, downBps: 9_200_000, upBps: 31_000_000,
      uptimeDays: 12, load: 14.2, group: 0),
    Blueprint(
      name: "nimbus-sgp", city: "Singapore", flag: "🇸🇬", os: "alpine",
      hardware: "EPYC 9124 · 4核", status: .warning, tags: ["edge"],
      cpu: 93, memory: 89, disk: 37, downBps: 3_400_000, upBps: 1_100_000,
      uptimeDays: 158, load: 5.7, group: 1),
    Blueprint(
      name: "outback-syd", city: "Sydney", flag: "🇦🇺", os: "debian",
      hardware: "Ryzen 9 5950X · 16核", status: .offline, tags: ["backup"],
      cpu: 0, memory: 0, disk: 72, downBps: 0, upBps: 0,
      uptimeDays: 0, load: 0, group: 1),
    Blueprint(
      name: "dune-dxb", city: "Dubai", flag: "🇦🇪", os: "arch",
      hardware: "i9-13900K · 24核", status: .online, tags: ["dev"],
      cpu: 7, memory: 22, disk: 19, downBps: 4_200, upBps: 1_800,
      uptimeDays: 3.2, load: 0.4, group: 1),
    Blueprint(
      name: "helios-fra", city: "Frankfurt", flag: "🇩🇪", os: "debian",
      hardware: "EPYC 7443P · 24核", status: .online, tags: ["prod", "db"],
      cpu: 41, memory: 77, disk: 66, downBps: 18_700_000, upBps: 6_300_000,
      uptimeDays: 388, load: 6.8, group: 0),
    Blueprint(
      name: "bastion-lax", city: "Los Angeles", flag: "🇺🇸", os: "centos",
      hardware: "Xeon E5-2680 v4 · 28核", status: .online, tags: ["legacy"],
      cpu: 18, memory: 48, disk: 91, downBps: 96_000, upBps: 42_000,
      uptimeDays: 402, load: 1.9, group: 0),
    Blueprint(
      name: "glacier-hel", city: "Helsinki", flag: "🇫🇮", os: "fedora",
      hardware: "Ryzen 7 7700 · 8核", status: .online, tags: ["staging"],
      cpu: 26, memory: 39, disk: 28, downBps: 510_000, upBps: 380_000,
      uptimeDays: 27, load: 1.1, group: 1),
    Blueprint(
      name: "pampa-gru", city: "São Paulo", flag: "🇧🇷", os: "rocky",
      hardware: "EPYC 7302 · 16核", status: .online, tags: ["worker"],
      cpu: 54, memory: 58, disk: 49, downBps: 2_100_000, upBps: 940_000,
      uptimeDays: 96, load: 4.3, group: 1),
    Blueprint(
      name: "fjord-osl", city: "Oslo", flag: "🇳🇴", os: "almalinux",
      hardware: "Xeon Gold 6338 · 32核", status: .online, tags: ["cache"],
      cpu: 12, memory: 84, disk: 23, downBps: 7_600_000, upBps: 2_800_000,
      uptimeDays: 71, load: 2.6, group: 1),
    Blueprint(
      name: "lotus-icn", city: "Seoul", flag: "🇰🇷", os: "gentoo",
      hardware: "i7-12700 · 12核", status: .online, tags: ["exp"],
      cpu: 71, memory: 52, disk: 61, downBps: 1_300_000, upBps: 260_000,
      uptimeDays: 8.5, load: 7.9, group: 1),
  ]

  func loadNodes() -> [NodeSnapshot] {
    blueprints.map { blueprint in
      let info = NodeInfo(
        id: UUID(), name: blueprint.name, region: blueprint.city, flag: blueprint.flag,
        operatingSystem: blueprint.os, status: blueprint.status, tags: blueprint.tags,
        groupID: groups[blueprint.group].id, createdAt: .now, hardware: blueprint.hardware)
      let metrics = NodeMetrics(
        cpuUsage: blueprint.cpu, memoryUsage: blueprint.memory,
        swapUsage: max(0, blueprint.memory - 62), diskUsage: blueprint.disk,
        downloadBytesPerSecond: blueprint.downBps, uploadBytesPerSecond: blueprint.upBps,
        connectionCount: Int(blueprint.load * 34) + 8, processCount: Int(blueprint.load * 40) + 70,
        loadAverage: blueprint.load, uptime: blueprint.uptimeDays * 86_400,
        diskReadBytesPerSecond: blueprint.downBps * 0.3,
        diskWriteBytesPerSecond: blueprint.upBps * 0.5)
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

  func refresh(nodes: [NodeSnapshot], includeHistory: Bool) -> [NodeSnapshot] {
    nodes.map { snapshot in
      var copy = snapshot
      guard copy.info.status != .offline else { return copy }
      func jitter(_ value: Double, by amount: Double, range: ClosedRange<Double> = 0...100)
        -> Double
      { min(max(value + Double.random(in: -amount...amount), range.lowerBound), range.upperBound) }
      copy.metrics.cpuUsage = jitter(copy.metrics.cpuUsage, by: 5)
      copy.metrics.memoryUsage = jitter(copy.metrics.memoryUsage, by: 2)
      copy.metrics.diskUsage = jitter(copy.metrics.diskUsage, by: 0.4)
      copy.metrics.downloadBytesPerSecond = max(
        0, copy.metrics.downloadBytesPerSecond * Double.random(in: 0.8...1.25))
      copy.metrics.uploadBytesPerSecond = max(
        0, copy.metrics.uploadBytesPerSecond * Double.random(in: 0.8...1.25))
      copy.metrics.loadAverage = max(
        0, copy.metrics.loadAverage + Double.random(in: -0.3...0.3))
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
}
