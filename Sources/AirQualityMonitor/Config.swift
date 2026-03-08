import Foundation
import SwiftUI

struct AppConfig: Codable {
    var homeAssistantURL: String
    var token: String
    var refreshIntervalSeconds: Int
    var fullRefreshIntervalSeconds: Int
    var historyHours: Int
    var sensors: [SensorConfig]

    static let defaultSensors: [SensorConfig] = [
        SensorConfig(key: "temperature", entityId: "sensor.alpstuga_air_quality_monitor_temperature",
                     name: "Temperature", unit: "\u{00b0}C", icon: "thermometer.medium",
                     color: "orange", thresholdMin: 18, thresholdMax: 26),
        SensorConfig(key: "humidity", entityId: "sensor.alpstuga_air_quality_monitor_humidity",
                     name: "Humidity", unit: "%", icon: "humidity",
                     color: "cyan", thresholdMin: 30, thresholdMax: 60),
        SensorConfig(key: "co2", entityId: "sensor.alpstuga_air_quality_monitor_carbon_dioxide",
                     name: "CO\u{2082}", unit: "ppm", icon: "aqi.medium",
                     color: "green", thresholdMin: nil, thresholdMax: 1000),
        SensorConfig(key: "pm25", entityId: "sensor.alpstuga_air_quality_monitor_pm2_5",
                     name: "PM2.5", unit: "\u{00b5}g/m\u{00b3}", icon: "smoke",
                     color: "purple", thresholdMin: nil, thresholdMax: 25),
    ]

    static var empty: AppConfig {
        AppConfig(
            homeAssistantURL: "http://",
            token: "",
            refreshIntervalSeconds: 30,
            fullRefreshIntervalSeconds: 900,
            historyHours: 12,
            sensors: defaultSensors
        )
    }
}

struct SensorConfig: Codable, Identifiable {
    var key: String
    var entityId: String
    var name: String
    var unit: String
    var icon: String
    var color: String
    var thresholdMin: Double?
    var thresholdMax: Double?

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
