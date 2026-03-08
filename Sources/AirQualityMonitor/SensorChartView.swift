import SwiftUI
import Charts

struct SensorChartView: View {
    let sensor: SensorConfig
    let readings: [SensorReading]
    var isExpanded: Bool = false

    @State private var hoverDate: Date?
    @State private var hoverValue: Double?

    private var taggedPoints: [TaggedPoint] {
        ChartDataProcessor.buildTaggedPoints(from: readings, sensor: sensor)
    }

    private var currentValue: Double? {
        readings.last?.value
    }

    private var currentIsWarning: Bool {
        guard let value = currentValue else { return false }
        return sensor.isOutOfRange(value)
    }

    private var yDomain: ClosedRange<Double> {
        guard !readings.isEmpty else { return 0...100 }

        let values = readings.map(\.value)
        let dataMin = values.min()!
        let dataMax = values.max()!

        var lo = dataMin
        var hi = dataMax

        if let tMin = sensor.thresholdMin { lo = min(lo, tMin) }
        if let tMax = sensor.thresholdMax { hi = max(hi, tMax) }

        let padding = max((hi - lo) * 0.12, 1.0)
        return (lo - padding)...(hi + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chart
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .cursor(.pointingHand)
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
            ForEach(taggedPoints) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value(sensor.unit, point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(point.isWarning ? .red : sensor.swiftColor)
                .lineStyle(StrokeStyle(lineWidth: isExpanded ? 2.5 : 2))
                .interpolationMethod(.catmullRom)
            }

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
        .chartYScale(domain: yDomain)
        .chartYAxisLabel(position: .leading) {
            Text(sensor.unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .chartXAxisLabel(position: .bottom, alignment: .center) {
            Text("Time")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                            // Find the closest reading to the hover date
                            let closest = readings.min(by: {
                                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                            })
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

// Helper to set cursor on hover
private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
