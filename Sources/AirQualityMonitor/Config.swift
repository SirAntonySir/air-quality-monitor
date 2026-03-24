import Foundation
import SwiftUI

// MARK: - Data Model

struct AppConfig: Codable {
    var homeAssistantURL: String
    var token: String
    var refreshIntervalSeconds: Int
    var fullRefreshIntervalSeconds: Int
    var historyHours: Int
    var categories: [SensorCategory]
    var menuBarSensorKey: String?
    var showThresholdLines: Bool
    var showAverageLine: Bool

    /// All sensors across all categories and subcategories (for fetching)
    var allSensors: [SensorConfig] {
        categories.flatMap { cat in
            cat.sensors + cat.subcategories.flatMap(\.sensors)
        }
    }

    /// All air quality entity IDs from subcategories
    var allAirQualityEntityIds: [String] {
        categories.flatMap(\.subcategories).compactMap(\.airQualityEntityId).filter { !$0.isEmpty }
    }

    // MARK: - Migration from flat sensors array

    enum CodingKeys: String, CodingKey {
        case homeAssistantURL, token, refreshIntervalSeconds, fullRefreshIntervalSeconds, historyHours
        case categories, sensors, menuBarSensorKey // "sensors" for legacy format
        case showThresholdLines, showAverageLine
    }

    init(homeAssistantURL: String, token: String, refreshIntervalSeconds: Int,
         fullRefreshIntervalSeconds: Int, historyHours: Int, categories: [SensorCategory],
         menuBarSensorKey: String? = nil, showThresholdLines: Bool = true, showAverageLine: Bool = false) {
        self.homeAssistantURL = homeAssistantURL
        self.token = token
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.fullRefreshIntervalSeconds = fullRefreshIntervalSeconds
        self.historyHours = historyHours
        self.categories = categories
        self.menuBarSensorKey = menuBarSensorKey
        self.showThresholdLines = showThresholdLines
        self.showAverageLine = showAverageLine
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        homeAssistantURL = try container.decode(String.self, forKey: .homeAssistantURL)
        token = try container.decode(String.self, forKey: .token)
        refreshIntervalSeconds = try container.decode(Int.self, forKey: .refreshIntervalSeconds)
        fullRefreshIntervalSeconds = try container.decode(Int.self, forKey: .fullRefreshIntervalSeconds)
        historyHours = try container.decode(Int.self, forKey: .historyHours)

        menuBarSensorKey = try container.decodeIfPresent(String.self, forKey: .menuBarSensorKey)
        showThresholdLines = try container.decodeIfPresent(Bool.self, forKey: .showThresholdLines) ?? true
        showAverageLine = try container.decodeIfPresent(Bool.self, forKey: .showAverageLine) ?? false

        // Try new format first, fall back to legacy flat sensors
        if let cats = try? container.decode([SensorCategory].self, forKey: .categories) {
            categories = cats
        } else if let flatSensors = try? container.decode([SensorConfig].self, forKey: .sensors) {
            // Migrate: group into a single "General" category
            categories = [
                SensorCategory(
                    id: "general",
                    name: "General",
                    icon: "home",
                    sensors: flatSensors,
                    subcategories: []
                )
            ]
        } else {
            categories = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(homeAssistantURL, forKey: .homeAssistantURL)
        try container.encode(token, forKey: .token)
        try container.encode(refreshIntervalSeconds, forKey: .refreshIntervalSeconds)
        try container.encode(fullRefreshIntervalSeconds, forKey: .fullRefreshIntervalSeconds)
        try container.encode(historyHours, forKey: .historyHours)
        try container.encode(categories, forKey: .categories)
        try container.encodeIfPresent(menuBarSensorKey, forKey: .menuBarSensorKey)
        try container.encode(showThresholdLines, forKey: .showThresholdLines)
        try container.encode(showAverageLine, forKey: .showAverageLine)
    }

    static let defaultCategories: [SensorCategory] = [
        SensorCategory(
            id: "air-quality",
            name: "Air Quality",
            icon: "aqi.medium",
            sensors: [],
            subcategories: [
                SensorSubcategory(
                    id: "living-room-air",
                    name: "Living Room",
                    icon: "sofa",
                    sensors: [
                        SensorConfig(key: "co2", entityId: "sensor.alpstuga_air_quality_monitor_carbon_dioxide",
                                     name: "CO\u{2082}", unit: "ppm", icon: "carbon.dioxide.cloud",
                                     color: "green", thresholdMin: nil, thresholdMax: 1000),
                        SensorConfig(key: "pm25", entityId: "sensor.alpstuga_air_quality_monitor_pm2_5",
                                     name: "PM2.5", unit: "\u{00b5}g/m\u{00b3}", icon: "smoke",
                                     color: "purple", thresholdMin: nil, thresholdMax: 25, filterOutliers: true),
                    ],
                    airQualityEntityId: "sensor.alpstuga_air_quality_monitor_air_quality"
                )
            ]
        ),
        SensorCategory(
            id: "climate",
            name: "Climate",
            icon: "thermometer.medium",
            sensors: [],
            subcategories: [
                SensorSubcategory(
                    id: "living-room-climate",
                    name: "Living Room",
                    icon: "sofa",
                    sensors: [
                        SensorConfig(key: "temperature", entityId: "sensor.alpstuga_air_quality_monitor_temperature",
                                     name: "Temperature", unit: "\u{00b0}C", icon: "thermometer.medium",
                                     color: "orange", thresholdMin: 18, thresholdMax: 26),
                        SensorConfig(key: "humidity", entityId: "sensor.alpstuga_air_quality_monitor_humidity",
                                     name: "Humidity", unit: "%", icon: "humidity",
                                     color: "cyan", thresholdMin: 30, thresholdMax: 60),
                    ]
                )
            ]
        ),
    ]

    static var empty: AppConfig {
        AppConfig(
            homeAssistantURL: "http://",
            token: "",
            refreshIntervalSeconds: 30,
            fullRefreshIntervalSeconds: 900,
            historyHours: 12,
            categories: defaultCategories
        )
    }
}

// MARK: - Category

struct SensorCategory: Codable, Identifiable {
    var id: String
    var name: String
    var icon: String
    var sensors: [SensorConfig]
    var subcategories: [SensorSubcategory]

    /// All sensors in this category (direct + from subcategories)
    var allSensors: [SensorConfig] {
        sensors + subcategories.flatMap(\.sensors)
    }
}

// MARK: - Subcategory

struct SensorSubcategory: Codable, Identifiable {
    var id: String
    var name: String
    var icon: String
    var sensors: [SensorConfig]
    var airQualityEntityId: String?
}

// MARK: - Sensor

struct SensorConfig: Codable, Identifiable {
    var key: String
    var entityId: String
    var name: String
    var unit: String
    var icon: String
    var color: String
    var thresholdMin: Double?
    var thresholdMax: Double?
    var filterOutliers: Bool?

    var id: String { key }

    var swiftColor: Color {
        switch color {
        case "orange": return .orange
        case "cyan": return .cyan
        case "green": return .green
        case "purple": return .purple
        case "blue": return .blue
        case "red": return .red
        case "yellow": return .yellow
        case "pink": return .pink
        default: return .accentColor
        }
    }

    func isOutOfRange(_ value: Double) -> Bool {
        if let min = thresholdMin, value < min { return true }
        if let max = thresholdMax, value > max { return true }
        return false
    }
}

// MARK: - Config Loader

enum ConfigLoader {
    static let configDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("airquality-monitor")
    }()

    static let configFile: URL = {
        configDirectory.appendingPathComponent("config.json")
    }()

    static func load() throws -> AppConfig {
        let data = try Data(contentsOf: configFile)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    static func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configFile, options: .atomic)
    }

    static func configExists() -> Bool {
        FileManager.default.fileExists(atPath: configFile.path)
    }
}
