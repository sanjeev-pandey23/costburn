import Foundation
import ServiceManagement

@MainActor
final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Keys

    private enum Key: String {
        case organizationID = "org_id"
        case pricingTier = "pricing_tier"
        case customComputeRate = "custom_compute_rate"
        case customStorageRate = "custom_storage_rate"
        case customTransferRate = "custom_transfer_rate"
        case monthlySpendLimit = "monthly_spend_limit"
        case refreshInterval = "refresh_interval"
        // Copilot
        case copilotPlan = "copilot_plan"
        case copilotCreditAllowance = "copilot_credit_allowance"
        case copilotSpendLimit = "copilot_spend_limit"
    }

    // MARK: - Properties

    var organizationID: String {
        get { defaults.string(forKey: Key.organizationID.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.organizationID.rawValue) }
    }

    var pricingTier: PricingTier {
        get {
            guard let raw = defaults.string(forKey: Key.pricingTier.rawValue),
                  let tier = PricingTier(rawValue: raw) else { return .launch }
            return tier
        }
        set { defaults.set(newValue.rawValue, forKey: Key.pricingTier.rawValue) }
    }

    var customRates: CustomRates? {
        get {
            let compute = defaults.double(forKey: Key.customComputeRate.rawValue)
            let storage = defaults.double(forKey: Key.customStorageRate.rawValue)
            let transfer = defaults.double(forKey: Key.customTransferRate.rawValue)
            guard compute > 0 || storage > 0 || transfer > 0 else { return nil }
            return CustomRates(
                computePerCUHour: compute > 0 ? compute : nil,
                storagePerGBMonth: storage > 0 ? storage : nil,
                transferPerGB: transfer > 0 ? transfer : nil
            )
        }
        set {
            defaults.set(newValue?.computePerCUHour ?? 0, forKey: Key.customComputeRate.rawValue)
            defaults.set(newValue?.storagePerGBMonth ?? 0, forKey: Key.customStorageRate.rawValue)
            defaults.set(newValue?.transferPerGB ?? 0, forKey: Key.customTransferRate.rawValue)
        }
    }

    var monthlySpendLimit: Double? {
        get {
            let v = defaults.double(forKey: Key.monthlySpendLimit.rawValue)
            return v > 0 ? v : nil
        }
        set { defaults.set(newValue ?? 0, forKey: Key.monthlySpendLimit.rawValue) }
    }

    /// Polling interval in seconds. Default: 15 minutes.
    var refreshInterval: TimeInterval {
        get {
            let v = defaults.double(forKey: Key.refreshInterval.rawValue)
            return v > 0 ? v : 900
        }
        set { defaults.set(newValue, forKey: Key.refreshInterval.rawValue) }
    }

    // MARK: - Copilot

    var copilotPlan: CopilotPlan {
        get {
            guard let raw = defaults.string(forKey: Key.copilotPlan.rawValue),
                  let plan = CopilotPlan(rawValue: raw) else { return .individualPro }
            return plan
        }
        set { defaults.set(newValue.rawValue, forKey: Key.copilotPlan.rawValue) }
    }

    /// Custom credit allowance override. If nil, falls back to the plan's default.
    var copilotCreditAllowance: Int? {
        get {
            let v = defaults.integer(forKey: Key.copilotCreditAllowance.rawValue)
            return v > 0 ? v : nil
        }
        set { defaults.set(newValue ?? 0, forKey: Key.copilotCreditAllowance.rawValue) }
    }

    /// Resolved monthly credit allowance: custom override → plan default → nil.
    var resolvedCreditAllowance: Int? {
        copilotCreditAllowance ?? copilotPlan.defaultCreditAllowance
    }

    /// Optional monthly dollar spend limit for Copilot (in addition to credit allowance).
    var copilotSpendLimit: Double? {
        get {
            let v = defaults.double(forKey: Key.copilotSpendLimit.rawValue)
            return v > 0 ? v : nil
        }
        set { defaults.set(newValue ?? 0, forKey: Key.copilotSpendLimit.rawValue) }
    }

    // MARK: - Launch at login (backed by SMAppService, not UserDefaults)

    var launchAtLoginStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Returns true only when the service is confirmed enabled.
    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item.
    /// Throws if the system rejects the change.
    /// Status `.requiresApproval` means the user must approve in
    /// System Settings → General → Login Items.
    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
