import Foundation

struct CostCalculator: Sendable {
    private let rates: PricingTier.Rates

    init(tier: PricingTier, customRates: CustomRates?) {
        let base = tier.rates
        if let c = customRates {
            rates = PricingTier.Rates(
                computePerCUHour: c.computePerCUHour ?? base.computePerCUHour,
                storagePerGBMonth: c.storagePerGBMonth ?? base.storagePerGBMonth,
                transferPerGB: c.transferPerGB ?? base.transferPerGB
            )
        } else {
            rates = base
        }
    }

    // MARK: - Conversion helpers

    /// CU-seconds → CU-hours
    func cuHours(from cuSeconds: Double) -> Double {
        cuSeconds / 3600.0
    }

    /// byte-hours → GB-months  (730 hours/month, 1e9 bytes/GB)
    func gbMonths(from byteHours: Double) -> Double {
        byteHours / (1_000_000_000.0 * 730.0)
    }

    /// bytes → GB
    func gb(from bytes: Double) -> Double {
        bytes / 1_000_000_000.0
    }

    // MARK: - Cost from metrics

    func computeCost(cuSeconds: Double) -> Double {
        cuHours(from: cuSeconds) * rates.computePerCUHour
    }

    func storageCost(byteHours: Double) -> Double {
        gbMonths(from: byteHours) * rates.storagePerGBMonth
    }

    func transferCost(bytes: Double) -> Double {
        gb(from: bytes) * rates.transferPerGB
    }

    // MARK: - Build domain models

    func buildProjectConsumption(
        _ raw: RawProjectConsumption,
        nameMap: [String: String]
    ) -> ProjectConsumption {
        var totalCU: Double = 0
        var totalRootBytes: Double = 0
        var totalChildBytes: Double = 0
        var totalTransfer: Double = 0

        for period in raw.periods {
            for entry in period.consumption {
                totalCU += entry.computeUnitSeconds ?? 0
                totalRootBytes += entry.rootBranchBytesMonth ?? 0
                totalChildBytes += entry.childBranchBytesMonth ?? 0
                totalTransfer += entry.publicNetworkTransferBytes ?? 0
            }
        }

        let computeHours = cuHours(from: totalCU)
        let storageGBMonth = gbMonths(from: totalRootBytes + totalChildBytes)
        let transferGB = gb(from: totalTransfer)

        return ProjectConsumption(
            projectID: raw.projectID,
            projectName: nameMap[raw.projectID] ?? raw.projectID,
            computeHours: computeHours,
            storageGBMonth: storageGBMonth,
            transferGB: transferGB,
            computeCost: computeCost(cuSeconds: totalCU),
            storageCost: storageCost(byteHours: totalRootBytes + totalChildBytes),
            transferCost: transferCost(bytes: totalTransfer)
        )
    }

    /// Builds from GET /api/v2/projects response — works on all Neon plans.
    /// Storage is approximated: synthetic_storage_size (instantaneous bytes) × hours
    /// elapsed in the current billing period. Data transfer is not available from
    /// this endpoint and is reported as zero.
    func buildProjectConsumptionFromProject(_ project: NeonProject) -> ProjectConsumption {
        let cuSeconds = project.cpuUsedSec ?? 0

        // Derive billing period start from quota_reset_at (next reset date - 1 month)
        let storageSizeBytes = project.syntheticStorageSize ?? 0
        let byteHours: Double
        if let resetAt = project.quotaResetAt,
           let periodStart = Calendar.current.date(byAdding: .month, value: -1, to: resetAt) {
            let hoursElapsed = max(Date().timeIntervalSince(periodStart) / 3600, 0)
            byteHours = storageSizeBytes * hoursElapsed
        } else {
            byteHours = 0
        }

        return ProjectConsumption(
            projectID:      project.id,
            projectName:    project.name,
            computeHours:   cuHours(from: cuSeconds),
            storageGBMonth: gbMonths(from: byteHours),
            transferGB:     0, // not exposed by GET /api/v2/projects
            computeCost:    computeCost(cuSeconds: cuSeconds),
            storageCost:    storageCost(byteHours: byteHours),
            transferCost:   0
        )
    }

    func buildAccountSummary(_ raw: RawAccountConsumption) -> AccountSummary {
        var totalCU: Double = 0
        var totalRootBytes: Double = 0
        var totalChildBytes: Double = 0
        var totalTransfer: Double = 0

        for period in raw.periods {
            for entry in period.consumption {
                totalCU += entry.computeUnitSeconds ?? 0
                totalRootBytes += entry.rootBranchBytesMonth ?? 0
                totalChildBytes += entry.childBranchBytesMonth ?? 0
                totalTransfer += entry.publicNetworkTransferBytes ?? 0
            }
        }

        let computeHours = cuHours(from: totalCU)
        let storageGBMonth = gbMonths(from: totalRootBytes + totalChildBytes)
        let transferGB = gb(from: totalTransfer)

        return AccountSummary(
            computeHours: computeHours,
            storageGBMonth: storageGBMonth,
            transferGB: transferGB,
            computeCost: computeCost(cuSeconds: totalCU),
            storageCost: storageCost(byteHours: totalRootBytes + totalChildBytes),
            transferCost: transferCost(bytes: totalTransfer)
        )
    }
}

// MARK: - Domain models

struct ProjectConsumption: Identifiable, Sendable {
    let projectID: String
    let projectName: String
    let computeHours: Double
    let storageGBMonth: Double
    let transferGB: Double
    let computeCost: Double
    let storageCost: Double
    let transferCost: Double

    var id: String { projectID }
    var estimatedCost: Double { computeCost + storageCost + transferCost }
}

struct AccountSummary: Sendable {
    let computeHours: Double
    let storageGBMonth: Double
    let transferGB: Double
    let computeCost: Double
    let storageCost: Double
    let transferCost: Double

    var estimatedCost: Double { computeCost + storageCost + transferCost }
}
