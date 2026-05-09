import Foundation

// MARK: - Org-level: GET /api/v2/consumption_history/projects

struct ConsumptionHistoryResponse: Decodable, Sendable {
    let projects: [RawProjectConsumption]
    let pagination: Pagination?
}

struct RawProjectConsumption: Decodable, Sendable {
    let projectID: String
    let projectName: String?
    let periods: [ConsumptionPeriod]

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case projectName = "project_name"
        case periods
    }
}

// MARK: - Account-level: GET /api/v2/consumption_history/account

struct AccountConsumptionResponse: Decodable, Sendable {
    let periods: [ConsumptionPeriod]
}

struct RawAccountConsumption: Sendable {
    let periods: [ConsumptionPeriod]
}

// MARK: - Shared

struct ConsumptionPeriod: Decodable, Sendable {
    let periodID: String
    let consumption: [ConsumptionEntry]

    enum CodingKeys: String, CodingKey {
        case periodID = "period_id"
        case consumption
    }
}

struct ConsumptionEntry: Decodable, Sendable {
    let timeframeStart: Date
    let timeframeEnd: Date
    let computeUnitSeconds: Double?
    let rootBranchBytesMonth: Double?
    let childBranchBytesMonth: Double?
    let publicNetworkTransferBytes: Double?

    enum CodingKeys: String, CodingKey {
        case timeframeStart = "timeframe_start"
        case timeframeEnd = "timeframe_end"
        case computeUnitSeconds = "compute_unit_seconds"
        case rootBranchBytesMonth = "root_branch_bytes_month"
        case childBranchBytesMonth = "child_branch_bytes_month"
        case publicNetworkTransferBytes = "public_network_transfer_bytes"
    }
}

struct Pagination: Decodable, Sendable {
    let cursor: String?
}

// MARK: - Projects list: GET /api/v2/projects
// Available on all plans. Each project carries current billing-period usage.

struct ProjectsListResponse: Decodable, Sendable {
    let projects: [NeonProject]
}

struct NeonProject: Decodable, Sendable {
    let id: String
    let name: String
    // Compute: CU-seconds used in current billing period
    let cpuUsedSec: Double?
    // Storage: current live database size in bytes (instantaneous snapshot, NOT byte-hours)
    // Multiply by hours elapsed in billing period to get byte-hours
    let syntheticStorageSize: Double?
    // Billing period next reset — used to derive period start (reset - 1 month)
    let quotaResetAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case cpuUsedSec          = "cpu_used_sec"
        case syntheticStorageSize = "synthetic_storage_size"
        case quotaResetAt        = "quota_reset_at"
    }
}
