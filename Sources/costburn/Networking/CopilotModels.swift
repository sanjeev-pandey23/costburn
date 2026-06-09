import Foundation

// MARK: - Per-model usage inside a session

struct CopilotModelUsage: Sendable {
    let requestCount: Int
    let creditCost: Int    // from requests.cost in session.shutdown
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
}

// MARK: - Single parsed session record

struct CopilotSessionRecord: Sendable {
    enum Source: Sendable { case cli, vscode }

    let sessionId: String
    let startTime: Date
    let source: Source
    /// Exact totalPremiumRequests (cli) or turn count as proxy (vscode)
    let credits: Int
    /// Number of assistant turns in the session
    let turnCount: Int
    let modelBreakdown: [String: CopilotModelUsage]
}

// MARK: - Aggregated summary shown in the UI

struct CopilotUsageSummary: Sendable {
    let totalCredits: Int
    /// totalCredits × $0.01
    let estimatedCost: Double
    let sessionCount: Int
    let turnCount: Int
    /// Sorted descending by creditCost
    let modelBreakdown: [(model: String, usage: CopilotModelUsage)]

    // Derived from configured allowance / limit
    var creditAllowanceFraction: Double?   // nil when no allowance set
    var creditsRemaining: Int?
    var spendLimitFraction: Double?        // nil when no dollar limit set
    var dollarRemaining: Double?
    var overCreditAllowance: Bool { creditAllowanceFraction.map { $0 >= 1.0 } ?? false }
    var overSpendLimit: Bool { spendLimitFraction.map { $0 >= 1.0 } ?? false }
}

// MARK: - Copilot plan definitions

enum CopilotPlan: String, CaseIterable, Identifiable, Sendable {
    case individualPro      = "Individual Pro"
    case individualProPlus  = "Individual Pro+"
    case individualMax      = "Individual Max"
    case business           = "Business"
    case enterprise         = "Enterprise"
    case custom             = "Custom"

    var id: String { rawValue }

    /// Default monthly credit allowance for each plan (nil for custom).
    var defaultCreditAllowance: Int? {
        switch self {
        case .individualPro:     return 1_500
        case .individualProPlus: return 7_000
        case .individualMax:     return 20_000
        case .business:          return 1_900
        case .enterprise:        return 3_900
        case .custom:            return nil
        }
    }
}

// MARK: - Raw JSON shapes for session.shutdown parsing

struct ShutdownEventWrapper: Decodable {
    let type: String
    let data: ShutdownData
}

struct ShutdownData: Decodable {
    let totalPremiumRequests: Int?
    let sessionStartTime: Double?        // Unix ms
    let modelMetrics: [String: RawModelMetrics]?
    let currentModel: String?
}

struct RawModelMetrics: Decodable {
    let requests: RawRequestMetrics?
    let usage: RawUsageMetrics?
}

struct RawRequestMetrics: Decodable {
    let count: Int?
    let cost: Int?
}

struct RawUsageMetrics: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
}

// MARK: - Raw JSON shape for vscode transcript session.start

struct TranscriptSessionStart: Decodable {
    let type: String
    let data: TranscriptSessionData
    let timestamp: String?
}

struct TranscriptSessionData: Decodable {
    let sessionId: String?
    let startTime: String?
}
