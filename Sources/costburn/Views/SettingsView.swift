import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    // Neon credentials
    @State private var apiKey: String = ""
    @State private var organizationID: String = ""

    // Pricing
    @State private var pricingTier: PricingTier = .launch
    @State private var customComputeRate: String = ""
    @State private var customStorageRate: String = ""
    @State private var customTransferRate: String = ""

    // Alerts
    @State private var spendLimitText: String = ""

    // Copilot
    @State private var copilotPlan: CopilotPlan = .individualPro
    @State private var copilotCustomAllowanceText: String = ""
    @State private var copilotSpendLimitText: String = ""

    // General
    @State private var refreshInterval: TimeInterval = 900
    @State private var launchAtLogin: Bool = false
    @State private var loginItemNeedsApproval: Bool = false

    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") {
                    saveAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: Neon API
                    section("Neon API") {
                        VStack(alignment: .leading, spacing: 8) {
                            label("API Key")
                            SecureField("neon_...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            Text("Generate at: console.neon.tech/app/settings/api-keys")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)

                            Divider().padding(.vertical, 2)

                            label("Organization ID")
                            TextField("Optional — leave blank for personal accounts", text: $organizationID)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                            Text("Required for per-project breakdown. Find at: console.neon.tech/app/settings/organization")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // MARK: Pricing
                    section("Pricing") {
                        VStack(alignment: .leading, spacing: 8) {
                            label("Plan")
                            Picker("Plan", selection: $pricingTier) {
                                ForEach(PricingTier.allCases) { tier in
                                    Text(tier.rawValue).tag(tier)
                                }
                            }
                            .pickerStyle(.segmented)

                            if pricingTier == .custom {
                                Divider().padding(.vertical, 2)
                                label("Custom rates (leave blank to use defaults)")
                                rateField("Compute ($/CU-hour)", binding: $customComputeRate, placeholder: "0.106")
                                rateField("Storage ($/GB-month)", binding: $customStorageRate, placeholder: "0.35")
                                rateField("Egress ($/GB)", binding: $customTransferRate, placeholder: "0.10")
                            } else {
                                let rates = pricingTier.rates
                                HStack(spacing: 16) {
                                    rateInfo("Compute", String(format: "$%.4f/CU-h", rates.computePerCUHour))
                                    rateInfo("Storage", String(format: "$%.4f/GB-mo", rates.storagePerGBMonth))
                                    rateInfo("Egress", String(format: "$%.4f/GB", rates.transferPerGB))
                                }
                                .padding(.top, 2)
                            }
                        }
                    }

                    // MARK: Alerts
                    section("Spend Alerts") {
                        VStack(alignment: .leading, spacing: 8) {
                            label("Monthly spend limit ($)")
                            TextField("e.g. 50.00", text: $spendLimitText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                            Text("Receive a notification at 80% and 100% of this limit.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // MARK: Copilot
                    section("Copilot") {
                        VStack(alignment: .leading, spacing: 8) {
                            label("Plan")
                            Picker("Plan", selection: $copilotPlan) {
                                ForEach(CopilotPlan.allCases) { plan in
                                    Text(plan.rawValue).tag(plan)
                                }
                            }
                            .pickerStyle(.menu)

                            // Show plan default allowance (or custom field)
                            if copilotPlan == .custom {
                                label("Monthly credit allowance")
                                TextField("e.g. 5000", text: $copilotCustomAllowanceText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                            } else if let allowance = copilotPlan.defaultCreditAllowance {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Text("Monthly allowance: \(allowance) credits ($\(String(format: "%.0f", Double(allowance) * 0.01)))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Divider().padding(.vertical, 2)

                            label("Spend limit (optional)")
                            TextField("e.g. 15.00", text: $copilotSpendLimitText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                            Text("Set a dollar cap in addition to your credit allowance. 1 credit = $0.01.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // MARK: General
                    section("General") {
                        VStack(alignment: .leading, spacing: 8) {
                            label("Refresh interval")
                            Picker("Refresh", selection: $refreshInterval) {
                                Text("15 minutes").tag(TimeInterval(900))
                                Text("30 minutes").tag(TimeInterval(1800))
                                Text("1 hour").tag(TimeInterval(3600))
                            }
                            .pickerStyle(.segmented)

                            Divider().padding(.vertical, 2)

                            Toggle(isOn: $launchAtLogin) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Launch at login")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Start CostBurn automatically when you log in.")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .onChange(of: launchAtLogin) { _, newValue in
                                applyLaunchAtLogin(newValue)
                            }

                            if loginItemNeedsApproval {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.system(size: 10))
                                    Text("Open System Settings → General → Login Items and enable CostBurn.")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            if saved {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Saved").font(.system(size: 12))
                }
                .padding(.bottom, 8)
            }
        }
        .frame(width: 400, height: 560)
        .onAppear { loadPreferences() }
    }

    // MARK: - Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
    }

    private func rateField(_ label: String, binding: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
        }
    }

    private func rateInfo(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    // MARK: - Launch at login

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try Preferences.shared.setLaunchAtLogin(enabled)
            let status = Preferences.shared.launchAtLoginStatus
            loginItemNeedsApproval = status == .requiresApproval
            // Reflect true state back (system may have overridden our request)
            launchAtLogin = status == .enabled || status == .requiresApproval
        } catch {
            // Roll the toggle back if the system outright rejected the request
            launchAtLogin = Preferences.shared.launchAtLogin
            loginItemNeedsApproval = false
        }
    }

    // MARK: - Persistence

    private func loadPreferences() {
        apiKey = KeychainHelper.shared.load(key: KeychainHelper.apiKeyTag) ?? ""
        organizationID = Preferences.shared.organizationID
        pricingTier = Preferences.shared.pricingTier
        if let c = Preferences.shared.customRates {
            customComputeRate = c.computePerCUHour.map { String(format: "%.6f", $0) } ?? ""
            customStorageRate = c.storagePerGBMonth.map { String(format: "%.6f", $0) } ?? ""
            customTransferRate = c.transferPerGB.map { String(format: "%.6f", $0) } ?? ""
        }
        if let limit = Preferences.shared.monthlySpendLimit {
            spendLimitText = String(format: "%.2f", limit)
        }
        refreshInterval = Preferences.shared.refreshInterval
        launchAtLogin = Preferences.shared.launchAtLogin
        loginItemNeedsApproval = Preferences.shared.launchAtLoginStatus == .requiresApproval

        copilotPlan = Preferences.shared.copilotPlan
        if let customAllowance = Preferences.shared.copilotCreditAllowance {
            copilotCustomAllowanceText = "\(customAllowance)"
        }
        if let limit = Preferences.shared.copilotSpendLimit {
            copilotSpendLimitText = String(format: "%.2f", limit)
        }
    }

    private func saveAndDismiss() {
        // API key
        if !apiKey.isEmpty {
            KeychainHelper.shared.save(key: KeychainHelper.apiKeyTag, value: apiKey)
        } else {
            KeychainHelper.shared.delete(key: KeychainHelper.apiKeyTag)
        }

        // Preferences
        Preferences.shared.organizationID = organizationID
        Preferences.shared.pricingTier = pricingTier

        if pricingTier == .custom {
            Preferences.shared.customRates = CustomRates(
                computePerCUHour: Double(customComputeRate),
                storagePerGBMonth: Double(customStorageRate),
                transferPerGB: Double(customTransferRate)
            )
        } else {
            Preferences.shared.customRates = nil
        }

        Preferences.shared.monthlySpendLimit = Double(spendLimitText)
        Preferences.shared.refreshInterval = refreshInterval
        // Launch at login is applied immediately via onChange; no action needed here.

        // Copilot
        Preferences.shared.copilotPlan = copilotPlan
        if copilotPlan == .custom {
            Preferences.shared.copilotCreditAllowance = Int(copilotCustomAllowanceText)
        } else {
            Preferences.shared.copilotCreditAllowance = nil
        }
        Preferences.shared.copilotSpendLimit = Double(copilotSpendLimitText)

        // Refresh cached credentials then restart polling
        appState.reloadCredentials()
        appState.startPolling()
        Task { await appState.refreshCopilot() }

        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismiss()
        }
    }
}
