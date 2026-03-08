import SwiftUI

struct MenuBarLabel: View {
    let viewModel: SensorViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "aqi.medium")
            if let co2 = viewModel.currentValue(forKey: "co2") {
                Text("\(Int(co2))")
                    .monospacedDigit()
            }
        }
    }
}

struct MenuBarView: View {
    let viewModel: SensorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Air Quality")
                .font(.system(.headline, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            VStack(spacing: 2) {
                ForEach(viewModel.sensorConfigs) { sensor in
                    MenuBarSensorRow(sensor: sensor, viewModel: viewModel)
                }
            }
            .padding(.vertical, 4)

            HStack {
                if let updated = viewModel.lastUpdated {
                    Text("Updated \(updated, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button("Refresh") {
                    Task { await viewModel.fetchFullHistory() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(width: 260)
    }
}

private struct MenuBarSensorRow: View {
    let sensor: SensorConfig
    let viewModel: SensorViewModel

    private var value: Double? {
        viewModel.currentValue(for: sensor)
    }

    private var isWarning: Bool {
        guard let value else { return false }
        return sensor.isOutOfRange(value)
    }

    var body: some View {
        HStack {
            Image(systemName: sensor.icon)
                .frame(width: 20)
                .foregroundStyle(isWarning ? .red : sensor.swiftColor)

            Text(sensor.name)
                .foregroundStyle(.secondary)

            Spacer()

            if let value {
                Text(formatted(value) + " " + sensor.unit)
                    .monospacedDigit()
                    .fontWeight(.medium)
                    .foregroundStyle(isWarning ? .red : .primary)
            } else {
                Text("--")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(.body, design: .rounded))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
