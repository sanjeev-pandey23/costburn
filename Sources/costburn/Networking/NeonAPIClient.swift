import Foundation

struct NeonAPIClient: Sendable {
    private static let base = "https://console.neon.tech/api/v2"

    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let formatter = NeonAPIClient.makeISOFormatter()
            guard let date = formatter.date(from: s) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Cannot decode date: \(s)"
                ))
            }
            return date
        }
        return d
    }

    // MARK: - Org consumption: per-project breakdown

    func fetchProjectConsumption(
        apiKey: String,
        organizationID: String,
        from: Date,
        to: Date,
        granularity: String
    ) async throws -> [RawProjectConsumption] {
        let formatter = Self.makeISOFormatter()
        var components = URLComponents(string: "\(Self.base)/consumption_history/projects")!
        components.queryItems = [
            .init(name: "from", value: formatter.string(from: from)),
            .init(name: "to", value: formatter.string(from: to)),
            .init(name: "granularity", value: granularity),
            .init(name: "organization_id", value: organizationID),
        ]
        let metricNames = [
            "compute_unit_seconds",
            "root_branch_bytes_month",
            "child_branch_bytes_month",
            "public_network_transfer_bytes",
        ]
        for m in metricNames {
            components.queryItems?.append(.init(name: "metrics[]", value: m))
        }

        let response = try await get(
            url: components.url!,
            apiKey: apiKey,
            as: ConsumptionHistoryResponse.self
        )
        return response.projects
    }

    // MARK: - Account consumption: for personal (non-org) accounts

    func fetchAccountConsumption(
        apiKey: String,
        from: Date,
        to: Date,
        granularity: String
    ) async throws -> RawAccountConsumption {
        let formatter = Self.makeISOFormatter()
        var components = URLComponents(string: "\(Self.base)/consumption_history/account")!
        components.queryItems = [
            .init(name: "from", value: formatter.string(from: from)),
            .init(name: "to", value: formatter.string(from: to)),
            .init(name: "granularity", value: granularity),
        ]
        let metricNames = [
            "compute_unit_seconds",
            "root_branch_bytes_month",
            "child_branch_bytes_month",
            "public_network_transfer_bytes",
        ]
        for m in metricNames {
            components.queryItems?.append(.init(name: "metrics[]", value: m))
        }

        let response = try await get(
            url: components.url!,
            apiKey: apiKey,
            as: AccountConsumptionResponse.self
        )
        return RawAccountConsumption(periods: response.periods)
    }

    // MARK: - Project names: GET /api/v2/projects

    func fetchProjectNames(apiKey: String) async throws -> [String: String] {
        let url = URL(string: "\(Self.base)/projects")!
        let response = try await get(url: url, apiKey: apiKey, as: ProjectsListResponse.self)
        return Dictionary(uniqueKeysWithValues: response.projects.map { ($0.id, $0.name) })
    }

    // MARK: - Generic GET

    private func get<T: Decodable>(
        url: URL,
        apiKey: String,
        as type: T.Type
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, body)
        }

        return try Self.makeDecoder().decode(T.self, from: data)
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .http(let code, let body):
            let hint = body.isEmpty ? "" : ": \(body.prefix(120))"
            return "HTTP \(code)\(hint)"
        }
    }
}
