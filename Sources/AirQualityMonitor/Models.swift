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
