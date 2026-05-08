import SwiftUI

struct SummaryView: View {
    @Environment(AppState.self) private var appState

    private var metrics: (compute: Double, storage: Double, transfer: Double, total: Double) {
        if let summary = appState.accountSummary {
            return (
                summary.computeCost,
                summary.storageCost,
                summary.transferCost,
                summary.estimatedCost
            )
        }
        let compute = appState.projects.reduce(0) { $0 + $1.computeCost }
        let storage = appState.projects.reduce(0) { $0 + $1.storageCost }
        let transfer = appState.projects.reduce(0) { $0 + $1.transferCost }
        return (compute, storage, transfer, compute + storage + transfer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Period label + total
            HStack(alignment: .firstTextBaseline) {
                Text(costString(metrics.total))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: metrics.total)
                Spacer()
                Text(appState.selectedPeriod.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Spend limit progress bar
            if let limit = Preferences.shared.monthlySpendLimit, limit > 0 {
                spendLimitBar(spent: metrics.total, limit: limit)
            }

            // Metric breakdown
            HStack(spacing: 0) {
                metricPill(
                    label: "Compute",
                    value: metrics.compute,
                    icon: "cpu"
                )
                Divider().frame(height: 28)
                metricPill(
                    label: "Storage",
                    value: metrics.storage,
                    icon: "internaldrive"
                )
                Divider().frame(height: 28)
                metricPill(
                    label: "Egress",
                    value: metrics.transfer,
                    icon: "arrow.up.circle"
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    // MARK: - Spend limit bar

    private func spendLimitBar(spent: Double, limit: Double) -> some View {
        let fraction = min(spent / limit, 1.0)
        let color: Color = fraction >= 1.0 ? .red : fraction >= 0.8 ? .orange : .green
        return VStack(alignment: .leading, spacing: 3) {
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
                Text(String(format: "%.0f%% of $%.0f limit", fraction * 100, limit))
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Spacer()
                Text(String(format: "$%.2f remaining", max(limit - spent, 0)))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Metric pill

    private func metricPill(label: String, value: Double, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(costString(value))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func costString(_ value: Double) -> String {
        if value < 0.01 { return "$0.00" }
        if value >= 100 { return String(format: "$%.0f", value) }
        return String(format: "$%.2f", value)
    }
}
