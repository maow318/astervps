import Foundation

@MainActor final class MockDataSource: MonitorDataSource {
    private let groups = [
        NodeGroup(id: UUID(), name: "Production", symbol: "shippingbox.fill", nodeIDs: []),
        NodeGroup(id: UUID(), name: "Edge", symbol: "point.3.connected.trianglepath.dotted", nodeIDs: [])
    ]
    private let blueprints: [(String, String, String, String, NodeStatus, [String])] = [
        ("aurora-01", "Tokyo", "🇯🇵", "Ubuntu", .online, ["prod", "api"]), ("luna-sfo", "San Francisco", "🇺🇸", "macOS", .online, ["edge"]),
        ("atlas-fra", "Frankfurt", "🇩🇪", "Debian", .online, ["prod", "db"]), ("nova-sin", "Singapore", "🇸🇬", "Alpine", .warning, ["edge"]),
        ("zenith-lhr", "London", "🇬🇧", "Ubuntu", .online, ["worker"]), ("orbit-syd", "Sydney", "🇦🇺", "Debian", .offline, ["backup"]),
        ("meridian-tor", "Toronto", "🇨🇦", "Ubuntu", .online, ["api"]), ("sol-sea", "Seattle", "🇺🇸", "Fedora", .online, ["staging"]),
        ("polar-hel", "Helsinki", "🇫🇮", "Ubuntu", .online, ["edge"]), ("comet-gru", "São Paulo", "🇧🇷", "Debian", .online, ["worker"]),
        ("terra-sel", "Seoul", "🇰🇷", "Ubuntu", .online, ["prod"]), ("drift-ams", "Amsterdam", "🇳🇱", "Alpine", .online, ["cache"])
    ]

    func loadNodes() -> [NodeSnapshot] {
        blueprints.enumerated().map { index, item in
            let base = Double(18 + (index * 7) % 54)
            let info = NodeInfo(id: UUID(), name: item.0, region: item.1, flag: item.2, operatingSystem: item.3, status: item.4, tags: item.5, groupID: groups[index % groups.count].id, createdAt: .now)
            let metrics = NodeMetrics(cpuUsage: base, memoryUsage: min(base + 13, 92), swapUsage: Double(index % 17), diskUsage: Double(28 + (index * 6) % 58), downloadBytesPerSecond: Double(1_300_000 + index * 270_000), uploadBytesPerSecond: Double(300_000 + index * 88_000), connectionCount: 12 + index * 9, processCount: 85 + index * 7, loadAverage: base / 21, uptime: Double(86_400 * (index + 2)), diskReadBytesPerSecond: Double(400_000 + index * 40_000), diskWriteBytesPerSecond: Double(170_000 + index * 22_000))
            return NodeSnapshot(info: info, metrics: metrics, history: history(around: base))
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
            var copy = snapshot; guard copy.info.status != .offline else { return copy }
            func jitter(_ value: Double, by amount: Double, range: ClosedRange<Double> = 0...100) -> Double { min(max(value + Double.random(in: -amount...amount), range.lowerBound), range.upperBound) }
            copy.metrics.cpuUsage = jitter(copy.metrics.cpuUsage, by: 5)
            copy.metrics.memoryUsage = jitter(copy.metrics.memoryUsage, by: 2)
            copy.metrics.diskUsage = jitter(copy.metrics.diskUsage, by: 0.4)
            copy.metrics.downloadBytesPerSecond = max(0, copy.metrics.downloadBytesPerSecond + Double.random(in: -350_000...350_000))
            copy.metrics.uploadBytesPerSecond = max(0, copy.metrics.uploadBytesPerSecond + Double.random(in: -90_000...90_000))
            copy.metrics.loadAverage = max(0, copy.metrics.cpuUsage / 20 + Double.random(in: -0.12...0.12))
            if includeHistory {
                copy.history.cpu = append(copy.metrics.cpuUsage, to: copy.history.cpu)
                copy.history.memory = append(copy.metrics.memoryUsage, to: copy.history.memory)
                copy.history.download = append(copy.metrics.downloadBytesPerSecond / 1_000_000, to: copy.history.download)
                copy.history.upload = append(copy.metrics.uploadBytesPerSecond / 1_000_000, to: copy.history.upload)
            }
            return copy
        }
    }
    private func history(around value: Double) -> MetricsHistory {
        func series(_ base: Double) -> [MetricSample] { (0..<28).map { offset in MetricSample(id: UUID(), date: .now.addingTimeInterval(Double(offset - 27) * 300), value: max(0, base + Double.random(in: -9...9))) } }
        return MetricsHistory(cpu: series(value), memory: series(value + 13), download: series(2.4), upload: series(0.7), diskRead: series(1.3), diskWrite: series(0.5))
    }
    private func append(_ value: Double, to samples: [MetricSample]) -> [MetricSample] { Array((samples + [MetricSample(id: UUID(), date: .now, value: value)]).suffix(28)) }
}
