import SwiftUI

struct PopoverView: View {
    @Environment(AppState.self) private var appState
    @State private var showSettings = false
    @State private var showPromotionalBanner = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            // Tab switcher
            tabPicker
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)

            Divider()

            if appState.activeTab == .neon {
                if !appState.isConfigured {
                    setupPrompt
                } else {
                    periodPicker
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    // Neon content
                    ScrollView {
                        VStack(spacing: 12) {
                            SummaryView()
                            if !appState.projects.isEmpty {
                                projectList
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            } else {
                // AI usage content
                periodPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                aiProviderPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ScrollView {
                    AIUsageTabView(provider: appState.activeAIUsageProvider)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }

            Spacer(minLength: 0)
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            if showPromotionalBanner {
                PromotionalBannerView {
                    showPromotionalBanner = false
                }

                Divider()
            }
        }
        .frame(width: 320)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Header

    private var header: some View {
        let isLoading = appState.activeTab == .neon ? appState.isLoading : appState.aiUsageIsLoading
        return HStack {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 14, weight: .semibold))
                Text("CostBurn")
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            Button {
                if appState.activeTab == .neon {
                    Task { await appState.refresh() }
                } else {
                    Task { await appState.refreshAIUsage() }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .rotationEffect(isLoading ? .degrees(360) : .zero)
                    .animation(
                        isLoading
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: isLoading
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        @Bindable var state = appState
        return Picker("Tab", selection: $state.activeTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        @Bindable var state = appState
        return PeriodSegmentedPicker(selection: $state.selectedPeriod)
            .onChange(of: appState.selectedPeriod) {
                Task {
                    await appState.refresh()
                    await appState.refreshAIUsage()
                }
            }
    }

    // MARK: - AI Provider Picker

    private var aiProviderPicker: some View {
        @Bindable var state = appState
        return Picker("AI Agent", selection: $state.activeAIUsageProvider) {
            ForEach(AIUsageProvider.allCases) { provider in
                Text(provider.rawValue).tag(provider)
            }
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - NSViewRepresentable period picker
// Uses setContentHuggingPriority(.defaultLow) so the NSSegmentedControl
// expands to fill available width instead of using intrinsic content size.
// Required because two sibling NSSegmentedControls in the same NSHostingView
// negotiate sizes with each other, shrinking the period picker.

private struct PeriodSegmentedPicker: NSViewRepresentable {
    @Binding var selection: AppState.Period

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentStyle = .rounded
        control.trackingMode = .selectOne
        control.segmentCount = AppState.Period.allCases.count
        for (i, period) in AppState.Period.allCases.enumerated() {
            control.setLabel(period.rawValue, forSegment: i)
        }
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectionChanged(_:))
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        let idx = AppState.Period.allCases.firstIndex(of: selection) ?? 0
        if control.selectedSegment != idx {
            control.selectedSegment = idx
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PeriodSegmentedPicker
        init(_ parent: PeriodSegmentedPicker) { self.parent = parent }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let period = AppState.Period.allCases[sender.selectedSegment]
            parent.selection = period
        }
    }
}

// Re-open PopoverView to keep the closing brace matched — struct continues above.
extension PopoverView {

    // MARK: - Project list

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Projects")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(appState.projects) { project in
                ProjectRowView(project: project)
            }
        }
    }

    // MARK: - Setup prompt

    private var setupPrompt: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "key.horizontal")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Connect your Neon account")
                .font(.system(size: 13, weight: .medium))
            Text("Add your API key in Settings to start tracking costs.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
            Button("Open Settings") { showSettings = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding()
    }

    // MARK: - Footer

    private var footer: some View {
        let activeError = appState.activeTab == .neon ? appState.lastError : appState.aiUsageError
        let activeUpdated = appState.activeTab == .neon ? appState.lastUpdated : appState.aiUsageLastUpdated
        return HStack {
            if let error = activeError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 11))
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                if let updated = activeUpdated {
                    Text("Updated \(updated, style: .relative) ago")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
