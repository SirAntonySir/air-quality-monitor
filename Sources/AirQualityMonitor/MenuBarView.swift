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
                ForEach(viewModel.categories) { category in
                    if !category.allSensors.isEmpty {
                        MenuBarCategorySection(category: category, viewModel: viewModel)
                    }
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
        .frame(width: 280)
    }
}

private struct MenuBarCategorySection: View {
    let category: SensorCategory
    let viewModel: SensorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Category header
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                Text(category.name)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Direct sensors
            ForEach(category.sensors) { sensor in
                MenuBarSensorRow(sensor: sensor, viewModel: viewModel)
            }

            // Subcategory sensors
            ForEach(category.subcategories) { sub in
                if !sub.sensors.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: sub.icon)
                        Text(sub.name)
                            .font(.system(.caption2, design: .rounded))
                    }
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)

                    ForEach(sub.sensors) { sensor in
                        MenuBarSensorRow(sensor: sensor, viewModel: viewModel)
                    }
                }
            }
        }
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
