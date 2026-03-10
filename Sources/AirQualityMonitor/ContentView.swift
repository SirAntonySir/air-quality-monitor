import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: SensorViewModel
    @State private var expandedSensor: String?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
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
                .navigationTitle(viewModel.selectionTitle)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        if expandedSensor != nil {
                            Button {
                                withAnimation(.spring(duration: 0.35)) { expandedSensor = nil }
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                        }
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
                .tag("__all__")

            ForEach(viewModel.categories) { category in
                Section {
                    if !category.sensors.isEmpty {
                        Label("Uncategorized", systemImage: category.icon)
                            .tag("cat:\(category.id)")
                    }

                    ForEach(category.subcategories) { sub in
                        Label(sub.name, systemImage: sub.icon)
                            .tag("cat:\(category.id)/sub:\(sub.id)")
                    }
                } header: {
                    Label(category.name, systemImage: category.icon)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()
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

                Button {
                    Task { await viewModel.fetchFullHistory() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Refresh all data")

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Settings")
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
                isExpanded: true
            )
            .matchedGeometryEffect(id: sensor.key, in: chartNamespace)
            .padding(spacing)
            .onTapGesture {
                withAnimation(.spring(duration: 0.35)) { expandedSensor = nil }
            }
            .transition(.opacity)
        } else if sensors.isEmpty {
            ContentUnavailableView(
                "No Sensors",
                systemImage: "sensor",
                description: Text("Add sensors in Settings to get started.")
            )
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
                            isExpanded: false
                        )
                        .matchedGeometryEffect(id: sensor.key, in: chartNamespace)
                        .frame(height: max(cellHeight, 150))
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.35)) {
                                expandedSensor = sensor.key
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
                .padding(spacing)
            }
            .clipped()
            .transition(.opacity)
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
