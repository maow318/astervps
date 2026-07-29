import Foundation
import UserNotifications

/// Threshold bookkeeping per node. "Sustained" rules track when the value
/// first crossed the threshold; hysteresis prevents flapping at the edge.
struct AlertRuntime {
  var cpuHighSince: Date?
  var memoryHighSince: Date?
  var diskAlerted = false
  var knownFailedUnits: Set<String> = []
  var restartCounts: [String: Int] = [:]
  var certAlerted: Set<String> = []
  var servicesSeeded = false
  var lastFired: [String: Date] = [:]
}

/// Alert engine. Metric rules run on every poll; service rules run whenever
/// /v1/services data lands. Every rule is edge-triggered with a cooldown so
/// a persistent condition produces one alert, not a stream.
extension MonitorStore {
  private static let sustainInterval: TimeInterval = 300
  private static let fireCooldown: TimeInterval = 6 * 3600
  private static let alertsDefaultsKey = "aster.alerts"
  private static let maxStoredAlerts = 200

  // MARK: metric rules

  func evaluateMetricAlerts(for id: UUID, previousStatus: NodeStatus?) {
    guard let node = node(id: id) else { return }
    var runtime = alertRuntime[id] ?? AlertRuntime()
    defer { alertRuntime[id] = runtime }

    if let previousStatus, previousStatus != node.info.status {
      if node.info.status == .offline {
        fire(&runtime, node: node, key: "offline", severity: .offline, title: L.text("alert.offline"))
      } else if previousStatus == .offline, runtime.lastFired["offline"] != nil {
        // Only announce recovery for outages we alerted on; the first
        // successful poll after app launch is not a recovery.
        fire(&runtime, node: node, key: "online", severity: .online, title: L.text("alert.online"))
      }
    }
    guard node.info.status != .offline else {
      runtime.cpuHighSince = nil
      runtime.memoryHighSince = nil
      return
    }

    sustained(
      &runtime, since: \.cpuHighSince, node: node, value: node.metrics.cpuUsage,
      threshold: 90, key: "cpu",
      title: "\(L.text("alert.cpu")) \(Int(node.metrics.cpuUsage))%")
    sustained(
      &runtime, since: \.memoryHighSince, node: node, value: node.metrics.memoryUsage,
      threshold: 92, key: "memory",
      title: "\(L.text("alert.memory")) \(Int(node.metrics.memoryUsage))%")

    if node.metrics.diskUsage >= 90 {
      if !runtime.diskAlerted {
        runtime.diskAlerted = true
        fire(
          &runtime, node: node, key: "disk", severity: .warning,
          title: "\(L.text("alert.disk")) \(Int(node.metrics.diskUsage))%")
      }
    } else if node.metrics.diskUsage < 85 {
      runtime.diskAlerted = false
    }
  }

  private func sustained(
    _ runtime: inout AlertRuntime, since: WritableKeyPath<AlertRuntime, Date?>,
    node: NodeSnapshot, value: Double, threshold: Double, key: String, title: String
  ) {
    if value >= threshold {
      let start = runtime[keyPath: since] ?? .now
      if runtime[keyPath: since] == nil { runtime[keyPath: since] = start }
      if Date.now.timeIntervalSince(start) >= Self.sustainInterval {
        fire(&runtime, node: node, key: key, severity: .warning, title: title)
      }
    } else if value < threshold - 10 {
      runtime[keyPath: since] = nil
    }
  }

  // MARK: service rules

  func evaluateServiceAlerts(for id: UUID, services: AgentServices) {
    guard let node = node(id: id) else { return }
    var runtime = alertRuntime[id] ?? AlertRuntime()
    defer { alertRuntime[id] = runtime }

    let failed = Set(services.systemd?.failed ?? [])
    let containers = services.docker.containers ?? []
    let seeded = runtime.servicesSeeded
    runtime.servicesSeeded = true

    if seeded {
      let newFailures = failed.subtracting(runtime.knownFailedUnits)
      if !newFailures.isEmpty {
        fire(
          &runtime, node: node, key: "failed-units", severity: .warning,
          title: "\(L.text("alert.failedUnit")): \(newFailures.sorted().joined(separator: ", "))")
      }
      for container in containers {
        if let previous = runtime.restartCounts[container.id], container.restarts > previous {
          fire(
            &runtime, node: node, key: "restart-\(container.id)", severity: .warning,
            title: "\(L.text("alert.restart")): \(container.name) (\(container.restarts))")
        }
      }
    }
    runtime.knownFailedUnits = failed
    runtime.restartCounts = Dictionary(
      uniqueKeysWithValues: containers.map { ($0.id, $0.restarts) })

    for site in services.websites {
      guard let days = site.certDaysLeft, days <= 14, !runtime.certAlerted.contains(site.id)
      else { continue }
      runtime.certAlerted.insert(site.id)
      fire(
        &runtime, node: node, key: "cert-\(site.id)",
        severity: days <= 7 ? .offline : .warning,
        title: "\(L.text("alert.cert")): \(site.domain) (\(days)d)")
    }
  }

  // MARK: firing, persistence, notification

  private func fire(
    _ runtime: inout AlertRuntime, node: NodeSnapshot, key: String,
    severity: NodeStatus, title: String
  ) {
    if let last = runtime.lastFired[key], Date.now.timeIntervalSince(last) < Self.fireCooldown {
      return
    }
    runtime.lastFired[key] = .now
    alerts.insert(
      AlertItem(id: UUID(), nodeID: node.id, severity: severity, title: title, date: .now, isRead: false),
      at: 0)
    if alerts.count > Self.maxStoredAlerts {
      alerts.removeLast(alerts.count - Self.maxStoredAlerts)
    }
    persistAlerts()
    postNotification(nodeName: node.info.name, body: title)
  }

  func markAllAlertsRead() {
    for index in alerts.indices {
      alerts[index].isRead = true
    }
    persistAlerts()
  }

  func clearAlerts() {
    alerts.removeAll()
    persistAlerts()
  }

  var unreadAlertCount: Int {
    alerts.filter { !$0.isRead }.count
  }

  func restoreAlerts() {
    guard let data = UserDefaults.standard.data(forKey: Self.alertsDefaultsKey),
      let stored = try? JSONDecoder().decode([AlertItem].self, from: data)
    else { return }
    alerts = stored
  }

  private func persistAlerts() {
    if let data = try? JSONEncoder().encode(alerts) {
      UserDefaults.standard.set(data, forKey: Self.alertsDefaultsKey)
    }
  }

  private func postNotification(nodeName: String, body: String) {
    Task {
      let center = UNUserNotificationCenter.current()
      let granted =
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = nodeName
      content.body = body
      try? await center.add(
        UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
  }
}
