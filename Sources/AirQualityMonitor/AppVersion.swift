import Foundation

enum AppVersion {
    static let current = "1.0.0"
    static let build = "1"

    static var formatted: String { "v\(current) (\(build))" }

    static var projectPath: String? {
        // Walk up from the executable to find the project root (contains Package.swift)
        var url = URL(fileURLWithPath: Bundle.main.executablePath ?? "")
        for _ in 0..<10 {
            url = url.deletingLastPathComponent()
            let packageFile = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageFile.path) {
                return url.path
            }
        }
        // Fallback: check if the source directory exists at a known location
        let knownPaths = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Dev/Projects/smart-home-setup/AirQualityMonitor").path
        ]
        return knownPaths.first { FileManager.default.fileExists(atPath: $0 + "/Package.swift") }
    }

    static var isGitRepo: Bool {
        guard let path = projectPath else { return false }
        return FileManager.default.fileExists(atPath: path + "/.git") ||
               FileManager.default.fileExists(atPath: (URL(fileURLWithPath: path).deletingLastPathComponent().path) + "/.git")
    }
}
