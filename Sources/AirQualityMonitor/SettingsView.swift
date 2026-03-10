import SwiftUI

struct SettingsView: View {
    var viewModel: SensorViewModel

    @State private var url: String = ""
    @State private var token: String = ""
    @State private var historyHours: Int = 12
    @State private var refreshInterval: Int = 30
    @State private var fullRefreshInterval: Int = 900
    @State private var categories: [SensorCategory] = []
    @State private var saveMessage: String?
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var updateStatus: UpdateStatus = .idle

    var body: some View {
        TabView {
            connectionTab
                .tabItem { Label("Connection", systemImage: "network") }
            sensorsTab
                .tabItem { Label("Sensors", systemImage: "sensor") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 600, height: 520)
        .onAppear(perform: loadFromConfig)
    }

    // MARK: - Connection Tab

    private var connectionTab: some View {
        Form {
            Section {
                TextField("Home Assistant URL", text: $url, prompt: Text("http://192.168.178.120:8123"))
                    .textFieldStyle(.roundedBorder)

                SecureField("Long-Lived Access Token", text: $token, prompt: Text("Paste token here"))
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Home Assistant")
            }

            Section {
                Stepper("History: \(historyHours) hours", value: $historyHours, in: 1...240)
                Stepper("Poll interval: \(refreshInterval)s", value: $refreshInterval, in: 5...300, step: 5)
                Stepper("Full refresh: \(fullRefreshInterval / 60) min", value: $fullRefreshInterval, in: 60...3600, step: 60)
            } header: {
                Text("Refresh")
            }

            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(url.isEmpty || token.isEmpty || isTesting)

                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("OK") ? .green : .red)
                }

                Spacer()

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(url.isEmpty || token.isEmpty)

                if let msg = saveMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Sensors Tab

    private var sensorsTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach($categories) { $category in
                        CategoryEditorView(category: $category, onDelete: {
                            categories.removeAll { $0.id == category.id }
                        })
                    }

                    Button {
                        let newId = "category-\(UUID().uuidString.prefix(8).lowercased())"
                        categories.append(SensorCategory(
                            id: newId, name: "New Category", icon: "folder",
                            sensors: [], subcategories: []
                        ))
                    } label: {
                        Label("Add Category", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 8)
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)

                if let msg = saveMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding()
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        Form {
            Section {
                LabeledContent("Version", value: AppVersion.current)
                LabeledContent("Build", value: AppVersion.build)
                LabeledContent("Config", value: ConfigLoader.configFile.path)
                    .textSelection(.enabled)
            } header: {
                Text("App Info")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        switch updateStatus {
                        case .idle:
                            Text("Check if a newer version is available.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .checking:
                            Text("Checking for updates...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .upToDate(let info):
                            Text("Up to date. \(info)")
                                .font(.caption)
                                .foregroundStyle(.green)
                        case .updateAvailable(let info):
                            Text("Update available: \(info)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        case .updating(let step):
                            Text(step)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .done:
                            Text("Updated! Restart the app to use the new version.")
                                .font(.caption)
                                .foregroundStyle(.green)
                        case .error(let msg):
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.red)
                        case .noRepo:
                            Text("Source directory not found. Update manually by running:\ngit pull && make install")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if case .checking = updateStatus {
                        ProgressView().controlSize(.small)
                    } else if case .updating = updateStatus {
                        ProgressView().controlSize(.small)
                    }
                }

                HStack {
                    Button("Check for Updates") {
                        checkForUpdates()
                    }
                    .disabled(updateStatus.isBusy)

                    if case .updateAvailable = updateStatus {
                        Button("Install Update") {
                            installUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private func loadFromConfig() {
        let config = viewModel.config ?? .empty
        url = config.homeAssistantURL
        token = config.token
        historyHours = config.historyHours
        refreshInterval = config.refreshIntervalSeconds
        fullRefreshInterval = config.fullRefreshIntervalSeconds
        categories = config.categories.isEmpty ? AppConfig.defaultCategories : config.categories
    }

    private func save() {
        let config = AppConfig(
            homeAssistantURL: url,
            token: token,
            refreshIntervalSeconds: refreshInterval,
            fullRefreshIntervalSeconds: fullRefreshInterval,
            historyHours: historyHours,
            categories: categories
        )

        do {
            try ConfigLoader.save(config)
            saveMessage = "Saved"
            viewModel.stopMonitoring()
            viewModel.loadConfig()
            viewModel.startMonitoring()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveMessage = nil }
        } catch {
            saveMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                let testURL = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard let apiURL = URL(string: "\(testURL)/api/") else {
                    testResult = "Invalid URL"
                    isTesting = false
                    return
                }
                var request = URLRequest(url: apiURL)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 10

                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    testResult = "OK \u{2014} Connected"
                } else {
                    testResult = "Error: Bad response"
                }
            } catch {
                testResult = "Error: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }

    // MARK: - Update

    private func checkForUpdates() {
        guard let path = AppVersion.projectPath else {
            updateStatus = .noRepo
            return
        }

        updateStatus = .checking
        Task.detached {
            do {
                let gitRoot = try shellOutput("git -C \(path.shellEscaped) rev-parse --show-toplevel")
                let _ = try shellOutput("git -C \(gitRoot.shellEscaped) fetch origin 2>&1")
                let local = try shellOutput("git -C \(gitRoot.shellEscaped) rev-parse HEAD")
                let remote = try shellOutput("git -C \(gitRoot.shellEscaped) rev-parse @{u}")
                let behind = try shellOutput("git -C \(gitRoot.shellEscaped) rev-list --count HEAD..@{u}")
                let commitCount = Int(behind.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

                await MainActor.run {
                    if local.prefix(8) == remote.prefix(8) {
                        updateStatus = .upToDate("Commit: \(local.prefix(8))")
                    } else {
                        updateStatus = .updateAvailable("\(commitCount) new commit\(commitCount == 1 ? "" : "s")")
                    }
                }
            } catch {
                await MainActor.run {
                    updateStatus = .error("Git error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func installUpdate() {
        guard let path = AppVersion.projectPath else {
            updateStatus = .noRepo
            return
        }

        updateStatus = .updating("Pulling latest changes...")
        Task.detached {
            do {
                let gitRoot = try shellOutput("git -C \(path.shellEscaped) rev-parse --show-toplevel")
                let _ = try shellOutput("git -C \(gitRoot.shellEscaped) pull origin 2>&1")

                await MainActor.run { updateStatus = .updating("Building...") }
                let _ = try shellOutput("cd \(path.shellEscaped) && swift build -c release 2>&1")

                await MainActor.run { updateStatus = .updating("Installing...") }
                let _ = try shellOutput("cd \(path.shellEscaped) && make install 2>&1")

                await MainActor.run { updateStatus = .done }
            } catch {
                await MainActor.run {
                    updateStatus = .error("Update failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Category Editor

private struct CategoryEditorView: View {
    @Binding var category: SensorCategory
    let onDelete: () -> Void
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach($category.sensors) { $sensor in
                        SensorEditorRow(sensor: $sensor) {
                            category.sensors.removeAll { $0.key == sensor.key }
                        }
                        .padding(.leading, 8)
                    }

                    ForEach($category.subcategories) { $sub in
                        SubcategoryEditorView(subcategory: $sub) {
                            category.subcategories.removeAll { $0.id == sub.id }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            let newId = "sub-\(UUID().uuidString.prefix(8).lowercased())"
                            category.subcategories.append(SensorSubcategory(
                                id: newId, name: "New Room", icon: "house", sensors: []
                            ))
                        } label: {
                            Label("Add Subcategory", systemImage: "folder.badge.plus")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)

                        Button {
                            let newKey = "sensor-\(UUID().uuidString.prefix(8).lowercased())"
                            category.sensors.append(SensorConfig(
                                key: newKey, entityId: "", name: "New Sensor", unit: "",
                                icon: "sensor", color: "blue"
                            ))
                        } label: {
                            Label("Add Sensor", systemImage: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.leading, 8)
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            } label: {
                HStack {
                    IconPickerButton(selectedIcon: $category.icon)

                    TextField("Category Name", text: $category.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.headline, design: .rounded))

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete category")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        }
    }
}

// MARK: - Subcategory Editor

private struct SubcategoryEditorView: View {
    @Binding var subcategory: SensorSubcategory
    let onDelete: () -> Void
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach($subcategory.sensors) { $sensor in
                    SensorEditorRow(sensor: $sensor) {
                        subcategory.sensors.removeAll { $0.key == sensor.key }
                    }
                    .padding(.leading, 8)
                }

                Button {
                    let newKey = "sensor-\(UUID().uuidString.prefix(8).lowercased())"
                    subcategory.sensors.append(SensorConfig(
                        key: newKey, entityId: "", name: "New Sensor", unit: "",
                        icon: "sensor", color: "blue"
                    ))
                } label: {
                    Label("Add Sensor", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 8)
            }
        } label: {
            HStack {
                IconPickerButton(selectedIcon: $subcategory.icon)

                TextField("Subcategory Name", text: $subcategory.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.subheadline, design: .rounded))

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.3)))
    }
}

// MARK: - Sensor Editor Row

private struct SensorEditorRow: View {
    @Binding var sensor: SensorConfig
    let onDelete: () -> Void
    @State private var isExpanded = false

    private let colorOptions = ["orange", "cyan", "green", "purple", "blue", "red", "yellow", "pink"]

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    TextField("Name", text: $sensor.name)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
                HStack {
                    Text("Entity ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    TextField("sensor.xxx", text: $sensor.entityId)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
                HStack {
                    Text("Unit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    TextField("Unit", text: $sensor.unit)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 80)

                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $sensor.color) {
                        ForEach(colorOptions, id: \.self) { color in
                            HStack {
                                Circle()
                                    .fill(colorForName(color))
                                    .frame(width: 10, height: 10)
                                Text(color.capitalized)
                            }
                            .tag(color)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 100)
                }
                HStack {
                    Text("Thresholds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    TextField("Min", value: $sensor.thresholdMin, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 60)
                    Text("\u{2013}")
                    TextField("Max", value: $sensor.thresholdMax, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 60)
                    Text(sensor.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 4)
            .padding(.bottom, 4)
        } label: {
            HStack(spacing: 8) {
                IconPickerButton(selectedIcon: $sensor.icon)

                Text(sensor.name)
                    .font(.system(.callout, design: .rounded))

                if !sensor.entityId.isEmpty {
                    Text(sensor.entityId)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "orange": return .orange
        case "cyan": return .cyan
        case "green": return .green
        case "purple": return .purple
        case "blue": return .blue
        case "red": return .red
        case "yellow": return .yellow
        case "pink": return .pink
        default: return .accentColor
        }
    }
}

// MARK: - Icon Picker

private struct IconPickerButton: View {
    @Binding var selectedIcon: String
    @State private var showPicker = false
    @State private var searchText = ""

    var body: some View {
        Button {
            showPicker = true
        } label: {
            Image(systemName: validIconName)
                .imageScale(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
        }
        .buttonStyle(.plain)
        .help("Change icon (\(selectedIcon))")
        .popover(isPresented: $showPicker) {
            iconPickerContent
        }
    }

    /// Fall back to a known icon if the name is empty or invalid
    private var validIconName: String {
        selectedIcon.isEmpty ? "questionmark.square.dashed" : selectedIcon
    }

    private var iconPickerContent: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search icons...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(filteredIcons, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)

                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 8), spacing: 4) {
                                ForEach(group.icons, id: \.name) { icon in
                                    Button {
                                        selectedIcon = icon.name
                                        showPicker = false
                                    } label: {
                                        Image(systemName: icon.name)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 28, height: 28)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(selectedIcon == icon.name
                                                          ? Color.accentColor.opacity(0.3)
                                                          : Color.clear)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help(icon.label)
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }

        }
        .frame(width: 300, height: 340)
    }

    private var filteredIcons: [(category: String, icons: [(name: String, label: String)])] {
        if searchText.isEmpty {
            return Self.suggestedIcons
        }
        let query = searchText.lowercased()
        return Self.suggestedIcons.compactMap { group in
            let filtered = group.icons.filter {
                $0.name.lowercased().contains(query) || $0.label.lowercased().contains(query)
            }
            return filtered.isEmpty ? nil : (group.category, filtered)
        }
    }

    static let suggestedIcons: [(category: String, icons: [(name: String, label: String)])] = [
        ("Climate", [
            ("thermometer.medium", "Thermometer"),
            ("thermometer.sun", "Thermometer Sun"),
            ("thermometer.snowflake", "Thermometer Cold"),
            ("humidity", "Humidity"),
            ("drop", "Drop"),
            ("wind", "Wind"),
            ("cloud", "Cloud"),
            ("cloud.rain", "Cloud Rain"),
            ("cloud.sun", "Cloud Sun"),
            ("sun.max", "Sun"),
            ("snowflake", "Snowflake"),
        ]),
        ("Air Quality", [
            ("aqi.medium", "AQI"),
            ("aqi.low", "AQI Low"),
            ("aqi.high", "AQI High"),
            ("smoke", "Smoke/PM"),
            ("leaf", "Leaf"),
            ("carbon.dioxide.cloud", "CO2"),
            ("gauge.with.dots.needle.bottom.50percent", "Gauge"),
            ("fan", "Fan"),
        ]),
        ("Energy", [
            ("bolt", "Bolt"),
            ("bolt.circle", "Bolt Circle"),
            ("powerplug", "Plug"),
            ("battery.100percent", "Battery"),
            ("battery.100percent.bolt", "Battery Charging"),
            ("flame", "Flame"),
            ("lightbulb", "Lightbulb"),
            ("lightbulb.led", "LED"),
        ]),
        ("Rooms", [
            ("house", "House"),
            ("door.left.hand.open", "Door Open"),
            ("door.left.hand.closed", "Door Closed"),
            ("bed.double", "Bed Double"),
            ("sofa", "Sofa"),
            ("bathtub", "Bath"),
            ("oven", "Kitchen"),
            ("lamp.desk", "Lamp"),
            ("chair.lounge", "Chair"),
            ("building.2", "Building"),
        ]),
        ("Sensors", [
            ("sensor", "Sensor"),
            ("waveform.path.ecg", "Activity"),
            ("antenna.radiowaves.left.and.right", "Signal"),
            ("wifi", "WiFi"),
            ("dot.radiowaves.left.and.right", "Radio"),
            ("eye", "Eye"),
            ("camera", "Camera"),
            ("speedometer", "Speed"),
        ]),
        ("Security", [
            ("lock", "Lock"),
            ("lock.open", "Unlock"),
            ("shield", "Shield"),
            ("bell", "Bell"),
            ("light.beacon.max", "Siren"),
            ("key", "Key"),
        ]),
        ("General", [
            ("circle", "Circle"),
            ("square", "Square"),
            ("triangle", "Triangle"),
            ("star", "Star"),
            ("heart", "Heart"),
            ("info.circle", "Info"),
            ("exclamationmark.triangle", "Alert"),
            ("checkmark.circle", "Check"),
            ("gearshape", "Settings"),
            ("cpu", "CPU"),
            ("externaldrive", "Drive"),
            ("server.rack", "Server"),
            ("chart.xyaxis.line", "Chart"),
            ("folder", "Folder"),
        ]),
    ]
}

// MARK: - Update Status

enum UpdateStatus {
    case idle
    case checking
    case upToDate(String)
    case updateAvailable(String)
    case updating(String)
    case done
    case error(String)
    case noRepo

    var isBusy: Bool {
        switch self {
        case .checking, .updating: return true
        default: return false
        }
    }
}

// MARK: - Shell Helper

private func shellOutput(_ command: String) throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if process.terminationStatus != 0 {
        throw NSError(domain: "ShellError", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: output])
    }
    return output
}

private extension String {
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
