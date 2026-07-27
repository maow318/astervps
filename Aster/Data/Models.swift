import Foundation

enum NodeStatus: String, Codable, CaseIterable, Identifiable {
  case online, offline, warning
  var id: String { rawValue }
}

/// Komari-compatible node identity. Future API adapter maps server name, location and OS here.
struct NodeInfo: Identifiable, Codable, Hashable {
  let id: UUID
  var name: String
  var region: String
  var flag: String
  var operatingSystem: String
  var status: NodeStatus
  var tags: [String]
  var groupID: UUID?
  var createdAt: Date
  /// CPU model / core count, e.g. "Apple M4 · 10核". Demo data ships varied
  /// hardware; agent nodes fill this from /v1/meta.
  var hardware: String = ""
  /// Optional user-entered billing note ("$17.93/年") and expiry date,
  /// mirrored from MachineConfig for display.
  var billingPrice: String? = nil
  var billingExpiresAt: Date? = nil
  var memoryTotalBytes: Double = 0
  var swapTotalBytes: Double = 0
  var diskTotalBytes: Double = 0
  /// Komari's UUID string. Kept separately so incompatible server IDs can still be displayed.
  var serverID: String? = nil
}

/// Latest node metrics. Percentages are 0-100; byte quantities are raw bytes
/// so views can format adaptively (agent wire format keeps used/total pairs).
struct NodeMetrics: Codable, Hashable {
  var cpuUsage, memoryUsage, swapUsage, diskUsage: Double
  var downloadBytesPerSecond, uploadBytesPerSecond: Double
  var connectionCount, processCount: Int
  var loadAverage: Double
  var uptime: TimeInterval
  var diskReadBytesPerSecond, diskWriteBytesPerSecond: Double
  var memoryUsedBytes: Double = 0
  var memoryTotalBytes: Double = 0
  var swapUsedBytes: Double = 0
  var swapTotalBytes: Double = 0
  var diskUsedBytes: Double = 0
  var diskTotalBytes: Double = 0
  var totalUploadBytes: Double = 0
  var totalDownloadBytes: Double = 0
  var load5: Double = 0
  var load15: Double = 0
}

struct MetricSample: Identifiable, Codable, Hashable {
  let id: UUID
  var date: Date
  var value: Double
}
/// Future Komari history endpoint maps each metric series to these timestamped samples.
struct MetricsHistory: Codable, Hashable {
  var cpu, memory, download, upload, diskRead, diskWrite: [MetricSample]
}

struct NodeGroup: Identifiable, Codable, Hashable {
  let id: UUID
  var name: String
  var symbol: String
  var nodeIDs: [UUID]
}
struct AlertItem: Identifiable, Codable, Hashable {
  let id: UUID
  var nodeID: UUID
  var severity: NodeStatus
  var title: String
  var date: Date
  var isRead: Bool
}
struct NodeSnapshot: Identifiable, Hashable {
  var info: NodeInfo
  var metrics: NodeMetrics
  var history: MetricsHistory
  var id: UUID { info.id }
}

struct MonitorDashboard {
  var nodes: [NodeSnapshot]
  var groups: [NodeGroup]
  var alerts: [AlertItem]
}

enum ConnectionState: Equatable {
  case unconfigured
  case connecting
  case connected
  case reconnecting(attempt: Int)
  case failed(String)
  case unauthorized
  case certificateMismatch

  var dotStatus: NodeStatus {
    switch self {
    case .connected: .online
    case .connecting, .reconnecting: .warning
    case .unconfigured, .failed, .unauthorized, .certificateMismatch: .offline
    }
  }

  var localizedText: String {
    switch self {
    case .unconfigured: L.text("connection.unconfigured")
    case .connecting: L.text("connection.connecting")
    case .connected: L.text("connection.connected")
    case .reconnecting: L.text("connection.reconnecting")
    case .failed(let message): "\(L.text("connection.failed")) · \(message)"
    case .unauthorized: L.text("connection.unauthorized")
    case .certificateMismatch: L.text("connection.certMismatch")
    }
  }
}

enum TimeRange: String, CaseIterable, Identifiable {
  case hour, sixHours, day, week
  var id: String { rawValue }
  var key: String { "range.\(rawValue)" }
  var hours: Int {
    switch self {
    case .hour: 1
    case .sixHours: 6
    case .day: 24
    case .week: 168
    }
  }
}
