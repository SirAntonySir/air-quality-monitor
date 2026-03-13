// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirQualityMonitor",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "AirQualityMonitor",
            path: "Sources/AirQualityMonitor"
        )
    ]
)
