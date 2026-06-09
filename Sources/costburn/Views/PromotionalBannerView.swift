import SwiftUI

struct PromotionalBannerView: View {
    @Environment(\.openURL) private var openURL

    let onDismiss: () -> Void

    private let repositoryURL = URL(string: "https://github.com/sanjeev-pandey23/costburn")!

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)

            Text("Enjoying CostBurn?")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Button("Star it on GitHub") {
                openURL(repositoryURL)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.orange)
            .lineLimit(1)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }
}