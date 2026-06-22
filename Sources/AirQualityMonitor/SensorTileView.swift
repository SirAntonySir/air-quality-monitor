import SwiftUI
import Charts

/// Compact overview tile: metric name + current value + mini sparkline + trend.
/// Grouped under a device header (which carries room/status/battery) in the
/// "All Sensors" overview; tapping expands the full chart.
struct SensorTileView: View {
    let sensor: SensorConfig
    let readings: [SensorReading]
    var latestValue: Double?
    var trend: Double?

    private var value: Double? { latestValue ?? readings.last?.value }
    private var outOfRange: Bool {
        guard let value else { return false }
        return sensor.isOutOfRange(value)
    }

    private var sparkPoints: [SensorReading] {
        ChartDataProcessor.downsample(readings, targetCount: 80)
    }

    /// Plotted min...max — the sparkline is sized to the data (not the
    /// thresholds), and the line gradient maps to this bounding box.
    private var sparkDataDomain: ClosedRange<Double> {
        let values = sparkPoints.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 0...100 }
        return lo <= hi ? lo...hi : lo...(lo + 1)
    }

    private var sparkDomain: ClosedRange<Double> {
        let d = sparkDataDomain
        let pad = max((d.upperBound - d.lowerBound) * 0.15, 0.5)
        return (d.lowerBound - pad)...(d.upperBound + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            valueRow
            sparkline
            Spacer(minLength: 0)
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .overlay {
            if outOfRange {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.red.opacity(0.45), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(spacing: 4) {
            IconView(name: sensor.icon)
            Text(sensor.name)
            Spacer()
        }
        .font(.system(.subheadline, design: .rounded, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let value {
                Text(formattedValue(value))
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .foregroundStyle(outOfRange ? .red : .primary)
                Text(sensor.unit)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sparkline: some View {
        Chart {
            ForEach(sparkPoints) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(sensor.thresholdLineStyle(yDomain: sparkDataDomain))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: sparkDomain)
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 38)
        .opacity(sparkPoints.isEmpty ? 0 : 1)
    }

    private var footer: some View {
        HStack {
            if let trend {
                trendView(trend)
            }
            Spacer()
        }
    }

    private func trendView(_ delta: Double) -> some View {
        let flat = abs(delta) < 0.05
        let symbol = flat ? "arrow.right" : (delta > 0 ? "arrow.up.right" : "arrow.down.right")
        return HStack(spacing: 3) {
            Image(systemName: symbol)
            Text((delta > 0 ? "+" : "") + formattedValue(delta) + " " + sensor.unit)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func formattedValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
