import Foundation

// Neon pricing — source: https://neon.com/pricing#compute-usage
// Use Settings → Custom to override any rate.
enum PricingTier: String, CaseIterable, Identifiable {
    case launch = "Launch"
    case scale = "Scale"
    case custom = "Custom"

    var id: String { rawValue }

    var rates: Rates {
        switch self {
        case .launch:
            // Compute $0.106/CU-hour · Storage $0.35/GB-month · Egress $0.10/GB
            return Rates(computePerCUHour: 0.106, storagePerGBMonth: 0.35, transferPerGB: 0.10)
        case .scale:
            // Compute $0.222/CU-hour · Storage $0.35/GB-month · Egress $0.10/GB
            return Rates(computePerCUHour: 0.222, storagePerGBMonth: 0.35, transferPerGB: 0.10)
        case .custom:
            return Rates(computePerCUHour: 0.106, storagePerGBMonth: 0.35, transferPerGB: 0.10)
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
