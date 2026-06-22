import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: SensorViewModel
    @State private var expandedSensor: String?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @State private var groupedMode = false
    /// Device-group ids collapsed in the tile overview (session-only).
    @State private var collapsedGroups: Set<String> = []
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
        .onChange(of: viewModel.pendingFocusSensorKey) { _, key in
            guard let key else { return }
            withAnimation(.spring(duration: 0.35)) { expandedSensor = key }
            viewModel.pendingFocusSensorKey = nil
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
            let roomLabels = Dictionary(
                uniqueKeysWithValues: sensors.map {
                    ($0.key, viewModel.roomLabel(forSensorKey: $0.key) ?? $0.name)
                }
            )
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
                            roomLabels: roomLabels,
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
        } else if viewModel.selectedCategoryId == nil {
            tileOverview
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

    private var tileOverview: some View {
        // One column per distinct metric name, ordered by how many rooms have it
        // (most common leftmost). Every room reuses this same column set so matching
        // metrics line up vertically across rooms (gaps trail off to the right).
        let columnNames = metricColumnNames
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: max(columnNames.count, 1)
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(viewModel.visibleDeviceGroups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        deviceHeader(group)
                        if !collapsedGroups.contains(group.id) {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(columnNames, id: \.self) { metric in
                                    if let sensor = group.sensors.first(where: { $0.name == metric }) {
                                        SensorTileView(
                                            sensor: sensor,
                                            readings: viewModel.readings[sensor.entityId] ?? [],
                                            latestValue: viewModel.latestValues[sensor.entityId]?.value,
                                            trend: viewModel.trend(for: sensor)
                                        )
                                        .frame(height: 150)
                                        .onTapGesture {
                                            withAnimation(.spring(duration: 0.35)) { expandedSensor = sensor.key }
                                        }
                                        .contextMenu { sensorContextMenu(for: sensor) }
                                    } else {
                                        Color.clear.frame(height: 150)
                                    }
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    /// Distinct sensor names across visible groups, ordered by the number of rooms
    /// that have each metric (descending), with first-appearance order breaking ties.
    /// Defines the shared column layout for the tile overview — common metrics fill
    /// from the left, rarer ones trail off to the right.
    private var metricColumnNames: [String] {
        var roomCount: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var seq = 0
        for group in viewModel.visibleDeviceGroups {
            var inThisGroup = Set<String>()
            for sensor in group.sensors {
                if firstSeen[sensor.name] == nil {
                    firstSeen[sensor.name] = seq
                    seq += 1
                }
                if inThisGroup.insert(sensor.name).inserted {
                    roomCount[sensor.name, default: 0] += 1
                }
            }
        }
        return roomCount.keys.sorted { a, b in
            if roomCount[a] != roomCount[b] { return roomCount[a]! > roomCount[b]! }
            return firstSeen[a]! < firstSeen[b]!
        }
    }

    private func deviceHeader(_ group: DeviceGroup) -> some View {
        let collapsed = collapsedGroups.contains(group.id)
        return Button {
            withAnimation(.spring(duration: 0.3)) {
                if collapsed { collapsedGroups.remove(group.id) }
                else { collapsedGroups.insert(group.id) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                IconLabel(title: group.name, icon: group.icon)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                if let status = group.status {
                    statusPill(status)
                }
                if let battery = group.battery {
                    batteryChip(battery)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusPill(_ level: AirQualityLevel) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(level.color)
                .frame(width: 6, height: 6)
            Text(level.label)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(level.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(level.color.opacity(0.12)))
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
        return HStack(spacing: 3) {
            Image(systemName: symbol)
            Text("\(Int(level.rounded()))%")
        }
        .font(.caption)
        .foregroundStyle(level < 20 ? .red : .secondary)
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

