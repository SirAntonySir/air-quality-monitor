import SwiftUI

struct MenuBarLabel: View {
    let viewModel: SensorViewModel

    private var sensor: SensorConfig? { viewModel.menuBarSensor }

    var body: some View {
        HStack(spacing: 4) {
            IconView(name: sensor?.icon ?? "aqi.medium")
                .foregroundStyle(viewModel.worstAirQualityLevel?.color ?? .secondary)
            if let sensor, let value = viewModel.currentValue(for: sensor) {
                Text("\(Int(value))")
                    .monospacedDigit()
            }
        }
    }
}

struct MenuBarView: View {
    let viewModel: SensorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Air Quality")
                .font(.system(.headline, design: .rounded))
                .padding(.horizontal, 20)
                .padding(.top, 16)

            ForEach(viewModel.categories) { category in
                if !category.allSensors.isEmpty {
                    GroupBox {
                        MenuBarCategoryContent(category: category, viewModel: viewModel)
                            .padding(.vertical, 2)
                    } label: {
                        HStack(spacing: 6) {
                            IconView(name: category.icon)
                            Text(category.name)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                }
            }

            GroupBox {
                VStack(spacing: 8) {
                    Picker("Menu Bar Sensor", selection: Binding(
                        get: { viewModel.config?.menuBarSensorKey ?? viewModel.config?.allSensors.first?.key ?? "" },
                        set: { viewModel.setMenuBarSensorKey($0) }
                    )) {
                        ForEach(viewModel.config?.allSensors ?? []) { sensor in
                            Text(sensor.name).tag(sensor.key)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)

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
                }
                .padding(.vertical, 2)
            } label: {
                Label("Controls", systemImage: "gearshape")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(width: 310)
    }
}

private struct MenuBarCategoryContent: View {
    let category: SensorCategory
    let viewModel: SensorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Direct sensors
            ForEach(category.sensors) { sensor in
                MenuBarSensorRow(sensor: sensor, viewModel: viewModel)
            }

            // Subcategory sensors
            ForEach(category.subcategories) { sub in
                if !sub.sensors.isEmpty {
                    HStack(spacing: 4) {
                        IconView(name: sub.icon)
                        Text(sub.name)
                            .font(.system(.caption2, design: .rounded))

                        Spacer()

                        if let level = viewModel.airQualityLevel(for: sub) {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(level.color)
                                    .frame(width: 5, height: 5)
                                Text(level.label)
                                    .font(.system(.caption2, weight: .semibold))
                                    .foregroundStyle(level.color)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(level.color.opacity(0.15)))
                        }
                    }
                    .foregroundStyle(.quaternary)
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
            IconView(name: sensor.icon)
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
        .padding(.vertical, 4)
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
