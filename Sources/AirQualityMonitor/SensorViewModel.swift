import Foundation
import SwiftUI

@Observable
@MainActor
final class SensorViewModel {
    var readings: [String: [SensorReading]] = [:]
    var lastError: String?
    var isLoading = false
    var lastUpdated: Date?
    var config: AppConfig?
    var configLoaded = false

    private var client: HAClient?
    private var monitoringTask: Task<Void, Never>?
    private var fullRefreshTask: Task<Void, Never>?

    var sensorConfigs: [SensorConfig] { config?.sensors ?? [] }

    var hasConfig: Bool { config != nil }

    func loadConfig() {
        guard ConfigLoader.configExists() else {
            configLoaded = true
            return
        }
        do {
            let loaded = try ConfigLoader.load()
            config = loaded
            client = HAClient(baseURL: loaded.homeAssistantURL, token: loaded.token)
            configLoaded = true
        } catch {
            lastError = "Config error: \(error.localizedDescription)"
            configLoaded = true
        }
    }

    func currentValue(for sensor: SensorConfig) -> Double? {
        readings[sensor.entityId]?.last?.value
    }

    func currentValue(forKey key: String) -> Double? {
        guard let sensor = config?.sensors.first(where: { $0.key == key }) else { return nil }
        return readings[sensor.entityId]?.last?.value
    }

    func startMonitoring() {
        guard let config, client != nil else { return }

        monitoringTask?.cancel()
        fullRefreshTask?.cancel()

        monitoringTask = Task {
            // Brief delay on launch to let the network stack initialize
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            // Retry initial fetch up to 3 times
            for attempt in 0..<3 {
                await fetchFullHistory()
                if lastError == nil { break }
                if attempt < 2 {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                }
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(config.refreshIntervalSeconds))
                guard !Task.isCancelled else { break }
                await fetchLatestStates()
            }
        }

        fullRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(config.fullRefreshIntervalSeconds))
                guard !Task.isCancelled else { break }
                await fetchFullHistory()
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        fullRefreshTask?.cancel()
    }

    func fetchFullHistory() async {
        guard let config, let client else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let entityIds = config.sensors.map(\.entityId)
            let history = try await client.fetchHistory(entityIds: entityIds, hours: config.historyHours)
            for (entityId, data) in history {
                readings[entityId] = data
            }
            lastError = nil
            lastUpdated = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetchLatestStates() async {
        guard let config, let client else { return }

        do {
            for sensor in config.sensors {
                if let reading = try await client.fetchCurrentState(entityId: sensor.entityId) {
                    var current = readings[sensor.entityId] ?? []

                    if let last = current.last, last.date == reading.date {
                        continue
                    }

                    current.append(reading)

                    let cutoff = Date().addingTimeInterval(-Double(config.historyHours) * 3600)
                    current.removeAll { $0.date < cutoff }

                    readings[sensor.entityId] = current
                }
            }
            lastError = nil
            lastUpdated = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
