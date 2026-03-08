import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: SensorViewModel
    @State private var expandedSensor: String?
    @Namespace private var chartNamespace

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            GeometryReader { geo in
                chartLayout(in: geo.size)
                    .padding()
            }
        }
        .frame(minWidth: 900, minHeight: 550)
        .background {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .containerBackground(.clear, for: .window)
    }

    private var toolbar: some View {
        HStack {
            if expandedSensor != nil {
                Button {
                    withAnimation(.spring(duration: 0.35)) { expandedSensor = nil }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("All Sensors")
                    }
                }
                .buttonStyle(.borderless)
            }

            Text("Air Quality Monitor")
                .font(.system(.title3, design: .rounded, weight: .semibold))

            Spacer()

            if let error = viewModel.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if let updated = viewModel.lastUpdated {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.fetchFullHistory() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh all data")

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func chartLayout(in size: CGSize) -> some View {
        if let expandedKey = expandedSensor,
           let sensor = viewModel.sensorConfigs.first(where: { $0.key == expandedKey }) {
            // Expanded: single chart fills the space
            SensorChartView(
                sensor: sensor,
                readings: viewModel.readings[sensor.entityId] ?? [],
                isExpanded: true
            )
            .matchedGeometryEffect(id: sensor.key, in: chartNamespace)
            .onTapGesture {
                withAnimation(.spring(duration: 0.35)) { expandedSensor = nil }
            }
            .transition(.opacity)
        } else {
            // Grid: 2x2 filling available space
            // size already excludes the outer padding (from .padding() on GeometryReader content)
            // but we need to account for the padding modifier applied after GeometryReader
            let padding: CGFloat = 16 // the .padding() around chartLayout
            let spacing: CGFloat = 16
            let availableWidth = size.width - padding * 2
            let availableHeight = size.height - padding * 2
            let cellWidth = (availableWidth - spacing) / 2
            let cellHeight = (availableHeight - spacing) / 2

            let columns = [
                GridItem(.fixed(cellWidth), spacing: spacing),
                GridItem(.fixed(cellWidth), spacing: spacing)
            ]

            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(viewModel.sensorConfigs) { sensor in
                    SensorChartView(
                        sensor: sensor,
                        readings: viewModel.readings[sensor.entityId] ?? [],
                        isExpanded: false
                    )
                    .matchedGeometryEffect(id: sensor.key, in: chartNamespace)
                    .frame(height: cellHeight)
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.35)) {
                            expandedSensor = sensor.key
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
            .transition(.opacity)
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
