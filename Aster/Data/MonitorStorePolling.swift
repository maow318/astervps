import Foundation

/// Fleet polling: one concurrent fetch pass per tick, per-machine isolation.
/// Split from MonitorStore.swift to keep both files under the size budget.
extension MonitorStore {
  func startRefreshLoop() {
    refreshTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        let demo = self.isDemoMode
        let active = self.isWindowActive
        let seconds: Double = demo ? (active ? 5 : 30) : (active ? 2 : 30)
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled else { return }
        if self.isDemoMode {
          self.refreshDemo()
        } else {
          await self.pollAgents()
        }
      }
    }
  }

  func pollAgents() async {
    guard !isPolling, !clients.isEmpty else { return }
    isPolling = true
    defer { isPolling = false }

    await withTaskGroup(of: MachinePollResult.self) { group in
      for (id, client) in clients {
        let needsMeta = metaByMachine[id] == nil
        let needsHistory = shouldSyncHistory(id)
        let since = historyStore.latestTimestamp(for: id)
        group.addTask {
          await Self.poll(
            id: id, client: client, needsMeta: needsMeta, needsHistory: needsHistory, since: since)
        }
      }
      for await result in group {
        apply(result)
      }
    }
  }

  private nonisolated static func poll(
    id: UUID, client: AgentClient, needsMeta: Bool, needsHistory: Bool, since: Int64
  ) async -> MachinePollResult {
    do {
      let metrics = try await client.metrics()
      let meta = needsMeta ? try? await client.meta() : nil
      let history = needsHistory ? ((try? await client.history(since: since)) ?? []) : []
      return MachinePollResult(id: id, outcome: .success(metrics, meta, history))
    } catch let error as AgentError {
      return MachinePollResult(id: id, outcome: .agentError(error))
    } catch {
      return MachinePollResult(id: id, outcome: .failure(error.localizedDescription))
    }
  }

  private func shouldSyncHistory(_ id: UUID) -> Bool {
    guard let last = lastHistorySync[id] else { return true }
    return Date.now.timeIntervalSince(last) >= 30
  }

  private func apply(_ result: MachinePollResult) {
    guard let index = nodes.firstIndex(where: { $0.id == result.id }) else { return }
    let id = result.id
    let previousState = machineStates[id]
    defer {
      #if DEBUG
        // State transitions go to stdout so headless E2E runs can assert on them.
        if machineStates[id] != previousState {
          print("[aster-debug] machine \(id) state -> \(machineStates[id].map(String.init(describing:)) ?? "nil")")
        }
      #endif
    }
    switch result.outcome {
    case .success(let metrics, let meta, let history):
      machineStates[id] = .connected
      if let meta {
        metaByMachine[id] = meta
        nodes[index].info.operatingSystem = meta.os
        nodes[index].info.region = meta.hostname
      }
      nodes[index].metrics = metrics.nodeMetrics
      nodes[index].info.status = .online
      if !history.isEmpty {
        let points = history.map { snapshot in
          HistoryPoint(
            t: snapshot.timestamp, cpu: snapshot.metrics.cpuUsage,
            mem: snapshot.metrics.memory.percentage, down: snapshot.metrics.network.down,
            up: snapshot.metrics.network.up)
        }
        historyStore.append(points, for: id)
        lastHistorySync[id] = .now
        nodes[index].history = historyStore.metricsHistory(for: id, hours: detailHours[id] ?? 1)
      }
    case .agentError(let error):
      nodes[index].info.status = .offline
      switch error {
      case .unauthorized: machineStates[id] = .unauthorized
      case .certificateMismatch: machineStates[id] = .certificateMismatch
      default: machineStates[id] = .failed(error.localizedDescription ?? "")
      }
    case .failure(let message):
      nodes[index].info.status = .offline
      machineStates[id] = .failed(message)
    }
  }
}

private struct MachinePollResult {
  enum Outcome {
    case success(AgentMetrics, AgentMeta?, [AgentSnapshot])
    case agentError(AgentError)
    case failure(String)
  }

  let id: UUID
  let outcome: Outcome
}
