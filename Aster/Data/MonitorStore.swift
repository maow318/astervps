import Foundation
import Observation

@Observable
@MainActor
final class MonitorStore {
    var nodes: [NodeSnapshot]
    var groups: [NodeGroup]
    var alerts: [AlertItem]

    private let dataSource: any MonitorDataSource
    private var refreshTask: Task<Void, Never>?
    private var shouldRefreshHistory = false
    private var isWindowActive = true

    init(dataSource: any MonitorDataSource) {
        self.dataSource = dataSource
        nodes = dataSource.loadNodes()
        groups = dataSource.loadGroups()
        alerts = dataSource.loadAlerts()
        startRefreshLoop()
    }

    convenience init() {
        self.init(dataSource: MockDataSource())
    }

    func setWindowActive(_ isActive: Bool) {
        isWindowActive = isActive
    }

    func node(id: UUID) -> NodeSnapshot? {
        nodes.first { $0.id == id }
    }

    var onlineCount: Int {
        nodes.filter { $0.info.status == .online }.count
    }

    var offlineCount: Int {
        nodes.filter { $0.info.status == .offline }.count
    }

    private func startRefreshLoop() {
        refreshTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let interval: UInt64 = self.isWindowActive ? 2_000_000_000 : 30_000_000_000
                try? await Task.sleep(nanoseconds: interval)

                guard !Task.isCancelled else { return }
                self.refreshMetrics()
            }
        }
    }

    private func refreshMetrics() {
        let refreshedNodes = dataSource.refresh(nodes: nodes, includeHistory: shouldRefreshHistory)
        shouldRefreshHistory.toggle()

        for refreshedNode in refreshedNodes {
            guard let index = nodes.firstIndex(where: { $0.id == refreshedNode.id }) else { continue }
            nodes[index].metrics = refreshedNode.metrics
            nodes[index].info.status = refreshedNode.info.status

            if shouldRefreshHistory {
                nodes[index].history = refreshedNode.history
            }
        }
    }
}
