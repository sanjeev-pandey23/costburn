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

    // Copilot
    var copilotUsage: CopilotUsageSummary? = nil
    var copilotIsLoading = false
    var copilotError: String? = nil

    var activeTab: AppTab = .neon

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
        case .copilot:
            if copilotIsLoading && copilotUsage == nil { return "-- cr" }
            let cr = copilotUsage?.totalCredits ?? 0
            if let fraction = copilotUsage?.creditAllowanceFraction {
                let pct = Int((fraction * 100).rounded())
                // return "\(cr) cr (\(pct)%)"
                return "\(pct)% cr" // Simplified for status bar to save space
            }
            return "\(cr) cr"
        }
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    // MARK: - Private

    private let copilotReader = CopilotSessionReader()

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
            await refreshCopilot()
            while !Task.isCancelled {
                let interval = Preferences.shared.refreshInterval
                try? await Task.sleep(for: .seconds(interval))
                if !Task.isCancelled {
                    await refresh()
                    await refreshCopilot()
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

    // MARK: - Copilot

    func refreshCopilot() async {
        copilotIsLoading = true
        copilotError = nil

        let records = await copilotReader.readSessions(since: selectedPeriod.startDate)

        guard !Task.isCancelled else { return }

        // Aggregate
        var totalCredits = 0
        var totalTurns = 0
        var modelMap: [String: (requestCount: Int, creditCost: Int, inputTokens: Int, outputTokens: Int, cacheReadTokens: Int)] = [:]

        for record in records {
            totalCredits += record.credits
            totalTurns += record.turnCount
            for (model, usage) in record.modelBreakdown {
                var agg = modelMap[model] ?? (0, 0, 0, 0, 0)
                agg.requestCount += usage.requestCount
                agg.creditCost += usage.creditCost
                agg.inputTokens += usage.inputTokens
                agg.outputTokens += usage.outputTokens
                agg.cacheReadTokens += usage.cacheReadTokens
                modelMap[model] = agg
            }
        }

        let sortedBreakdown: [(model: String, usage: CopilotModelUsage)] = modelMap
            .map { (model, agg) in
                (model, CopilotModelUsage(
                    requestCount: agg.requestCount,
                    creditCost: agg.creditCost,
                    inputTokens: agg.inputTokens,
                    outputTokens: agg.outputTokens,
                    cacheReadTokens: agg.cacheReadTokens
                ))
            }
            .sorted { $0.usage.creditCost > $1.usage.creditCost }

        let estimatedCost = Double(totalCredits) * 0.01
        var summary = CopilotUsageSummary(
            totalCredits: totalCredits,
            estimatedCost: estimatedCost,
            sessionCount: records.count,
            turnCount: totalTurns,
            modelBreakdown: sortedBreakdown
        )

        // Apply configured allowance / limit
        if let allowance = Preferences.shared.resolvedCreditAllowance, allowance > 0 {
            summary.creditAllowanceFraction = Double(totalCredits) / Double(allowance)
            summary.creditsRemaining = max(allowance - totalCredits, 0)
        }
        if let limit = Preferences.shared.copilotSpendLimit, limit > 0 {
            summary.spendLimitFraction = estimatedCost / limit
            summary.dollarRemaining = max(limit - estimatedCost, 0)
        }

        copilotUsage = summary
        copilotIsLoading = false
    }
}

// MARK: - AppTab

enum AppTab: String, CaseIterable {
    case neon = "Neon DB"
    case copilot = "Copilot"
}
