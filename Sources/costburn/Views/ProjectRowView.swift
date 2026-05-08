import SwiftUI

struct ProjectRowView: View {
    let project: ProjectConsumption
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Summary row
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "cylinder.split.1x2")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(project.projectName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(String(format: "$%.2f", project.estimatedCost))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(expanded ? .degrees(90) : .zero)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)

            // Expanded detail
            if expanded {
                VStack(spacing: 2) {
                    metricRow(
                        label: "Compute",
                        detail: String(format: "%.2f CU-h", project.computeHours),
                        cost: project.computeCost,
                        icon: "cpu"
                    )
                    metricRow(
                        label: "Storage",
                        detail: String(format: "%.3f GB-mo", project.storageGBMonth),
                        cost: project.storageCost,
                        icon: "internaldrive"
                    )
                    metricRow(
                        label: "Egress",
                        detail: String(format: "%.3f GB", project.transferGB),
                        cost: project.transferCost,
                        icon: "arrow.up.circle"
                    )
                }
                .padding(.bottom, 6)
                .padding(.horizontal, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func metricRow(label: String, detail: String, cost: Double, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "$%.4f", cost))
                .font(.system(size: 11, design: .rounded))
        }
        .padding(.vertical, 2)
        .padding(.leading, 6)
    }
}
