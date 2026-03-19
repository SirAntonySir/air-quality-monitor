import Foundation

struct SensorReading: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct TaggedPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let isWarning: Bool
    let segment: Int
}

struct HAStateEntry: Decodable {
    let entityId: String
    let state: String
    let lastChanged: Date

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state
        case lastChanged = "last_changed"
    }
}

extension JSONDecoder {
    static var homeAssistant: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }

            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }

            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid date: \(string)")
            )
        }
        return decoder
    }
}

enum ChartDataProcessor {
    /// Filters out isolated outlier spikes while preserving sustained elevated readings.
    ///
    /// Uses a rolling median window to detect values that deviate significantly from
    /// their surroundings. Short runs of elevated values (< `minRunLength`) are treated
    /// as sensor glitches and removed. Longer runs are kept — they likely represent
    /// real events (cooking, traffic, etc.).
    static func filterOutliers(
        from readings: [SensorReading],
        minRunLength: Int = 3,
        windowSize: Int = 24
    ) -> [SensorReading] {
        guard readings.count > minRunLength else { return readings }

        // Use a wide window so dense spike clusters don't pollute the median
        let halfWindow = windowSize / 2
        var elevated = [Bool](repeating: false, count: readings.count)

        // Pre-sort all values to compute a global baseline for edge cases
        let allValues = readings.map(\.value).sorted()
        let globalMedian = allValues[allValues.count / 2]

        for i in 0..<readings.count {
            let start = max(0, i - halfWindow)
            let end = min(readings.count - 1, i + halfWindow)

            var neighbors: [Double] = []
            for j in start...end where j != i {
                neighbors.append(readings[j].value)
            }
            guard !neighbors.isEmpty else { continue }
            neighbors.sort()
            let median = neighbors[neighbors.count / 2]

            // Use the lower of local and global median to avoid clusters raising the baseline
            let baseline = min(median, globalMedian)
            let value = readings[i].value
            // Elevated if value is more than 3x the baseline AND at least 15 units above it
            elevated[i] = value > baseline * 3 && value > baseline + 15
        }

        // Find runs of elevated readings — short runs are outliers, long runs are real
        var keep = [Bool](repeating: true, count: readings.count)
        var i = 0
        while i < readings.count {
            if elevated[i] {
                var runEnd = i
                while runEnd + 1 < readings.count && elevated[runEnd + 1] {
                    runEnd += 1
                }
                if runEnd - i + 1 < minRunLength {
                    for j in i...runEnd {
                        keep[j] = false
                    }
                }
                i = runEnd + 1
            } else {
                i += 1
            }
        }

        return zip(readings, keep).compactMap { $0.1 ? $0.0 : nil }
    }

    static func buildTaggedPoints(
        from readings: [SensorReading],
        sensor: SensorConfig
    ) -> [TaggedPoint] {
        guard !readings.isEmpty else { return [] }

        var result: [TaggedPoint] = []
        var segmentIndex = 0

        for i in 0..<readings.count {
            let curr = readings[i]
            let currWarning = sensor.isOutOfRange(curr.value)

            if i > 0 {
                let prev = readings[i - 1]
                let prevWarning = sensor.isOutOfRange(prev.value)

                if currWarning != prevWarning {
                    let crossings = findCrossings(from: prev, to: curr, sensor: sensor)
                    for (date, value) in crossings {
                        let beforeWarning = result.last?.isWarning ?? prevWarning
                        result.append(TaggedPoint(
                            date: date, value: value,
                            isWarning: beforeWarning, segment: segmentIndex
                        ))
                        segmentIndex += 1
                        result.append(TaggedPoint(
                            date: date, value: value,
                            isWarning: !beforeWarning, segment: segmentIndex
                        ))
                    }
                }
            }

            result.append(TaggedPoint(
                date: curr.date, value: curr.value,
                isWarning: currWarning, segment: segmentIndex
            ))
        }

        return result
    }

    private static func findCrossings(
        from prev: SensorReading,
        to curr: SensorReading,
        sensor: SensorConfig
    ) -> [(Date, Double)] {
        let boundaries = [sensor.thresholdMin, sensor.thresholdMax].compactMap { $0 }
        var crossings: [(fraction: Double, date: Date, value: Double)] = []

        for boundary in boundaries {
            let v1 = prev.value, v2 = curr.value
            if (v1 < boundary && v2 >= boundary) || (v1 >= boundary && v2 < boundary) {
                let fraction = (boundary - v1) / (v2 - v1)
                if fraction > 0 && fraction < 1 {
                    let t1 = prev.date.timeIntervalSince1970
                    let t2 = curr.date.timeIntervalSince1970
                    let crossDate = Date(timeIntervalSince1970: t1 + fraction * (t2 - t1))
                    crossings.append((fraction, crossDate, boundary))
                }
            }
        }

        crossings.sort { $0.fraction < $1.fraction }
        return crossings.map { ($0.date, $0.value) }
    }
}
