import SwiftUI

struct PopoverView: View {
    @Environment(AppState.self) private var appState
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            if !appState.isConfigured {
                setupPrompt
            } else {
                // Period picker
                periodPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                // Main content
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

            Spacer(minLength: 0)
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: 320)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 14, weight: .semibold))
                Text("CostBurn")
                    .font(.system(size: 13, weight: .semibold))
                Text("· Neon DB")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: appState.isLoading ? "arrow.clockwise" : "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .rotationEffect(appState.isLoading ? .degrees(360) : .zero)
                    .animation(
                        appState.isLoading
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: appState.isLoading
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        @Bindable var state = appState
        return Picker("Period", selection: $state.selectedPeriod) {
            ForEach(AppState.Period.allCases) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: appState.selectedPeriod) {
            Task { await appState.refresh() }
        }
    }

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
        HStack {
            if let error = appState.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 11))
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let updated = appState.lastUpdated {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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
