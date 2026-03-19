import SwiftUI
import Charts

struct SensorChartView: View {
    let sensor: SensorConfig
    let readings: [SensorReading]
    var isExpanded: Bool = false
    var showThresholdLines: Bool = true
    var showAverageLine: Bool = false

    @State private var hoverDate: Date?
    @State private var hoverValue: Double?
    @State private var cachedPoints: [TaggedPoint] = []
    @State private var cachedYDomain: ClosedRange<Double> = 0...100
    @State private var cachedFiltered: [SensorReading] = []
    @State private var cachedAverage: Double?
    @State private var isHovered = false

    private var currentValue: Double? {
        readings.last?.value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chart
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
                isHovered = true
            } else {
                NSCursor.pop()
                isHovered = false
            }
        }
        .onDisappear {
            if isHovered { NSCursor.pop() }
        }
        .onChange(of: readings.count) {
            recomputeCache()
        }
        .onChange(of: readings.last?.value) {
            recomputeCache()
        }
        .onAppear {
            recomputeCache()
        }
    }

    private func recomputeCache() {
        let filtered = (sensor.filterOutliers == true)
            ? ChartDataProcessor.filterOutliers(from: readings)
            : readings
        cachedFiltered = filtered
        cachedPoints = ChartDataProcessor.buildTaggedPoints(from: filtered, sensor: sensor)

        guard !filtered.isEmpty else {
            cachedYDomain = 0...100
            cachedAverage = nil
            return
        }

        let sum = filtered.reduce(0.0) { $0 + $1.value }
        cachedAverage = sum / Double(filtered.count)

        var lo = Double.infinity
        var hi = -Double.infinity
        for r in filtered {
            if r.value < lo { lo = r.value }
            if r.value > hi { hi = r.value }
        }
        if let tMin = sensor.thresholdMin { lo = min(lo, tMin) }
        if let tMax = sensor.thresholdMax { hi = max(hi, tMax) }
        let padding = max((hi - lo) * 0.12, 1.0)
        cachedYDomain = (lo - padding)...(hi + padding)
    }

    private var displayValue: Double? {
        hoverValue ?? currentValue
    }

    private var displayDate: Date? {
        hoverDate
    }

    private var header: some View {
        HStack(alignment: .top) {
            Label(sensor.name, systemImage: sensor.icon)
                .font(.system(isExpanded ? .title3 : .headline, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let value = displayValue {
                    Text(formattedValue(value) + " " + sensor.unit)
                        .font(.system(isExpanded ? .title : .title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(sensor.isOutOfRange(value) ? .red : .primary)
                } else {
                    Text("--")
                        .font(.system(isExpanded ? .title : .title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                // Always reserve space for timestamp line
                Text(displayDate.map { formatTimestamp($0) } ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(displayDate != nil ? 1 : 0)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(cachedPoints) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value(sensor.unit, point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(point.isWarning ? .red : sensor.swiftColor)
                .lineStyle(StrokeStyle(lineWidth: isExpanded ? 2.5 : 2))
                .interpolationMethod(.catmullRom)
            }

            if showThresholdLines {
                if let max = sensor.thresholdMax {
                    RuleMark(y: .value(sensor.unit, max))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .foregroundStyle(.red.opacity(0.4))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("max \(formattedValue(max))")
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.7))
                        }
                }

                if let min = sensor.thresholdMin {
                    RuleMark(y: .value(sensor.unit, min))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .foregroundStyle(.red.opacity(0.4))
                        .annotation(position: .bottom, alignment: .trailing) {
                            Text("min \(formattedValue(min))")
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.7))
                        }
                }
            }

            if showAverageLine, let avg = cachedAverage {
                RuleMark(y: .value(sensor.unit, avg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, alignment: .leading) {
                        Text("avg \(formattedValue(avg))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }

            // Hover crosshair
            if let hDate = hoverDate, let hValue = hoverValue {
                RuleMark(x: .value("Hover", hDate))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.primary.opacity(0.3))

                PointMark(
                    x: .value("Hover", hDate),
                    y: .value(sensor.unit, hValue)
                )
                .symbolSize(isExpanded ? 60 : 40)
                .foregroundStyle(sensor.isOutOfRange(hValue) ? .red : sensor.swiftColor)
            }
        }
        .chartYScale(domain: cachedYDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: isExpanded ? 12 : 6)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: isExpanded ? 10 : 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else {
                                hoverDate = nil
                                hoverValue = nil
                                return
                            }
                            let origin = geo[plotFrame].origin
                            let locationInPlot = CGPoint(
                                x: location.x - origin.x,
                                y: location.y - origin.y
                            )
                            guard let date: Date = proxy.value(atX: locationInPlot.x) else {
                                hoverDate = nil
                                hoverValue = nil
                                return
                            }
                            let closest = closestReading(to: date, in: cachedFiltered)
                            hoverDate = closest?.date
                            hoverValue = closest?.value
                        case .ended:
                            hoverDate = nil
                            hoverValue = nil
                        }
                    }
            }
        }
    }

    private func formattedValue(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func formatTimestamp(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }
}

// MARK: - Grouped Chart View

struct GroupedChartView: View {
    let sensors: [SensorConfig]
    let readings: [String: [SensorReading]]
    var showAverageLine: Bool = false

    @State private var hoverDate: Date?
    @State private var cachedYDomain: ClosedRange<Double> = 0...100

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            legend
            chart
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .onAppear { recomputeCache() }
        .onChange(of: readingsCount) { recomputeCache() }
    }

    private var readingsCount: Int {
        sensors.reduce(0) { $0 + (readings[$1.entityId]?.count ?? 0) }
    }

    private func recomputeCache() {
        var lo = Double.infinity
        var hi = -Double.infinity
        for sensor in sensors {
            for r in readings[sensor.entityId] ?? [] {
                if r.value < lo { lo = r.value }
                if r.value > hi { hi = r.value }
            }
        }
        guard lo.isFinite else {
            cachedYDomain = 0...100
            return
        }
        let padding = max((hi - lo) * 0.12, 1.0)
        cachedYDomain = (lo - padding)...(hi + padding)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(sensors) { sensor in
                let sensorReadings = readings[sensor.entityId] ?? []
                let value = hoverValue(for: sensor) ?? sensorReadings.last?.value

                HStack(spacing: 6) {
                    Circle()
                        .fill(sensor.swiftColor)
                        .frame(width: 8, height: 8)
                    Text(sensor.name)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)

                    if let value {
                        Text(formattedValue(value) + " " + sensor.unit)
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                            .foregroundStyle(sensor.isOutOfRange(value) ? .red : sensor.swiftColor)
                    }
                }
            }

            Spacer()

            if let hoverDate {
                Text(hoverDate.formatted(.dateTime.hour().minute().second()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(sensors) { sensor in
                let sensorReadings = readings[sensor.entityId] ?? []
                ForEach(sensorReadings) { reading in
                    LineMark(
                        x: .value("Time", reading.date),
                        y: .value("Value", reading.value),
                        series: .value("Sensor", sensor.key)
                    )
                    .foregroundStyle(sensor.swiftColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
            }

            if showAverageLine {
                ForEach(sensors) { sensor in
                    let sensorReadings = readings[sensor.entityId] ?? []
                    if !sensorReadings.isEmpty {
                        let avg = sensorReadings.reduce(0.0) { $0 + $1.value } / Double(sensorReadings.count)
                        RuleMark(y: .value("Value", avg))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(sensor.swiftColor.opacity(0.4))
                    }
                }
            }

            if let hoverDate {
                RuleMark(x: .value("Hover", hoverDate))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.primary.opacity(0.3))

                ForEach(sensors) { sensor in
                    if let value = hoverValue(for: sensor) {
                        PointMark(
                            x: .value("Hover", hoverDate),
                            y: .value("Value", value)
                        )
                        .symbolSize(40)
                        .foregroundStyle(sensor.swiftColor)
                    }
                }
            }
        }
        .chartYScale(domain: cachedYDomain)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 8)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else {
                                hoverDate = nil
                                return
                            }
                            let origin = geo[plotFrame].origin
                            let x = location.x - origin.x
                            hoverDate = proxy.value(atX: x)
                        case .ended:
                            hoverDate = nil
                        }
                    }
            }
        }
    }

    private func hoverValue(for sensor: SensorConfig) -> Double? {
        guard let hoverDate else { return nil }
        let sensorReadings = readings[sensor.entityId] ?? []
        return closestReading(to: hoverDate, in: sensorReadings)?.value
    }

    private func formattedValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

// MARK: - Binary search for closest reading

/// Binary search for the closest reading to a target date. Readings must be sorted by date.
private func closestReading(to date: Date, in readings: [SensorReading]) -> SensorReading? {
    guard !readings.isEmpty else { return nil }

    let target = date.timeIntervalSince1970
    var lo = 0
    var hi = readings.count - 1

    while lo < hi {
        let mid = (lo + hi) / 2
        if readings[mid].date.timeIntervalSince1970 < target {
            lo = mid + 1
        } else {
            hi = mid
        }
    }

    // lo is the insertion point; compare lo and lo-1 to find closest
    let candidate = readings[lo]
    if lo > 0 {
        let prev = readings[lo - 1]
        if abs(prev.date.timeIntervalSince(date)) < abs(candidate.date.timeIntervalSince(date)) {
            return prev
        }
    }
    return candidate
}
