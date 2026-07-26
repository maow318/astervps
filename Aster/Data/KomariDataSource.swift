import Foundation

/// Komari v1 public API adapter. REST is used for node metadata/history; `/api/clients`
/// is used only for current nested real-time values. All byte fields stay in bytes until
/// mapping to the percentage/speed fields consumed by the UI.
@MainActor
final class KomariDataSource: MonitorDataSource {
    private let baseURL: URL
    private let token: String?
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var latestNodes: [String: NodeSnapshot] = [:]
    var onStateChange: (@MainActor (ConnectionState) -> Void)?
    var onMetrics: (@MainActor ([NodeSnapshot]) -> Void)?

    init(endpoint: String, token: String?) throws {
        guard let url = URL(string: endpoint), url.scheme == "http" || url.scheme == "https" else {
            throw URLError(.badURL)
        }
        baseURL = url
        self.token = token?.isEmpty == false ? token : nil
        session = URLSession(configuration: .default)
    }

    func loadNodes() -> [NodeSnapshot] { Array(latestNodes.values) }
    func loadGroups() -> [NodeGroup] { [] }
    func loadAlerts() -> [AlertItem] { [] }
    func refresh(nodes: [NodeSnapshot], includeHistory: Bool) -> [NodeSnapshot] { nodes }

    func testConnection() async throws {
        let _: KomariEnvelope<KomariVersion> = try await request(path: "/api/version")
    }

    func loadDashboard() async throws -> MonitorDashboard {
        let response: KomariEnvelope<[KomariNode]> = try await request(path: "/api/nodes")
        let nodeInfos = response.data.map(makeInfo)
        let snapshots = nodeInfos.map { NodeSnapshot(info: $0, metrics: .empty, history: .empty) }
        latestNodes = Dictionary(uniqueKeysWithValues: snapshots.compactMap { snapshot in
            snapshot.info.serverID.map { ($0, snapshot) }
        })
        return MonitorDashboard(nodes: snapshots, groups: makeGroups(from: nodeInfos), alerts: [])
    }

    func loadHistory(for node: NodeInfo, hours: Int) async throws -> MetricsHistory {
        guard let serverID = node.serverID else { return .empty }
        let response: KomariEnvelope<KomariHistoryPayload> = try await request(
            path: "/api/records/load",
            query: [URLQueryItem(name: "uuid", value: serverID), URLQueryItem(name: "hours", value: "\(hours)")]
        )
        return makeHistory(response.data.records)
    }

    func startLiveUpdates() {
        stopLiveUpdates()
        openSocket()
    }

    func stopLiveUpdates() {
        receiveTask?.cancel()
        reconnectTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func openSocket() {
        onStateChange?(.connecting)
        guard var components = URLComponents(url: baseURL.appendingPathComponent("api/clients"), resolvingAgainstBaseURL: false) else { return }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        guard let url = components.url else { return }

        let task = session.webSocketTask(with: authorizedRequest(url))
        socket = task
        task.resume()
        task.send(.string("get")) { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                if error == nil {
                    self.reconnectAttempt = 0
                    self.onStateChange?(.connected)
                    self.receiveMessages(from: task)
                } else {
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func receiveMessages(from task: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .data(let data):
                        self.applyRealtimePayload(data)
                    case .string(let string):
                        self.applyRealtimePayload(Data(string.utf8))
                    @unknown default:
                        continue
                    }
                } catch {
                    self.scheduleReconnect()
                    return
                }
            }
        }
    }

    private func applyRealtimePayload(_ data: Data) {
        guard let payload = try? JSONDecoder.komari.decode(KomariSocketEnvelope.self, from: data) else { return }
        let online = Set(payload.data.online)

        for (serverID, sample) in payload.data.data {
            guard var snapshot = latestNodes[serverID] else { continue }
            snapshot.info.status = online.contains(serverID) ? .online : .offline
            snapshot.metrics = makeMetrics(sample)
            latestNodes[serverID] = snapshot
        }
        onMetrics?(Array(latestNodes.values))
    }

    private func scheduleReconnect() {
        reconnectAttempt += 1
        onStateChange?(.reconnecting(attempt: reconnectAttempt))
        let delay = min(pow(2, Double(reconnectAttempt)), 60)
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.openSocket()
        }
    }

    private func request<T: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        let (data, response) = try await session.data(for: authorizedRequest(components.url!))
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
        return try JSONDecoder.komari.decode(T.self, from: data)
    }

    private func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func makeInfo(_ node: KomariNode) -> NodeInfo {
        NodeInfo(id: UUID(uuidString: node.uuid) ?? UUID(), name: node.name, region: node.group ?? node.region ?? "", flag: node.region?.containsEmoji ?? "", operatingSystem: node.os ?? "", status: .offline, tags: node.tags?.split(separator: ";").map(String.init) ?? [], groupID: nil, createdAt: node.createdAt ?? .now, serverID: node.uuid)
    }

    private func makeGroups(from nodes: [NodeInfo]) -> [NodeGroup] {
        Dictionary(grouping: nodes, by: { $0.region }).map { name, members in NodeGroup(id: UUID(), name: name, symbol: "folder", nodeIDs: members.map(\.id)) }
    }

    private func makeMetrics(_ sample: KomariRealtime) -> NodeMetrics {
        let ramPercent = percentage(sample.ram.used, sample.ram.total)
        return NodeMetrics(cpuUsage: sample.cpu.usage, memoryUsage: ramPercent, swapUsage: percentage(sample.swap.used, sample.swap.total), diskUsage: percentage(sample.disk.used, sample.disk.total), downloadBytesPerSecond: sample.network.down, uploadBytesPerSecond: sample.network.up, connectionCount: sample.connections.tcp + sample.connections.udp, processCount: sample.process, loadAverage: sample.load.load1, uptime: sample.uptime, diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0)
    }

    private func makeHistory(_ records: [KomariHistoryRecord]) -> MetricsHistory {
        func samples(_ value: @escaping (KomariHistoryRecord) -> Double) -> [MetricSample] { records.map { MetricSample(id: UUID(), date: $0.time, value: value($0)) } }
        return MetricsHistory(cpu: samples(\.cpu), memory: samples { self.percentage($0.ram, $0.ramTotal) }, download: samples { $0.netIn / 1_000_000 }, upload: samples { $0.netOut / 1_000_000 }, diskRead: [], diskWrite: [])
    }

    private func percentage(_ used: Double, _ total: Double) -> Double { total > 0 ? min(used / total * 100, 100) : 0 }
}

private struct KomariEnvelope<T: Decodable>: Decodable { let data: T }
private struct KomariVersion: Decodable { let version: String }
private struct KomariNode: Decodable { let uuid: String; let name: String; let region: String?; let group: String?; let os: String?; let tags: String?; let createdAt: Date?
    enum CodingKeys: String, CodingKey { case uuid, name, region, group, os, tags; case createdAt = "created_at" } }
private struct KomariSocketEnvelope: Decodable { let data: KomariSocketPayload }
private struct KomariSocketPayload: Decodable { let online: [String]; let data: [String: KomariRealtime] }
private struct KomariRealtime: Decodable { let cpu: KomariCPU; let ram: KomariMemory; let swap: KomariMemory; let load: KomariLoad; let disk: KomariMemory; let network: KomariNetwork; let connections: KomariConnections; let uptime: TimeInterval; let process: Int }
private struct KomariCPU: Decodable { let usage: Double }
private struct KomariMemory: Decodable { let total: Double; let used: Double }
private struct KomariLoad: Decodable { let load1: Double }
private struct KomariNetwork: Decodable { let up: Double; let down: Double }
private struct KomariConnections: Decodable { let tcp: Int; let udp: Int }
private struct KomariHistoryPayload: Decodable { let records: [KomariHistoryRecord] }
private struct KomariHistoryRecord: Decodable { let time: Date; let cpu: Double; let ram: Double; let ramTotal: Double; let netIn: Double; let netOut: Double
    enum CodingKeys: String, CodingKey { case time, cpu, ram; case ramTotal = "ram_total"; case netIn = "net_in"; case netOut = "net_out" } }
private extension JSONDecoder { static var komari: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder } }
private extension MetricsHistory { static let empty = MetricsHistory(cpu: [], memory: [], download: [], upload: [], diskRead: [], diskWrite: []) }
private extension NodeMetrics { static let empty = NodeMetrics(cpuUsage: 0, memoryUsage: 0, swapUsage: 0, diskUsage: 0, downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, connectionCount: 0, processCount: 0, loadAverage: 0, uptime: 0, diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0) }
private extension String { var containsEmoji: String? { unicodeScalars.contains { $0.properties.isEmojiPresentation } ? self : nil } }
