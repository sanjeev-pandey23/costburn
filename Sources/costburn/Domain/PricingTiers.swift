import Foundation

// Neon pricing as of 2025 — configurable via Settings > Custom
// Source: https://neon.tech/pricing
enum PricingTier: String, CaseIterable, Identifiable {
    case launch = "Launch"
    case scale = "Scale"
    case agent = "Business"  // "Business/Agent" plan
    case custom = "Custom"

    var id: String { rawValue }

    var rates: Rates {
        switch self {
        case .launch:
            return Rates(computePerCUHour: 0.0255, storagePerGBMonth: 0.1195, transferPerGB: 0.09)
        case .scale:
            return Rates(computePerCUHour: 0.0255, storagePerGBMonth: 0.1195, transferPerGB: 0.09)
        case .agent:
            return Rates(computePerCUHour: 0.0255, storagePerGBMonth: 0.1195, transferPerGB: 0.09)
        case .custom:
            return Rates(computePerCUHour: 0.0255, storagePerGBMonth: 0.1195, transferPerGB: 0.09)
        }
    }

    struct Rates: Sendable {
        let computePerCUHour: Double    // $/CU-hour
        let storagePerGBMonth: Double   // $/GB-month
        let transferPerGB: Double       // $/GB egress
    }
}

struct CustomRates: Sendable {
    var computePerCUHour: Double?
    var storagePerGBMonth: Double?
    var transferPerGB: Double?
}
