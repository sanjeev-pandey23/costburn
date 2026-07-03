import Foundation

enum AIUsageProvider: String, CaseIterable, Identifiable, Sendable {
    case copilot = "Copilot"
    case claude = "Claude"
    case codex = "Codex"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .copilot: return "bolt.horizontal.circle"
        case .claude: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var usesCredits: Bool {
        self == .copilot
    }

    var emptyTitle: String {
        switch self {
        case .copilot: return "No Copilot sessions found"
        case .claude: return "No Claude sessions found"
        case .codex: return "No Codex sessions found"
        }
    }

    var emptyMessage: String {
        switch self {
        case .copilot:
            return "Sessions from this billing month will appear here automatically. Configure your plan in Settings to set a credit allowance."
        case .claude:
            return "Claude Code transcripts from this billing period will appear here automatically."
        case .codex:
            return "Codex session logs from this billing period will appear here automatically."
        }
    }
}

struct AIModelUsage: Sendable {
    let requestCount: Int
    let creditCost: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheCreationFiveMinuteTokens: Int
    let cacheCreationOneHourTokens: Int
    let cacheReadTokens: Int
    let reasoningTokens: Int
    let estimatedCost: Double

    init(
        requestCount: Int,
        creditCost: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheCreationFiveMinuteTokens: Int = 0,
        cacheCreationOneHourTokens: Int = 0,
        cacheReadTokens: Int = 0,
        reasoningTokens: Int = 0,
        estimatedCost: Double = 0
    ) {
        self.requestCount = requestCount
        self.creditCost = creditCost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheCreationFiveMinuteTokens = cacheCreationFiveMinuteTokens
        self.cacheCreationOneHourTokens = cacheCreationOneHourTokens
        self.cacheReadTokens = cacheReadTokens
        self.reasoningTokens = reasoningTokens
        self.estimatedCost = estimatedCost
    }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}

struct AIUsageSessionRecord: Sendable {
    enum Source: String, Sendable {
        case copilotCLI = "CLI"
        case copilotVSCode = "VS Code"
        case copilotJetBrains = "JetBrains"
        case claudeCode = "Claude Code"
        case codexCLI = "Codex CLI"
    }

    let sessionId: String
    let startTime: Date
    let provider: AIUsageProvider
    let source: Source
    let credits: Int
    let turnCount: Int
    let modelBreakdown: [String: AIModelUsage]
    let estimatedCost: Double
}

struct AIUsageSummary: Sendable {
    let provider: AIUsageProvider
    let totalCredits: Int
    let estimatedCost: Double
    let sessionCount: Int
    let turnCount: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let reasoningTokens: Int
    let modelBreakdown: [(model: String, usage: AIModelUsage)]

    var creditAllowanceFraction: Double?
    var creditsRemaining: Int?
    var spendLimitFraction: Double?
    var dollarRemaining: Double?

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var overCreditAllowance: Bool {
        creditAllowanceFraction.map { $0 >= 1.0 } ?? false
    }

    var overSpendLimit: Bool {
        spendLimitFraction.map { $0 >= 1.0 } ?? false
    }
}

struct AITokenRates: Sendable {
    let inputPerMillion: Double
    let cachedInputPerMillion: Double
    let cacheWriteFiveMinutePerMillion: Double
    let cacheWriteOneHourPerMillion: Double
    let outputPerMillion: Double

    func cost(
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationFiveMinuteTokens: Int = 0,
        cacheCreationOneHourTokens: Int = 0,
        cacheReadTokens: Int = 0
    ) -> Double {
        let million = 1_000_000.0
        return (Double(inputTokens) / million * inputPerMillion)
            + (Double(cacheReadTokens) / million * cachedInputPerMillion)
            + (Double(cacheCreationFiveMinuteTokens) / million * cacheWriteFiveMinutePerMillion)
            + (Double(cacheCreationOneHourTokens) / million * cacheWriteOneHourPerMillion)
            + (Double(outputTokens) / million * outputPerMillion)
    }
}

enum AIUsagePricing {
    static func rates(for provider: AIUsageProvider, model: String, now: Date = Date()) -> AITokenRates? {
        switch provider {
        case .copilot:
            return nil
        case .claude:
            return claudeRates(for: model, now: now)
        case .codex:
            return openAIRates(for: model)
        }
    }

    static func estimatedCost(
        provider: AIUsageProvider,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationFiveMinuteTokens: Int = 0,
        cacheCreationOneHourTokens: Int = 0,
        cacheReadTokens: Int = 0,
        explicitCost: Double? = nil
    ) -> Double {
        if let explicitCost, explicitCost > 0 {
            return explicitCost
        }
        guard let rates = rates(for: provider, model: model) else {
            return 0
        }
        return rates.cost(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationFiveMinuteTokens: cacheCreationFiveMinuteTokens,
            cacheCreationOneHourTokens: cacheCreationOneHourTokens,
            cacheReadTokens: cacheReadTokens
        )
    }

    private static func claudeRates(for model: String, now: Date) -> AITokenRates {
        let normalized = model.lowercased()

        if normalized.contains("fable") || normalized.contains("mythos") {
            return AITokenRates(
                inputPerMillion: 10,
                cachedInputPerMillion: 1,
                cacheWriteFiveMinutePerMillion: 12.5,
                cacheWriteOneHourPerMillion: 20,
                outputPerMillion: 50
            )
        }

        if normalized.contains("opus-4-5")
            || normalized.contains("opus-4.5")
            || normalized.contains("opus-4-6")
            || normalized.contains("opus-4.6")
            || normalized.contains("opus-4-7")
            || normalized.contains("opus-4.7")
            || normalized.contains("opus-4-8")
            || normalized.contains("opus-4.8") {
            return AITokenRates(
                inputPerMillion: 5,
                cachedInputPerMillion: 0.5,
                cacheWriteFiveMinutePerMillion: 6.25,
                cacheWriteOneHourPerMillion: 10,
                outputPerMillion: 25
            )
        }

        if normalized.contains("haiku-4-5") || normalized.contains("haiku-4.5") {
            return AITokenRates(
                inputPerMillion: 1,
                cachedInputPerMillion: 0.1,
                cacheWriteFiveMinutePerMillion: 1.25,
                cacheWriteOneHourPerMillion: 2,
                outputPerMillion: 5
            )
        }

        if normalized.contains("sonnet-5") {
            let introCutoff = Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 9, day: 1)
            ) ?? Date.distantPast
            let input = now < introCutoff ? 2.0 : 3.0
            let output = now < introCutoff ? 10.0 : 15.0
            return AITokenRates(
                inputPerMillion: input,
                cachedInputPerMillion: input * 0.1,
                cacheWriteFiveMinutePerMillion: input * 1.25,
                cacheWriteOneHourPerMillion: input * 2,
                outputPerMillion: output
            )
        }

        return AITokenRates(
            inputPerMillion: 3,
            cachedInputPerMillion: 0.3,
            cacheWriteFiveMinutePerMillion: 3.75,
            cacheWriteOneHourPerMillion: 6,
            outputPerMillion: 15
        )
    }

    private static func openAIRates(for model: String) -> AITokenRates {
        let normalized = model.lowercased()

        if normalized.contains("gpt-5.3-codex") {
            return AITokenRates(
                inputPerMillion: 1.75,
                cachedInputPerMillion: 0.175,
                cacheWriteFiveMinutePerMillion: 1.75,
                cacheWriteOneHourPerMillion: 1.75,
                outputPerMillion: 14
            )
        }

        if normalized.contains("gpt-5.5-pro") {
            return AITokenRates(
                inputPerMillion: 15,
                cachedInputPerMillion: 15,
                cacheWriteFiveMinutePerMillion: 15,
                cacheWriteOneHourPerMillion: 15,
                outputPerMillion: 90
            )
        }

        if normalized.contains("gpt-5.5") {
            return AITokenRates(
                inputPerMillion: 5,
                cachedInputPerMillion: 0.5,
                cacheWriteFiveMinutePerMillion: 5,
                cacheWriteOneHourPerMillion: 5,
                outputPerMillion: 30
            )
        }

        if normalized.contains("gpt-5.4-mini") {
            return AITokenRates(
                inputPerMillion: 0.375,
                cachedInputPerMillion: 0.0375,
                cacheWriteFiveMinutePerMillion: 0.375,
                cacheWriteOneHourPerMillion: 0.375,
                outputPerMillion: 2.25
            )
        }

        if normalized.contains("gpt-5.4-nano") {
            return AITokenRates(
                inputPerMillion: 0.10,
                cachedInputPerMillion: 0.01,
                cacheWriteFiveMinutePerMillion: 0.10,
                cacheWriteOneHourPerMillion: 0.10,
                outputPerMillion: 0.625
            )
        }

        if normalized.contains("gpt-5.4") {
            return AITokenRates(
                inputPerMillion: 1.25,
                cachedInputPerMillion: 0.13,
                cacheWriteFiveMinutePerMillion: 1.25,
                cacheWriteOneHourPerMillion: 1.25,
                outputPerMillion: 7.5
            )
        }

        return AITokenRates(
            inputPerMillion: 1.75,
            cachedInputPerMillion: 0.175,
            cacheWriteFiveMinutePerMillion: 1.75,
            cacheWriteOneHourPerMillion: 1.75,
            outputPerMillion: 14
        )
    }
}

enum AIUsageAggregator {
    static func summary(
        provider: AIUsageProvider,
        records: [AIUsageSessionRecord],
        creditAllowance: Int?,
        spendLimit: Double?
    ) -> AIUsageSummary {
        var totalCredits = 0
        var totalTurns = 0
        var estimatedCost: Double = 0
        var modelMap: [String: AIModelUsageAccumulator] = [:]

        for record in records {
            totalCredits += record.credits
            totalTurns += record.turnCount
            estimatedCost += record.estimatedCost

            for (model, usage) in record.modelBreakdown {
                modelMap[model, default: AIModelUsageAccumulator()].add(usage)
            }
        }

        let breakdown: [(model: String, usage: AIModelUsage)] = modelMap
            .map { model, accumulator in
                (model, accumulator.usage)
            }
            .sorted {
                if $0.usage.estimatedCost == $1.usage.estimatedCost {
                    return $0.usage.creditCost > $1.usage.creditCost
                }
                return $0.usage.estimatedCost > $1.usage.estimatedCost
            }

        let inputTokens = breakdown.reduce(0) { $0 + $1.usage.inputTokens }
        let outputTokens = breakdown.reduce(0) { $0 + $1.usage.outputTokens }
        let cacheCreationTokens = breakdown.reduce(0) { $0 + $1.usage.cacheCreationTokens }
        let cacheReadTokens = breakdown.reduce(0) { $0 + $1.usage.cacheReadTokens }
        let reasoningTokens = breakdown.reduce(0) { $0 + $1.usage.reasoningTokens }

        var summary = AIUsageSummary(
            provider: provider,
            totalCredits: totalCredits,
            estimatedCost: estimatedCost,
            sessionCount: records.count,
            turnCount: totalTurns,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens,
            reasoningTokens: reasoningTokens,
            modelBreakdown: breakdown
        )

        if provider.usesCredits, let creditAllowance, creditAllowance > 0 {
            summary.creditAllowanceFraction = Double(totalCredits) / Double(creditAllowance)
            summary.creditsRemaining = max(creditAllowance - totalCredits, 0)
        }

        if let spendLimit, spendLimit > 0 {
            summary.spendLimitFraction = estimatedCost / spendLimit
            summary.dollarRemaining = max(spendLimit - estimatedCost, 0)
        }

        return summary
    }
}

private struct AIModelUsageAccumulator {
    var requestCount = 0
    var creditCost = 0
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationTokens = 0
    var cacheCreationFiveMinuteTokens = 0
    var cacheCreationOneHourTokens = 0
    var cacheReadTokens = 0
    var reasoningTokens = 0
    var estimatedCost: Double = 0

    mutating func add(_ usage: AIModelUsage) {
        requestCount += usage.requestCount
        creditCost += usage.creditCost
        inputTokens += usage.inputTokens
        outputTokens += usage.outputTokens
        cacheCreationTokens += usage.cacheCreationTokens
        cacheCreationFiveMinuteTokens += usage.cacheCreationFiveMinuteTokens
        cacheCreationOneHourTokens += usage.cacheCreationOneHourTokens
        cacheReadTokens += usage.cacheReadTokens
        reasoningTokens += usage.reasoningTokens
        estimatedCost += usage.estimatedCost
    }

    var usage: AIModelUsage {
        AIModelUsage(
            requestCount: requestCount,
            creditCost: creditCost,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheCreationFiveMinuteTokens: cacheCreationFiveMinuteTokens,
            cacheCreationOneHourTokens: cacheCreationOneHourTokens,
            cacheReadTokens: cacheReadTokens,
            reasoningTokens: reasoningTokens,
            estimatedCost: estimatedCost
        )
    }
}
