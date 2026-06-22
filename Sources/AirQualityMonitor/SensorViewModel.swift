import Foundation
import SwiftUI

enum TimeRange: Int, CaseIterable, Identifiable {
    case oneHour = 1
    case sixHours = 6
    case twelveHours = 12
    case twentyFourHours = 24
    case threeDays = 72
    case sevenDays = 168
    case tenDays = 240

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .oneHour: return "1h"
        case .sixHours: return "6h"
        case .twelveHours: return "12h"
        case .twentyFourHours: return "24h"
        case .threeDays: return "3d"
        case .sevenDays: return "7d"
        case .tenDays: return "10d"
        }
    }

    static func closest(to hours: Int) -> TimeRange {
        allCases.min(by: { abs($0.rawValue - hours) < abs($1.rawValue - hours) }) ?? .twelveHours
    }
}

/// A device's worth of metric tiles for the overview: the room/device header
/// (name, icon, air-quality status, battery) plus the sensors that belong to it.
struct DeviceGroup: Identifiable {
    let id: String
    let categoryId: String
    let subcategoryId: String?
    let name: String
    let icon: String
    let status: AirQualityLevel?
    let battery: Double?
    let sensors: [SensorConfig]
}

@Observable
@MainActor
final class SensorViewModel {
    var readings: [String: [SensorReading]] = [:]
    var latestValues: [String: SensorReading] = [:]
    var airQualityLevels: [String: AirQualityLevel] = [:]
    var batteryLevels: [String: Double] = [:]
    var lastError: String?
    var isLoading = false
    var lastUpdated: Date?
    var config: AppConfig?
    var configLoaded = false
    var selectedTimeRange: TimeRange = .twelveHours

    /// Currently selected category in sidebar
    var selectedCategoryId: String?
    /// Currently selected subcategory (nil = show all in category)
    var selectedSubcategoryId: String?
    /// Set when something (e.g. the menu bar) wants the main window to expand a
    /// specific sensor. ContentView observes this, expands, then clears it.
    var pendingFocusSensorKey: String?

    private var client: HAClient?
    private var monitoringTask: Task<Void, Never>?
    private var fullRefreshTask: Task<Void, Never>?

    var categories: [SensorCategory] { config?.categories ?? [] }

    /// Sensors to display based on current selection
    var visibleSensors: [SensorConfig] {
        guard let config else { return [] }

        guard let catId = selectedCategoryId,
              let category = config.categories.first(where: { $0.id == catId }) else {
            // No selection: show all sensors
            return config.allSensors
        }

        if let subId = selectedSubcategoryId,
           let sub = category.subcategories.first(where: { $0.id == subId }) {
            return sub.sensors
        }

        return category.allSensors
    }

    /// Sensors grouped by their device (subcategory, or category for loose
    /// sensors), restricted to the given scope. Status/battery live on the
    /// device, not each sensor.
    func deviceGroups(categoryId: String?, subcategoryId: String?) -> [DeviceGroup] {
        guard let config else { return [] }
        var groups: [DeviceGroup] = []

        func addCategory(_ cat: SensorCategory, restrictSub: String?) {
            if restrictSub == nil, !cat.sensors.isEmpty {
                groups.append(DeviceGroup(
                    id: cat.id, categoryId: cat.id, subcategoryId: nil,
                    name: cat.name, icon: cat.icon, status: nil,
                    battery: cat.batteryEntityId.flatMap { batteryLevels[$0] },
                    sensors: cat.sensors))
            }
            for sub in cat.subcategories where !sub.sensors.isEmpty {
                if let restrictSub, sub.id != restrictSub { continue }
                groups.append(DeviceGroup(
                    id: "\(cat.id)/\(sub.id)", categoryId: cat.id, subcategoryId: sub.id,
                    name: sub.name, icon: sub.icon, status: airQualityLevel(for: sub),
                    battery: sub.batteryEntityId.flatMap { batteryLevels[$0] },
                    sensors: sub.sensors))
            }
        }

        if let catId = categoryId,
           let category = config.categories.first(where: { $0.id == catId }) {
            addCategory(category, restrictSub: subcategoryId)
        } else {
            for cat in config.categories { addCategory(cat, restrictSub: nil) }
        }
        return groups
    }

    /// Device groups for the current sidebar selection (tile overview).
    var visibleDeviceGroups: [DeviceGroup] {
        deviceGroups(categoryId: selectedCategoryId, subcategoryId: selectedSubcategoryId)
    }

    /// Every device group regardless of selection (menu bar popover).
    var allDeviceGroups: [DeviceGroup] {
        deviceGroups(categoryId: nil, subcategoryId: nil)
    }

    /// Title for the current selection
    var selectionTitle: String {
        guard let catId = selectedCategoryId,
              let category = config?.categories.first(where: { $0.id == catId }) else {
            return "All Sensors"
        }

        if let subId = selectedSubcategoryId,
           let sub = category.subcategories.first(where: { $0.id == subId }) {
            return sub.name
        }

        return category.name
    }

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
            selectedTimeRange = TimeRange.closest(to: loaded.historyHours)
            // Auto-select first category
            if selectedCategoryId == nil {
                selectedCategoryId = loaded.categories.first?.id
            }
            configLoaded = true
        } catch {
            lastError = "Config error: \(error.localizedDescription)"
            configLoaded = true
        }
    }

    /// Navigate the main window to a sensor and request it be expanded.
    func focus(sensorKey: String) {
        if let loc = config?.location(forSensorKey: sensorKey) {
            selectedCategoryId = loc.category.id
            selectedSubcategoryId = loc.subcategory?.id
        }
        pendingFocusSensorKey = sensorKey
    }

    /// Navigate the main window to a room/device (no expansion).
    func focusRoom(categoryId: String, subcategoryId: String?) {
        selectedCategoryId = categoryId
        selectedSubcategoryId = subcategoryId
        pendingFocusSensorKey = nil
    }

    func changeTimeRange(to range: TimeRange) {
        selectedTimeRange = range
        Task { await fetchFullHistory() }
    }

    var menuBarSensor: SensorConfig? {
        guard let config else { return nil }
        if let key = config.menuBarSensorKey {
            return config.allSensors.first { $0.key == key }
        }
        return config.allSensors.first
    }

    func currentValue(for sensor: SensorConfig) -> Double? {
        latestValues[sensor.entityId]?.value ?? readings[sensor.entityId]?.last?.value
    }

    func airQualityLevel(for sub: SensorSubcategory) -> AirQualityLevel? {
        guard let entityId = sub.airQualityEntityId, !entityId.isEmpty else { return nil }
        return airQualityLevels[entityId]
    }

    // MARK: - Tile / per-sensor lookups

    /// Room label for a sensor (subcategory name if nested, else category name).
    func roomLabel(forSensorKey key: String) -> String? {
        guard let loc = config?.location(forSensorKey: key) else { return nil }
        return loc.subcategory?.name ?? loc.category.name
    }

    /// Current battery percentage for the device a sensor belongs to, if available.
    func batteryLevel(forSensorKey key: String) -> Double? {
        guard let loc = config?.location(forSensorKey: key) else { return nil }
        let entityId = loc.subcategory?.batteryEntityId ?? loc.category.batteryEntityId
        guard let entityId, !entityId.isEmpty else { return nil }
        return batteryLevels[entityId]
    }

    /// Air-quality rating for the room a sensor belongs to, if that room has one.
    func airQualityLevel(forSensorKey key: String) -> AirQualityLevel? {
        guard let loc = config?.location(forSensorKey: key),
              let entityId = loc.subcategory?.airQualityEntityId, !entityId.isEmpty else { return nil }
        return airQualityLevels[entityId]
    }

    /// Change from the first to the latest value in the currently loaded window.
    func trend(for sensor: SensorConfig) -> Double? {
        guard let data = readings[sensor.entityId], let first = data.first?.value else { return nil }
        let last = latestValues[sensor.entityId]?.value ?? data.last?.value
        guard let last else { return nil }
        return last - first
    }

    /// Subcategories that have an AQ entity, paired with their current level
    var airQualityRoomStates: [(subcategory: SensorSubcategory, level: AirQualityLevel?)] {
        guard let config else { return [] }
        return config.categories.flatMap(\.subcategories)
            .filter { $0.airQualityEntityId != nil && !($0.airQualityEntityId?.isEmpty ?? true) }
            .map { ($0, airQualityLevel(for: $0)) }
    }

    /// Worst AQ level across all rooms
    var worstAirQualityLevel: AirQualityLevel? {
        airQualityLevels.values.max(by: { $0.severity < $1.severity })
    }

    func setMenuBarSensorKey(_ key: String?) {
        guard var cfg = config else { return }
        cfg.menuBarSensorKey = key
        config = cfg
        try? ConfigLoader.save(cfg)
    }

    func moveSensor(key: String, toCategoryId: String, subcategoryId: String?) {
        guard var cfg = config else { return }

        var sensorToMove: SensorConfig?
        outer: for i in cfg.categories.indices {
            if let idx = cfg.categories[i].sensors.firstIndex(where: { $0.key == key }) {
                sensorToMove = cfg.categories[i].sensors.remove(at: idx)
                break outer
            }
            for j in cfg.categories[i].subcategories.indices {
                if let idx = cfg.categories[i].subcategories[j].sensors.firstIndex(where: { $0.key == key }) {
                    sensorToMove = cfg.categories[i].subcategories[j].sensors.remove(at: idx)
                    break outer
                }
            }
        }

        guard let sensor = sensorToMove else { return }

        if let catIdx = cfg.categories.firstIndex(where: { $0.id == toCategoryId }) {
            if let subId = subcategoryId,
               let subIdx = cfg.categories[catIdx].subcategories.firstIndex(where: { $0.id == subId }) {
                cfg.categories[catIdx].subcategories[subIdx].sensors.append(sensor)
            } else {
                cfg.categories[catIdx].sensors.append(sensor)
            }
        }

        config = cfg
        try? ConfigLoader.save(cfg)
    }

    func startMonitoring() {
        guard let config, client != nil else { return }

        monitoringTask?.cancel()
        fullRefreshTask?.cancel()

        monitoringTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

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
            let entityIds = config.allSensors.map(\.entityId)
            let history = try await client.fetchHistory(entityIds: entityIds, hours: selectedTimeRange.rawValue)
            for (entityId, data) in history {
                readings[entityId] = data
            }
            lastError = nil
            lastUpdated = Date()
            NotificationManager.shared.seedState(readings: readings, sensors: config.allSensors)
            await fetchAirQualityLevels()
            await fetchBatteryLevels()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetchLatestStates() async {
        guard let config, let client else { return }

        let sensors = config.allSensors
        let results = await withTaskGroup(of: (SensorConfig, SensorReading?).self) { group in
            for sensor in sensors {
                group.addTask {
                    let reading = try? await client.fetchCurrentState(entityId: sensor.entityId)
                    return (sensor, reading)
                }
            }
            var collected: [(SensorConfig, SensorReading?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        let cutoff = Date().addingTimeInterval(-Double(selectedTimeRange.rawValue) * 3600)
        // Max gap allowed before a reading is considered disconnected from history
        let maxGap: TimeInterval = Double(config.refreshIntervalSeconds) * 5
        var anyUpdated = false

        for (sensor, reading) in results {
            guard let reading else { continue }

            // Always update the latest polled value (used for header display)
            latestValues[sensor.entityId] = reading

            var current = readings[sensor.entityId] ?? []
            if let last = current.last, last.date == reading.date { continue }

            // Only append to chart data if it doesn't create a time gap
            if let last = current.last {
                let gap = reading.date.timeIntervalSince(last.date)
                if gap > maxGap {
                    // Gap too large — skip appending to avoid stretching the chart
                    // The header still shows the current value via latestValues
                    NotificationManager.shared.checkReading(reading, sensor: sensor)
                    anyUpdated = true
                    continue
                }
            }

            current.append(reading)
            current.removeAll { $0.date < cutoff }
            readings[sensor.entityId] = current
            anyUpdated = true

            NotificationManager.shared.checkReading(reading, sensor: sensor)
        }

        if anyUpdated {
            lastError = nil
            lastUpdated = Date()
            await fetchAirQualityLevels()
            await fetchBatteryLevels()
        }
    }

    private func fetchAirQualityLevels() async {
        guard let config, let client else { return }
        let entityIds = config.allAirQualityEntityIds
        guard !entityIds.isEmpty else { return }

        let results = await withTaskGroup(of: (String, String?).self) { group in
            for entityId in entityIds {
                group.addTask {
                    let state = try? await client.fetchStringState(entityId: entityId)
                    return (entityId, state)
                }
            }
            var collected: [(String, String?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        for (entityId, state) in results {
            if let state, let level = AirQualityLevel(haState: state) {
                airQualityLevels[entityId] = level
            } else {
                airQualityLevels[entityId] = nil
            }
        }
    }

    private func fetchBatteryLevels() async {
        guard let config, let client else { return }
        let entityIds = config.allBatteryEntityIds
        guard !entityIds.isEmpty else { return }

        let results = await withTaskGroup(of: (String, Double?).self) { group in
            for entityId in entityIds {
                group.addTask {
                    let reading = try? await client.fetchCurrentState(entityId: entityId)
                    return (entityId, reading?.value)
                }
            }
            var collected: [(String, Double?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        for (entityId, value) in results {
            batteryLevels[entityId] = value
        }
    }
}
