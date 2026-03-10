import SwiftUI

@main
struct AirQualityMonitorApp: App {
    @State private var viewModel = SensorViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if viewModel.hasConfig {
                    ContentView(viewModel: viewModel)
                } else if viewModel.configLoaded {
                    SetupPromptView(viewModel: viewModel)
                } else {
                    ProgressView()
                        .frame(width: 400, height: 200)
                }
            }
            .onAppear {
                viewModel.loadConfig()
                viewModel.startMonitoring()
            }
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings {
            SettingsView(viewModel: viewModel)
        }

        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

struct SetupPromptView: View {
    let viewModel: SensorViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gear.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Configuration Required")
                .font(.system(.title2, design: .rounded, weight: .semibold))

            Text("Open Settings to configure your\nHome Assistant connection.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            SettingsLink {
                Text("Open Settings")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("or press \u{2318},")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(width: 400, height: 280)
    }
}
