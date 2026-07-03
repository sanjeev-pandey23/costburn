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

    // AI usage
    var aiUsage: [AIUsageProvider: AIUsageSummary] = [:]
    var aiUsageIsLoading = false
    var aiUsageError: String? = nil
    var aiUsageLastUpdated: Date? = nil

    var activeTab: AppTab = .neon
    var activeAIUsageProvider: AIUsageProvider = .copilot

    // MARK: - Computed

    var totalEstimatedCost: Double {
        projects.isEmpty
            ? (accountSummary?.estimatedCost ?? 0)
            : projects.reduce(0) { $0 + $1.estimatedCost }
    }

    var statusBarTitle: String {
        switch activeTab {
        case .neon:
            guard !isLoading || !projects.isEmpty || accountSummary != nil else {
                return "$--.--"
            }
            let cost = totalEstimatedCost
            guard cost > 0 || lastUpdated != nil else { return "$--.--" }
            if cost >= 100 {
                return String(format: "$%.0f", cost)
            }
            return String(format: "$%.2f", cost)
        case .aiUsage:
            let provider = activeAIUsageProvider
            if aiUsageIsLoading && aiUsage[provider] == nil {
                return provider.usesCredits ? "-- cr" : "$--.--"
            }
            guard let summary = aiUsage[provider] else {
                return provider.usesCredits ? "0 cr" : "$--.--"
            }
            if provider.usesCredits {
                if let fraction = summary.creditAllowanceFraction {
                    let pct = Int((fraction * 100).rounded())
                    return "\(pct)% cr"
                }
                return "\(summary.totalCredits) cr"
            }
            return formatStatusCost(summary.estimatedCost)
        }
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    // MARK: - Private

    private let copilotReader = CopilotSessionReader()
    private let claudeReader = ClaudeSessionReader()
    private let codexReader = CodexSessionReader()

    // API key cached in memory — Keychain is only read once at init and after
    // credentials are explicitly saved in Settings, avoiding repeated OS prompts.
    private(set) var apiKey: String = ""
    private let apiClient = NeonAPIClient()
    private var pollingTask: Task<Void, Never>?

    init() {
        apiKey = KeychainHelper.shared.load(key: KeychainHelper.apiKeyTag) ?? ""
    }

    /// Call after saving new credentials in Settings to refresh the in-memory cache.
    func reloadCredentials() {
        apiKey = KeychainHelper.shared.load(key: KeychainHelper.apiKeyTag) ?? ""
    }

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
            await refreshAIUsage()
            while !Task.isCancelled {
                let interval = Preferences.shared.refreshInterval
                try? await Task.sleep(for: .seconds(interval))
                if !Task.isCancelled {
                    await refresh()
                    await refreshAIUsage()
                }
            }
        }
    }

    func refresh() async {
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

    // MARK: - AI usage

    func refreshAIUsage() async {
        aiUsageIsLoading = true
        aiUsageError = nil

        async let copilotRecords = copilotReader.readSessions(since: selectedPeriod.startDate)
        async let claudeRecords = claudeReader.readSessions(since: selectedPeriod.startDate)
        async let codexRecords = codexReader.readSessions(since: selectedPeriod.startDate)

        let recordsByProvider: [AIUsageProvider: [AIUsageSessionRecord]] = await [
            .copilot: copilotRecords,
            .claude: claudeRecords,
            .codex: codexRecords
        ]

        guard !Task.isCancelled else {
            aiUsageIsLoading = false
            return
        }

        aiUsage = Dictionary(
            uniqueKeysWithValues: AIUsageProvider.allCases.map { provider in
                (
                    provider,
                    AIUsageAggregator.summary(
                        provider: provider,
                        records: recordsByProvider[provider] ?? [],
                        creditAllowance: provider == .copilot ? Preferences.shared.resolvedCreditAllowance : nil,
                        spendLimit: Preferences.shared.aiSpendLimit(for: provider)
                    )
                )
            }
        )
        aiUsageLastUpdated = Date()
        aiUsageIsLoading = false
    }

    func refreshCopilot() async {
        await refreshAIUsage()
    }

    func aiUsageSummary(for provider: AIUsageProvider) -> AIUsageSummary? {
        aiUsage[provider]
    }

    private func formatStatusCost(_ value: Double) -> String {
        guard value > 0 else { return "$0.00" }
        if value >= 100 {
            return String(format: "$%.0f", value)
        }
        return String(format: "$%.2f", value)
    }
}

// MARK: - AppTab

enum AppTab: String, CaseIterable {
    case neon = "Neon DB"
    case aiUsage = "AI Usage"
}
