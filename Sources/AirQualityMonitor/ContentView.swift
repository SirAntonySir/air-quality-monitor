import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: SensorViewModel
    @State private var expandedSensor: String?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @State private var groupedMode = false
    @Namespace private var chartNamespace

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 260)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    sidebarFooter
                }
        } detail: {
            detailContent
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        if expandedSensor != nil {
                            Button {
                                withAnimation(.spring(duration: 0.35)) { expandedSensor = nil }
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                            .keyboardShortcut(.escape, modifiers: [])
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Picker("Display", selection: $groupedMode) {
                            Image(systemName: "square.grid.2x2")
                                .tag(false)
                            Image(systemName: "chart.xyaxis.line")
                                .tag(true)
                        }
                        .pickerStyle(.segmented)
                        .help(groupedMode ? "Combined chart" : "Individual charts")
                    }
                    ToolbarItem(placement: .automatic) {
                        Picker("Time Range", selection: Binding(
                            get: { viewModel.selectedTimeRange },
                            set: { viewModel.changeTimeRange(to: $0) }
                        )) {
                            ForEach(TimeRange.allCases) { range in
                                Text(range.label).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .help("History time range")
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            Task { await viewModel.fetchFullHistory() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh all data")
                    }
                    ToolbarItem(placement: .automatic) {
                        SettingsLink {
                            Image(systemName: "gearshape")
                        }
                        .help("Settings")
                    }
                }
        }
        .frame(minWidth: 900, minHeight: 550)
        .background {
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: Binding(
            get: { sidebarSelection },
            set: { applySidebarSelection($0) }
        )) {
            Label("All Sensors", systemImage: "square.grid.2x2")
                .font(.system(.body, weight: .medium))
                .tag("__all__")

            ForEach(viewModel.categories.filter { !$0.allSensors.isEmpty }) { category in
                IconLabel(title: category.name, icon: category.icon)
                    .font(.system(.body, weight: .medium))
                    .tag("cat:\(category.id)")

                ForEach(category.subcategories.filter { !$0.sensors.isEmpty }) { sub in
                    HStack {
                        IconLabel(title: sub.name, icon: sub.icon)
                        Spacer()
                        if let level = viewModel.airQualityLevel(for: sub) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(level.color)
                                    .frame(width: 6, height: 6)
                                Text(level.label)
                                    .font(.system(.caption2, weight: .semibold))
                                    .foregroundStyle(level.color)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(level.color.opacity(0.12)))
                        }
                    }
                    .padding(.leading, 12)
                    .tag("cat:\(category.id)/sub:\(sub.id)")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let error = viewModel.lastError {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .help(error)
                }

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }

                if let updated = viewModel.lastUpdated {
                    Text("Updated \(updated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var sidebarSelection: String? {
        guard let catId = viewModel.selectedCategoryId else {
            return "__all__"
        }
        if let subId = viewModel.selectedSubcategoryId {
            return "cat:\(catId)/sub:\(subId)"
        }
        return "cat:\(catId)"
    }

    private func applySidebarSelection(_ tag: String?) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedSensor = nil

            guard let tag else {
                viewModel.selectedCategoryId = nil
                viewModel.selectedSubcategoryId = nil
                return
            }

            if tag == "__all__" {
                viewModel.selectedCategoryId = nil
                viewModel.selectedSubcategoryId = nil
            } else if tag.contains("/sub:") {
                let parts = tag.split(separator: "/")
                let catId = String(parts[0].dropFirst(4))
                let subId = String(parts[1].dropFirst(4))
                viewModel.selectedCategoryId = catId
                viewModel.selectedSubcategoryId = subId
            } else if tag.hasPrefix("cat:") {
                let catId = String(tag.dropFirst(4))
                viewModel.selectedCategoryId = catId
                viewModel.selectedSubcategoryId = nil
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        let sensors = viewModel.visibleSensors
        let spacing: CGFloat = 12

        if let expandedKey = expandedSensor,
           let sensor = sensors.first(where: { $0.key == expandedKey }) {
            SensorChartView(
                sensor: sensor,
                readings: viewModel.readings[sensor.entityId] ?? [],
                isExpanded: true,
                showThresholdLines: viewModel.config?.showThresholdLines ?? true,
                showAverageLine: viewModel.config?.showAverageLine ?? false,
                timeRangeHours: viewModel.selectedTimeRange.rawValue,
                latestValue: viewModel.latestValues[sensor.entityId]?.value
            )
            .matchedGeometryEffect(id: sensor.key, in: chartNamespace)
            .padding(spacing)
            .transition(.opacity)
        } else if sensors.isEmpty {
            ContentUnavailableView(
                "No Sensors",
                systemImage: "sensor",
                description: Text("Add sensors in Settings to get started.")
            )
        } else if groupedMode {
            let grouped = Dictionary(grouping: sensors, by: \.unit)
            let unitOrder = grouped.keys.sorted()
            GeometryReader { geo in
                let count = unitOrder.count
                let columns = gridColumns(for: count, in: geo.size)
                let rowCount = Int(ceil(Double(count) / Double(columns.count)))
                let cellHeight = (geo.size.height - CGFloat(rowCount + 1) * spacing) / CGFloat(rowCount)

                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(unitOrder, id: \.self) { unit in
                        GroupedChartView(
                            sensors: grouped[unit] ?? [],
                            readings: viewModel.readings,
                            showAverageLine: viewModel.config?.showAverageLine ?? false,
                            timeRangeHours: viewModel.selectedTimeRange.rawValue
                        )
                        .frame(height: max(cellHeight, 200))
                    }
                }
                .padding(spacing)
            }
            .clipped()
            .transition(.opacity)
        } else {
            GeometryReader { geo in
                let columns = gridColumns(for: sensors.count, in: geo.size)
                let rowCount = Int(ceil(Double(sensors.count) / Double(columns.count)))
                let cellHeight = (geo.size.height - CGFloat(rowCount + 1) * spacing) / CGFloat(rowCount)

                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(sensors) { sensor in
                        SensorChartView(
                            sensor: sensor,
                            readings: viewModel.readings[sensor.entityId] ?? [],
                            isExpanded: false,
                            showThresholdLines: viewModel.config?.showThresholdLines ?? true,
                            showAverageLine: viewModel.config?.showAverageLine ?? false,
                            timeRangeHours: viewModel.selectedTimeRange.rawValue,
                            latestValue: viewModel.latestValues[sensor.entityId]?.value
                        )
                        .matchedGeometryEffect(id: sensor.key, in: chartNamespace)
                        .frame(height: max(cellHeight, 150))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(duration: 0.35)) {
                                expandedSensor = sensor.key
                            }
                        }
                        .contextMenu {
                            sensorContextMenu(for: sensor)
                        }
                    }
                }
                .padding(spacing)
            }
            .clipped()
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func sensorContextMenu(for sensor: SensorConfig) -> some View {
        if let config = viewModel.config {
            Menu("Move to\u{2026}") {
                ForEach(config.categories) { cat in
                    Button(cat.name) {
                        viewModel.moveSensor(key: sensor.key, toCategoryId: cat.id, subcategoryId: nil)
                    }
                    ForEach(cat.subcategories) { sub in
                        Button("\(cat.name) \u{2192} \(sub.name)") {
                            viewModel.moveSensor(key: sensor.key, toCategoryId: cat.id, subcategoryId: sub.id)
                        }
                    }
                }
            }

            Divider()

            Button(viewModel.config?.menuBarSensorKey == sensor.key
                   ? "Menu Bar Sensor \u{2713}"
                   : "Show in Menu Bar") {
                viewModel.setMenuBarSensorKey(sensor.key)
            }
        }
    }

    private func gridColumns(for count: Int, in size: CGSize) -> [GridItem] {
        let spacing: CGFloat = 12
        let colCount: Int
        switch count {
        case 1: colCount = 1
        case 2: colCount = 2
        case 3: colCount = size.width > 900 ? 3 : 2
        case 4: colCount = 2
        case 5...6: colCount = 3
        default: colCount = size.width > 1200 ? 4 : 3
        }
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: colCount)
    }
}

private struct AirQualityBadgeBar: View {
    let viewModel: SensorViewModel

    var body: some View {
        let states = viewModel.airQualityRoomStates
        if !states.isEmpty {
            HStack(spacing: 6) {
                ForEach(states, id: \.subcategory.id) { item in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(item.level?.color ?? .gray)
                            .frame(width: 7, height: 7)
                        Text(item.subcategory.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(item.level?.label ?? "–")
                            .font(.system(.caption2, weight: .semibold))
                            .foregroundStyle(item.level?.color ?? .gray)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((item.level?.color ?? .gray).opacity(0.12))
                    )
                    .help("\(item.subcategory.name): \(item.level?.label ?? "Unknown")")
                }
            }
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

