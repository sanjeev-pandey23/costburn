import SwiftUI

struct AIUsageTabView: View {
    @Environment(AppState.self) private var appState
    let provider: AIUsageProvider

    var body: some View {
        if appState.aiUsageIsLoading && appState.aiUsageSummary(for: provider) == nil {
            loadingState
        } else if let usage = appState.aiUsageSummary(for: provider), hasUsage(usage) {
            content(usage: usage)
        } else {
            emptyState
        }
    }

    // MARK: - Main content

    private func content(usage: AIUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            headline(usage)

            if provider.usesCredits,
               let fraction = usage.creditAllowanceFraction,
               let allowance = Preferences.shared.resolvedCreditAllowance {
                creditBar(
                    fraction: fraction,
                    allowance: allowance,
                    remaining: usage.creditsRemaining ?? 0
                )
            }

            if let fraction = usage.spendLimitFraction,
               let limit = Preferences.shared.aiSpendLimit(for: provider) {
                spendLimitBar(fraction: fraction, limit: limit, remaining: usage.dollarRemaining ?? 0)
            }

            stats(usage)

            if !usage.modelBreakdown.isEmpty {
                modelBreakdown(usage.modelBreakdown)
            }
        }
    }

    private func headline(_ usage: AIUsageSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(primaryValue(for: usage))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: usage.estimatedCost)
                    Text(primaryUnit)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Text(secondaryHeadline(for: usage))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(appState.selectedPeriod.rawValue)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func stats(_ usage: AIUsageSummary) -> some View {
        HStack(spacing: 0) {
            statPill(label: "Sessions", value: "\(usage.sessionCount)", icon: provider.icon)
            Divider().frame(height: 28)
            statPill(label: "Turns", value: "\(usage.turnCount)", icon: "bubble.left.and.bubble.right")
            Divider().frame(height: 28)
            if provider.usesCredits {
                statPill(label: "Cost/cr", value: "$0.01", icon: "dollarsign.circle")
            } else {
                statPill(label: "Tokens", value: compactNumber(usage.totalTokens), icon: "number")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Progress bars

    private func creditBar(fraction: Double, allowance: Int, remaining: Int) -> some View {
        let clamped = min(fraction, 1.0)
        let color: Color = clamped >= 1.0 ? .red : clamped >= 0.9 ? .orange : .green
        return progressBar(
            fraction: clamped,
            color: color,
            leading: String(format: "%.0f%% of allowance", clamped * 100),
            trailing: "\(remaining) of \(allowance) credits left"
        )
    }

    private func spendLimitBar(fraction: Double, limit: Double, remaining: Double) -> some View {
        let clamped = min(fraction, 1.0)
        let color: Color = clamped >= 1.0 ? .red : clamped >= 0.8 ? .orange : .blue
        return progressBar(
            fraction: clamped,
            color: color,
            leading: String(format: "%.0f%% of $%.0f limit", clamped * 100, limit),
            trailing: String(format: "$%.2f remaining", remaining)
        )
    }

    private func progressBar(
        fraction: Double,
        color: Color,
        leading: String,
        trailing: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .separatorColor).opacity(0.4))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * fraction, height: 6)
                        .animation(.easeInOut, value: fraction)
                }
            }
            .frame(height: 6)
            HStack {
                Text(leading)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Spacer()
                Text(trailing)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Stat pill

    private func statPill(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Model breakdown

    private func modelBreakdown(_ breakdown: [(model: String, usage: AIModelUsage)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Models")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(breakdown, id: \.model) { item in
                HStack(spacing: 8) {
                    Text(item.model)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(usageLabel(item.usage))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(costString(item.usage.estimatedCost))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .frame(width: 52, alignment: .trailing)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.7)
            Text("Reading \(provider.rawValue) sessions...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(provider.emptyTitle)
                .font(.system(size: 13, weight: .medium))
            Text(provider.emptyMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Formatting

    private var primaryUnit: String {
        provider.usesCredits ? "credits" : "estimated"
    }

    private func primaryValue(for usage: AIUsageSummary) -> String {
        provider.usesCredits ? "\(usage.totalCredits)" : costString(usage.estimatedCost)
    }

    private func secondaryHeadline(for usage: AIUsageSummary) -> String {
        provider.usesCredits
            ? costString(usage.estimatedCost)
            : "\(compactNumber(usage.totalTokens)) tokens"
    }

    private func usageLabel(_ usage: AIModelUsage) -> String {
        provider.usesCredits
            ? "\(usage.creditCost) cr"
            : "\(compactNumber(usage.totalTokens)) tok"
    }

    private func hasUsage(_ usage: AIUsageSummary) -> Bool {
        usage.sessionCount > 0 || usage.totalCredits > 0 || usage.totalTokens > 0 || usage.estimatedCost > 0
    }

    private func costString(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "$%.0f", value)
        }
        if value >= 1 {
            return String(format: "$%.2f", value)
        }
        return String(format: "$%.4f", value)
    }

    private func compactNumber(_ value: Int) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}
