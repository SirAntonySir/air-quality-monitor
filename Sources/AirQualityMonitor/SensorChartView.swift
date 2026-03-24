import SwiftUI
import Charts

struct SensorChartView: View {
    let sensor: SensorConfig
    let readings: [SensorReading]
    var isExpanded: Bool = false
    var showThresholdLines: Bool = true
    var showAverageLine: Bool = false
    var timeRangeHours: Int = 12
    var latestValue: Double?

    @State private var hoverDate: Date?
    @State private var hoverValue: Double?
    @State private var cachedPoints: [TaggedPoint] = []
    @State private var cachedYDomain: ClosedRange<Double> = 0...100
    @State private var cachedFiltered: [SensorReading] = []
    @State private var cachedAverage: Double?
    @State private var isHovered = false

    // Drag-to-select state
    @State private var selectionStart: Date?
    @State private var selectionEnd: Date?
    @State private var isDragging = false

    @State private var lastRecomputedCount: Int = -1

    private var currentValue: Double? {
        latestValue ?? readings.last?.value
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
        .onAppear {
            recomputeCache()
        }
    }

    private func recomputeCache() {
        // Skip if nothing changed
        guard readings.count != lastRecomputedCount else { return }
        lastRecomputedCount = readings.count

        // Only run expensive outlier filter on small datasets (< 2000 points)
        // For large datasets, LTTB downsampling naturally smooths spikes
        let filtered: [SensorReading]
        if sensor.filterOutliers == true && readings.count < 2000 {
            filtered = ChartDataProcessor.filterOutliers(from: readings)
        } else {
            filtered = readings
        }
        cachedFiltered = filtered

        let targetCount = isExpanded ? 1200 : 600
        let downsampled = ChartDataProcessor.downsample(filtered, targetCount: targetCount)
        cachedPoints = ChartDataProcessor.buildTaggedPoints(from: downsampled, sensor: sensor)

        guard !filtered.isEmpty else {
            cachedYDomain = 0...100
            cachedAverage = nil
            return
        }

        var lo = Double.infinity
        var hi = -Double.infinity
        var sum = 0.0
        for r in filtered {
            if r.value < lo { lo = r.value }
            if r.value > hi { hi = r.value }
            sum += r.value
        }
        cachedAverage = sum / Double(filtered.count)

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

    private var selectionStats: (min: Double, max: Double, avg: Double, count: Int, start: Date, end: Date)? {
        guard let start = selectionStart, let end = selectionEnd else { return nil }
        let lo = min(start, end)
        let hi = max(start, end)
        let selected = cachedFiltered.filter { $0.date >= lo && $0.date <= hi }
        guard !selected.isEmpty else { return nil }

        var minVal = Double.infinity
        var maxVal = -Double.infinity
        var sum = 0.0
        for r in selected {
            if r.value < minVal { minVal = r.value }
            if r.value > maxVal { maxVal = r.value }
            sum += r.value
        }
        return (min: minVal, max: maxVal, avg: sum / Double(selected.count),
                count: selected.count, start: lo, end: hi)
    }

    private var hasSelection: Bool {
        selectionStart != nil && selectionEnd != nil
    }

    private var header: some View {
        HStack(alignment: .top) {
            IconLabel(title: sensor.name, icon: sensor.icon)
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

            // Selection rectangle
            if let start = selectionStart, let end = selectionEnd {
                let lo = min(start, end)
                let hi = max(start, end)
                RectangleMark(
                    xStart: .value("Start", lo),
                    xEnd: .value("End", hi)
                )
                .foregroundStyle(sensor.swiftColor.opacity(0.08))

                RuleMark(x: .value("SelStart", lo))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(sensor.swiftColor.opacity(0.4))

                RuleMark(x: .value("SelEnd", hi))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(sensor.swiftColor.opacity(0.4))
            }

            // Hover crosshair (hidden during drag / when selection active)
            if !hasSelection, let hDate = hoverDate, let hValue = hoverValue {
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
                if timeRangeHours > 24 {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day().hour())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                        guard !isDragging, !hasSelection else { return }
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
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { drag in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geo[plotFrame].origin

                                if !isDragging {
                                    isDragging = true
                                    hoverDate = nil
                                    hoverValue = nil
                                }

                                let startX = drag.startLocation.x - origin.x
                                let currentX = drag.location.x - origin.x

                                if let startDate: Date = proxy.value(atX: startX),
                                   let currentDate: Date = proxy.value(atX: currentX) {
                                    selectionStart = startDate
                                    selectionEnd = currentDate
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
                    .onTapGesture {
                        selectionStart = nil
                        selectionEnd = nil
                    }
            }
        }
        .overlay(alignment: .top) {
            if let stats = selectionStats {
                selectionStatsOverlay(stats)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
    }

    private func selectionStatsOverlay(
        _ stats: (min: Double, max: Double, avg: Double, count: Int, start: Date, end: Date)
    ) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 12) {
                statLabel("Min", value: stats.min)
                statLabel("Avg", value: stats.avg)
                statLabel("Max", value: stats.max)
            }
            Text("\(formatTimestamp(stats.start)) \u{2013} \(formatTimestamp(stats.end))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func statLabel(_ label: String, value: Double) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formattedValue(value))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(sensor.isOutOfRange(value) ? .red : .primary)
            Text(sensor.unit)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func formattedValue(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func formatTimestamp(_ date: Date) -> String {
        if timeRangeHours > 24 {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return date.formatted(.dateTime.hour().minute().second())
    }
}

// MARK: - Grouped Chart View

struct GroupedChartView: View {
    let sensors: [SensorConfig]
    let readings: [String: [SensorReading]]
    var showAverageLine: Bool = false
    var timeRangeHours: Int = 12

    @State private var hoverDate: Date?
    @State private var cachedYDomain: ClosedRange<Double> = 0...100
    @State private var cachedDownsampled: [String: [SensorReading]] = [:]
    @State private var lastRecomputedCount: Int = -1

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
        let count = readingsCount
        guard count != lastRecomputedCount else { return }
        lastRecomputedCount = count

        var lo = Double.infinity
        var hi = -Double.infinity
        var downsampled: [String: [SensorReading]] = [:]
        for sensor in sensors {
            let sensorReadings = readings[sensor.entityId] ?? []
            let ds = ChartDataProcessor.downsample(sensorReadings, targetCount: 600)
            downsampled[sensor.entityId] = ds
            for r in sensorReadings {
                if r.value < lo { lo = r.value }
                if r.value > hi { hi = r.value }
            }
        }
        cachedDownsampled = downsampled

        if lo.isFinite {
            let padding = max((hi - lo) * 0.12, 1.0)
            cachedYDomain = (lo - padding)...(hi + padding)
        } else {
            cachedYDomain = 0...100
        }
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
                Text(timeRangeHours > 24
                     ? hoverDate.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                     : hoverDate.formatted(.dateTime.hour().minute().second()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(sensors) { sensor in
                let ds = cachedDownsampled[sensor.entityId] ?? []
                ForEach(ds) { reading in
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
                if timeRangeHours > 24 {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day().hour())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
