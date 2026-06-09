import SwiftUI

struct CopilotTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.copilotIsLoading && appState.copilotUsage == nil {
            loadingState
        } else if let usage = appState.copilotUsage {
            content(usage: usage)
        } else {
            emptyState
        }
    }

    // MARK: - Main content

    private func content(usage: CopilotUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Credits headline + cost
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(usage.totalCredits)")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: usage.totalCredits)
                        Text("credits")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Text(String(format: "$%.2f", usage.estimatedCost))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(appState.selectedPeriod.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Credit allowance progress bar
            if let fraction = usage.creditAllowanceFraction,
               let allowance = Preferences.shared.resolvedCreditAllowance {
                creditBar(
                    fraction: fraction,
                    usedLabel: "\(usage.totalCredits) / \(allowance) credits",
                    remainingLabel: "\(usage.creditsRemaining ?? 0) left"
                )
            }

            // Dollar spend limit progress bar (optional)
            if let fraction = usage.spendLimitFraction,
               let limit = Preferences.shared.copilotSpendLimit {
                spendLimitBar(fraction: fraction, limit: limit, remaining: usage.dollarRemaining ?? 0)
            }

            // Stats pills
            HStack(spacing: 0) {
                statPill(label: "Sessions", value: "\(usage.sessionCount)", icon: "terminal")
                Divider().frame(height: 28)
                statPill(label: "Turns", value: "\(usage.turnCount)", icon: "bubble.left.and.bubble.right")
                Divider().frame(height: 28)
                statPill(label: "Cost/cr", value: "$0.01", icon: "dollarsign.circle")
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            // Model breakdown
            if !usage.modelBreakdown.isEmpty {
                modelBreakdown(usage.modelBreakdown)
            }
        }
    }

    // MARK: - Credit allowance bar

    private func creditBar(fraction: Double, usedLabel: String, remainingLabel: String) -> some View {
        let clamped = min(fraction, 1.0)
        let color: Color = clamped >= 1.0 ? .red : clamped >= 0.9 ? .orange : .green
        return VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .separatorColor).opacity(0.4))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * clamped, height: 6)
                        .animation(.easeInOut, value: clamped)
                }
            }
            .frame(height: 6)
            HStack {
                Text(String(format: "%.0f%% of allowance", clamped * 100))
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Spacer()
                Text(remainingLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Spend limit bar

    private func spendLimitBar(fraction: Double, limit: Double, remaining: Double) -> some View {
        let clamped = min(fraction, 1.0)
        let color: Color = clamped >= 1.0 ? .red : clamped >= 0.8 ? .orange : .blue
        return VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .separatorColor).opacity(0.4))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * clamped, height: 6)
                        .animation(.easeInOut, value: clamped)
                }
            }
            .frame(height: 6)
            HStack {
                Text(String(format: "%.0f%% of $%.0f limit", clamped * 100, limit))
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Spacer()
                Text(String(format: "$%.2f remaining", remaining))
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

    private func modelBreakdown(_ breakdown: [(model: String, usage: CopilotModelUsage)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Models")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(breakdown, id: \.model) { item in
                HStack {
                    Text(item.model)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(item.usage.creditCost) cr")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", Double(item.usage.creditCost) * 0.01))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .frame(width: 44, alignment: .trailing)
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
            Text("Reading sessions…")
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
            Text("No Copilot sessions found")
                .font(.system(size: 13, weight: .medium))
            Text("Sessions from this billing month will appear here automatically. Configure your plan in Settings to set a credit allowance.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
