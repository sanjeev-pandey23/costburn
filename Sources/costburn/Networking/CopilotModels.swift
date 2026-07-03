import Foundation

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

// MARK: - Raw JSON shape for JetBrains partition.created

struct JBPartitionCreated: Decodable {
    let data: JBPartitionData
}

struct JBPartitionData: Decodable {
    let createdAt: Double   // Unix ms
}
