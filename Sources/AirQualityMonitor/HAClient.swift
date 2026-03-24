import Foundation

actor HAClient {
    private let baseURL: String
    private let token: String
    private let session: URLSession

    init(baseURL: String, token: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token
        self.session = URLSession.shared
    }

    func fetchHistory(entityIds: [String], hours: Int) async throws -> [String: [SensorReading]] {
        let startTime = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(hours) * 3600))
        let entityFilter = entityIds.joined(separator: ",")
        let urlString = "\(baseURL)/api/history/period/\(startTime)?filter_entity_id=\(entityFilter)&significant_changes_only=0&no_attributes"

        guard let url = URL(string: urlString) else {
            throw HAError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HAError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw HAError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder.homeAssistant
        let history = try decoder.decode([[HAStateEntry]].self, from: data)

        var result: [String: [SensorReading]] = [:]
        for entityHistory in history {
            guard let entityId = entityHistory.first?.entityId else { continue }
            let readings = entityHistory.compactMap { entry -> SensorReading? in
                guard let value = Double(entry.state) else { return nil }
                return SensorReading(date: entry.lastChanged, value: value)
            }
            result[entityId] = readings
        }

        return result
    }

    func fetchCurrentState(entityId: String) async throws -> SensorReading? {
        let urlString = "\(baseURL)/api/states/\(entityId)"
        guard let url = URL(string: urlString) else {
            throw HAError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HAError.invalidResponse
        }

        let decoder = JSONDecoder.homeAssistant
        let entry = try decoder.decode(HAStateEntry.self, from: data)

        guard let value = Double(entry.state) else { return nil }
        return SensorReading(date: entry.lastChanged, value: value)
    }
    func fetchStringState(entityId: String) async throws -> String? {
        let urlString = "\(baseURL)/api/states/\(entityId)"
        guard let url = URL(string: urlString) else {
            throw HAError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HAError.invalidResponse
        }

        let decoder = JSONDecoder.homeAssistant
        let entry = try decoder.decode(HAStateEntry.self, from: data)

        let state = entry.state.lowercased()
        if state == "unavailable" || state == "unknown" { return nil }
        return entry.state
    }
}

enum HAError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Home Assistant URL"
        case .invalidResponse: return "Invalid response from Home Assistant"
        case .httpError(let code): return "HTTP error \(code) from Home Assistant"
        }
    }
}
