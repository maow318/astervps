import Foundation

/// One 30-second history sample in the compact on-disk form. Values are kept
/// raw (percent / bytes-per-second); UI units are derived when converting to
/// MetricsHistory.
struct HistoryPoint: Codable {
  var t: Int64
  var cpu: Double
  var mem: Double
  var down: Double
  var up: Double
}

/// Persists per-machine history under Application Support so charts survive
/// app restarts. Files are rewritten wholesale on append — at 30 s cadence
/// and a 7-day cap (~20k points) this stays well under a megabyte.
@MainActor
final class HistoryStore {
  static let retention: TimeInterval = 7 * 24 * 3600

  private var cache: [UUID: [HistoryPoint]] = [:]

  private var directory: URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("Aster/history", isDirectory: true)
  }

  private func fileURL(for machineID: UUID) -> URL {
    directory.appendingPathComponent("\(machineID.uuidString).json")
  }

  func points(for machineID: UUID) -> [HistoryPoint] {
    if let cached = cache[machineID] { return cached }
    let loaded = loadFromDisk(machineID)
    cache[machineID] = loaded
    return loaded
  }

  var latestTimestamp: [UUID: Int64] {
    cache.mapValues { $0.last?.t ?? 0 }
  }

  func latestTimestamp(for machineID: UUID) -> Int64 {
    points(for: machineID).last?.t ?? 0
  }

  func append(_ newPoints: [HistoryPoint], for machineID: UUID) {
    guard !newPoints.isEmpty else { return }
    var merged = points(for: machineID)
    let lastKnown = merged.last?.t ?? 0
    merged.append(contentsOf: newPoints.filter { $0.t > lastKnown }.sorted { $0.t < $1.t })

    let cutoff = Int64(Date.now.timeIntervalSince1970 - Self.retention)
    if let firstKept = merged.firstIndex(where: { $0.t >= cutoff }) {
      merged.removeFirst(firstKept)
    } else if !merged.isEmpty, merged.last!.t < cutoff {
      merged.removeAll()
    }

    cache[machineID] = merged
    writeToDisk(merged, machineID: machineID)
  }

  func delete(for machineID: UUID) {
    cache[machineID] = nil
    try? FileManager.default.removeItem(at: fileURL(for: machineID))
  }

  /// Builds the chart-facing history for the requested window. CPU and memory
  /// are percentages; network series are MB/s to match the existing charts.
  func metricsHistory(for machineID: UUID, hours: Int) -> MetricsHistory {
    let cutoff = Date.now.timeIntervalSince1970 - Double(hours) * 3600
    let window = points(for: machineID).filter { Double($0.t) >= cutoff }

    func series(_ value: (HistoryPoint) -> Double) -> [MetricSample] {
      window.map { point in
        MetricSample(
          id: UUID(),
          date: Date(timeIntervalSince1970: Double(point.t)),
          value: value(point))
      }
    }
    return MetricsHistory(
      cpu: series { $0.cpu },
      memory: series { $0.mem },
      download: series { $0.down / 1_000_000 },
      upload: series { $0.up / 1_000_000 },
      diskRead: [],
      diskWrite: [])
  }

  private func loadFromDisk(_ machineID: UUID) -> [HistoryPoint] {
    guard let data = try? Data(contentsOf: fileURL(for: machineID)) else { return [] }
    // A corrupt file silently resets: history is reconstructable via backfill.
    return (try? JSONDecoder().decode([HistoryPoint].self, from: data)) ?? []
  }

  private func writeToDisk(_ points: [HistoryPoint], machineID: UUID) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(points)
      try data.write(to: fileURL(for: machineID), options: .atomic)
    } catch {
      // Persistence is best-effort; in-memory history keeps the UI working.
    }
  }
}
