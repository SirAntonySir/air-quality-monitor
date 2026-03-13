import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// Tracks whether each sensor was last known to be out of range
    private var wasOutOfRange: [String: Bool] = [:]

    /// Cooldown: earliest next notification time per sensor
    private var cooldownUntil: [String: Date] = [:]

    private let cooldownInterval: TimeInterval = 300 // 5 minutes

    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Check a new reading against thresholds and notify on state transitions.
    /// Call this only during incremental polls, not full history loads.
    func checkReading(_ reading: SensorReading, sensor: SensorConfig) {
        let isOut = sensor.isOutOfRange(reading.value)
        let wasOut = wasOutOfRange[sensor.entityId]

        // Update tracked state
        wasOutOfRange[sensor.entityId] = isOut

        // Skip if this is the first reading (no previous state to compare)
        guard let wasOut else { return }

        // Only notify on transitions
        guard isOut != wasOut else { return }

        // Respect cooldown
        if let until = cooldownUntil[sensor.entityId], Date() < until { return }
        cooldownUntil[sensor.entityId] = Date().addingTimeInterval(cooldownInterval)

        if isOut {
            sendOutOfRangeNotification(sensor: sensor, value: reading.value)
        } else {
            sendBackToNormalNotification(sensor: sensor, value: reading.value)
        }
    }

    /// Seed initial state from current readings so the first poll doesn't
    /// spuriously fire notifications.
    func seedState(readings: [String: [SensorReading]], sensors: [SensorConfig]) {
        for sensor in sensors {
            if let last = readings[sensor.entityId]?.last {
                wasOutOfRange[sensor.entityId] = sensor.isOutOfRange(last.value)
            }
        }
    }

    // MARK: - Private

    private func sendOutOfRangeNotification(sensor: SensorConfig, value: Double) {
        let content = UNMutableNotificationContent()
        content.title = "\(sensor.name) Out of Range"
        content.body = thresholdMessage(sensor: sensor, value: value)
        content.sound = .default
        send(content, id: "threshold-\(sensor.entityId)")
    }

    private func sendBackToNormalNotification(sensor: SensorConfig, value: Double) {
        let content = UNMutableNotificationContent()
        content.title = "\(sensor.name) Back to Normal"
        content.body = "\(sensor.name) is \(formatted(value)) \(sensor.unit)"
        content.sound = nil
        send(content, id: "threshold-\(sensor.entityId)")
    }

    private func send(_ content: UNMutableNotificationContent, id: String) {
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func thresholdMessage(sensor: SensorConfig, value: Double) -> String {
        let val = formatted(value)
        if let max = sensor.thresholdMax, value > max {
            return "\(sensor.name) is \(val) \(sensor.unit) (above \(formatted(max)))"
        }
        if let min = sensor.thresholdMin, value < min {
            return "\(sensor.name) is \(val) \(sensor.unit) (below \(formatted(min)))"
        }
        return "\(sensor.name) is \(val) \(sensor.unit)"
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
