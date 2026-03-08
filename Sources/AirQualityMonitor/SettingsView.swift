import SwiftUI

struct SettingsView: View {
    var viewModel: SensorViewModel

    @State private var url: String = ""
    @State private var token: String = ""
    @State private var historyHours: Int = 12
    @State private var refreshInterval: Int = 30
    @State private var fullRefreshInterval: Int = 900
    @State private var sensors: [SensorConfig] = []
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
        .frame(width: 520, height: 420)
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
        Form {
            ForEach($sensors) { $sensor in
                Section {
                    HStack {
                        TextField("Entity ID", text: $sensor.entityId)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        TextField("Min", value: $sensor.thresholdMin, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("\u{2013}")
                        TextField("Max", value: $sensor.thresholdMax, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text(sensor.unit)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label(sensor.name, systemImage: sensor.icon)
                }
            }

            HStack {
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
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
        sensors = config.sensors.isEmpty ? AppConfig.defaultSensors : config.sensors
    }

    private func save() {
        let config = AppConfig(
            homeAssistantURL: url,
            token: token,
            refreshIntervalSeconds: refreshInterval,
            fullRefreshIntervalSeconds: fullRefreshInterval,
            historyHours: historyHours,
            sensors: sensors
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
                // Find the git root (might be a parent directory)
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
