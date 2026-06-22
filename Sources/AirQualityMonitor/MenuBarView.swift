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
    @Environment(\.openWindow) private var openWindow

    /// When true, tapping a value row sets it as the menu-bar sensor instead of
    /// opening the app.
    @State private var pickingMenuBarSensor = false

    private var menuBarSensorKey: String? { viewModel.menuBarSensor?.key }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ForEach(viewModel.allDeviceGroups) { group in
                MenuBarDeviceSection(
                    group: group,
                    attention: hasWarning(group),
                    picking: pickingMenuBarSensor,
                    menuBarSensorKey: menuBarSensorKey,
                    viewModel: viewModel,
                    onTapSensor: { tapSensor($0) },
                    onOpenRoom: { if !pickingMenuBarSensor { openRoom(group) } }
                )
                .padding(.horizontal, 14)
            }

            controls
                .padding(.horizontal, 14)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(width: 330)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Air Quality")
                .font(.system(.headline, design: .rounded))
            Spacer()
            if let summary {
                HStack(spacing: 5) {
                    Image(systemName: summary.symbol)
                        .font(.caption2)
                    Text(summary.label)
                        .font(.system(.caption, weight: .semibold))
                }
                .foregroundStyle(summary.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(summary.color.opacity(0.15)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Controls

    private var controls: some View {
        GroupBox {
            VStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { pickingMenuBarSensor.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "menubar.rectangle")
                        Text(pickingMenuBarSensor ? "Tap a value above to show" : "Set Menu Bar Value")
                            .fontWeight(.medium)
                        Spacer()
                        if pickingMenuBarSensor {
                            Text("Cancel")
                                .foregroundStyle(.secondary)
                        } else if let name = viewModel.menuBarSensor?.name {
                            Text(name)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(pickingMenuBarSensor
                                  ? Color.accentColor.opacity(0.18)
                                  : Color.primary.opacity(0.06))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await viewModel.fetchFullHistory() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                            .fontWeight(.medium)
                        Spacer()
                        if let updated = viewModel.lastUpdated {
                            Text("Updated \(updated, style: .relative) ago")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        } label: {
            Label("Controls", systemImage: "gearshape")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func tapSensor(_ key: String) {
        if pickingMenuBarSensor {
            viewModel.setMenuBarSensorKey(key)
            withAnimation(.easeInOut(duration: 0.15)) { pickingMenuBarSensor = false }
        } else {
            open(focusKey: key)
        }
    }

    private func open(focusKey: String?) {
        if let focusKey { viewModel.focus(sensorKey: focusKey) }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openRoom(_ group: DeviceGroup) {
        viewModel.focusRoom(categoryId: group.categoryId, subcategoryId: group.subcategoryId)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Status

    private func hasWarning(_ group: DeviceGroup) -> Bool {
        group.sensors.contains { sensor in
            guard let value = viewModel.currentValue(for: sensor) else { return false }
            return sensor.isOutOfRange(value)
        }
    }

    /// True if any sensor's current reading is out of its threshold range.
    private var overallWarning: Bool {
        viewModel.config?.allSensors.contains { sensor in
            guard let value = viewModel.currentValue(for: sensor) else { return false }
            return sensor.isOutOfRange(value)
        } ?? false
    }

    private var summary: (label: String, color: Color, symbol: String)? {
        if overallWarning {
            return ("Attention", .red, "exclamationmark.triangle.fill")
        }
        if let worst = viewModel.worstAirQualityLevel {
            return (worst == .good ? "All Good" : worst.label, worst.color, "circle.fill")
        }
        return nil
    }
}

// MARK: - Device Section

private struct MenuBarDeviceSection: View {
    let group: DeviceGroup
    let attention: Bool
    let picking: Bool
    let menuBarSensorKey: String?
    let viewModel: SensorViewModel
    let onTapSensor: (String) -> Void
    let onOpenRoom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            ForEach(group.sensors) { sensor in
                MenuBarSensorRow(
                    sensor: sensor,
                    viewModel: viewModel,
                    picking: picking,
                    isMenuBarSensor: sensor.key == menuBarSensorKey,
                    onTap: { onTapSensor(sensor.key) }
                )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(attention ? Color.red.opacity(0.1) : Color.primary.opacity(0.04))
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            IconView(name: group.icon)
            Text(group.name)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))

            Spacer()

            if let status = group.status {
                statusPill(status)
            }
            if let battery = group.battery {
                batteryChip(battery)
            }
            if !picking {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onOpenRoom() }
        .help(picking ? "" : "Open \(group.name)")
    }

    private func statusPill(_ level: AirQualityLevel) -> some View {
        HStack(spacing: 3) {
            Circle().fill(level.color).frame(width: 5, height: 5)
            Text(level.label)
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(level.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(level.color.opacity(0.15)))
    }

    private func batteryChip(_ level: Double) -> some View {
        let symbol: String
        switch level {
        case 80...: symbol = "battery.100"
        case 50..<80: symbol = "battery.75percent"
        case 25..<50: symbol = "battery.50percent"
        case 10..<25: symbol = "battery.25percent"
        default: symbol = "battery.0percent"
        }
        return HStack(spacing: 2) {
            Image(systemName: symbol)
            Text("\(Int(level.rounded()))%")
        }
        .font(.caption2)
        .foregroundStyle(level < 20 ? .red : .secondary)
    }
}

// MARK: - Sensor Row

private struct MenuBarSensorRow: View {
    let sensor: SensorConfig
    let viewModel: SensorViewModel
    let picking: Bool
    let isMenuBarSensor: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    private var value: Double? { viewModel.currentValue(for: sensor) }
    private var isWarning: Bool {
        guard let value else { return false }
        return sensor.isOutOfRange(value)
    }

    var body: some View {
        HStack(spacing: 10) {
            IconView(name: sensor.icon)
                .frame(width: 20)
                .foregroundStyle(isWarning ? .red : .secondary)
                .opacity(isWarning ? 1 : 0.55)

            Text(sensor.name)
                .foregroundStyle(.secondary)

            if isMenuBarSensor {
                menuBadge
            }

            Spacer()

            if let trend = viewModel.trend(for: sensor) {
                trendArrow(trend)
            }

            if let value {
                Text(formatted(value) + " " + sensor.unit)
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundStyle(isWarning ? .red : .primary)
            } else {
                Text("--")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(.body, design: .rounded))
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(picking ? (isHovered ? 0.9 : 0.4) : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
        .help(picking ? "Show \(sensor.name) in the menu bar" : "Open \(sensor.name)")
    }

    private var menuBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "menubar.rectangle")
            Text("Menu")
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private func trendArrow(_ delta: Double) -> some View {
        let flat = abs(delta) < 0.05
        let symbol = flat ? "arrow.right" : (delta > 0 ? "arrow.up.right" : "arrow.down.right")
        return Image(systemName: symbol)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
