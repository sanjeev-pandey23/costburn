import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    // MARK: - Published state

    var projects: [ProjectConsumption] = []
    var accountSummary: AccountSummary? = nil
    var isLoading = false
    var lastError: String? = nil
    var lastUpdated: Date? = nil
    var selectedPeriod: Period = .month

    // MARK: - Computed

    var totalEstimatedCost: Double {
        projects.isEmpty
            ? (accountSummary?.estimatedCost ?? 0)
            : projects.reduce(0) { $0 + $1.estimatedCost }
    }

    var statusBarTitle: String {
        guard !isLoading || !projects.isEmpty || accountSummary != nil else {
            return "$--.--"
        }
        let cost = totalEstimatedCost
        guard cost > 0 || lastUpdated != nil else { return "$--.--" }
        if cost >= 100 {
            return String(format: "$%.0f", cost)
        }
        return String(format: "$%.2f", cost)
    }

    var isConfigured: Bool {
        !(KeychainHelper.shared.load(key: KeychainHelper.apiKeyTag) ?? "").isEmpty
    }

    // MARK: - Private

    private let apiClient = NeonAPIClient()
    private var pollingTask: Task<Void, Never>?

    // MARK: - Period

    enum Period: String, CaseIterable, Identifiable {
        case today = "Today"
        case sevenDays = "7d"
        case month = "Month"

        var id: String { rawValue }

        var startDate: Date {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .today:
                return cal.startOfDay(for: now)
            case .sevenDays:
                return cal.date(byAdding: .day, value: -7, to: now)!
            case .month:
                return cal.date(from: cal.dateComponents([.year, .month], from: now))!
            }
        }

        var granularity: String {
            switch self {
            case .today: return "hourly"
            case .sevenDays, .month: return "daily"
            }
        }
    }

    // MARK: - Polling

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            await refresh()
            while !Task.isCancelled {
                let interval = Preferences.shared.refreshInterval
                try? await Task.sleep(for: .seconds(interval))
                if !Task.isCancelled {
                    await refresh()
                }
            }
        }
    }

    func refresh() async {
        let apiKey = KeychainHelper.shared.load(key: KeychainHelper.apiKeyTag) ?? ""
        guard !apiKey.isEmpty else { return }

        isLoading = true
        lastError = nil

        let orgID = Preferences.shared.organizationID
        let from = selectedPeriod.startDate
        let to = Date()
        let granularity = selectedPeriod.granularity
        let calculator = CostCalculator(
            tier: Preferences.shared.pricingTier,
            customRates: Preferences.shared.customRates
        )

        do {
            if !orgID.isEmpty {
                do {
                    // Scale+ plan: full consumption history with org breakdown
                    let raw = try await apiClient.fetchProjectConsumption(
                        apiKey: apiKey,
                        organizationID: orgID,
                        from: from,
                        to: to,
                        granularity: granularity
                    )
                    let nameMap = try await apiClient.fetchProjects(apiKey: apiKey)
                        .reduce(into: [String: String]()) { $0[$1.id] = $1.name }
                    projects = raw.map { calculator.buildProjectConsumption($0, nameMap: nameMap) }
                    accountSummary = nil
                } catch let err as APIError where err.isForbidden {
                    // Launch plan: fall back to GET /api/v2/projects (current period only)
                    let neonProjects = try await apiClient.fetchProjects(apiKey: apiKey)
                    projects = neonProjects.map { calculator.buildProjectConsumptionFromProject($0) }
                    accountSummary = nil
                }
            } else {
                // Personal account: account-level totals
                let raw = try await apiClient.fetchAccountConsumption(
                    apiKey: apiKey,
                    from: from,
                    to: to,
                    granularity: granularity
                )
                accountSummary = calculator.buildAccountSummary(raw)
                projects = []
            }
            lastUpdated = Date()
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }
}
