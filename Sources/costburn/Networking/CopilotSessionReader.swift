import Foundation

/// Reads GitHub Copilot usage data from local session files.
/// No network calls or authentication required.
///
/// Data sources:
/// 1. CLI sessions: `~/.copilot/session-state/*/events.jsonl`
///    — `session.shutdown` events contain `totalPremiumRequests` (actual credits) and
///    per-model token breakdowns.
/// 2. VS Code chat: `~/Library/Application Support/Code/User/workspaceStorage/*/GitHub.copilot-chat/transcripts/*.jsonl`
///    — No token counts; parsed for turn count and timestamps only.
struct CopilotSessionReader: Sendable {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - Public API

    func readSessions(since: Date) async -> [AIUsageSessionRecord] {
        async let cliRecords = readCLISessions(since: since)
        async let vsCodeRecords = readVSCodeSessions(since: since)
        async let jbRecords = readJetBrainsSessions(since: since)
        let (cli, vscode, jb) = await (cliRecords, vsCodeRecords, jbRecords)
        return cli + vscode + jb
    }

    // MARK: - CLI sessions (~/.copilot/session-state/*/events.jsonl)

    private func readCLISessions(since: Date) async -> [AIUsageSessionRecord] {
        let sessionStateURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".copilot/session-state")

        guard let subdirs = try? FileManager.default.contentsOfDirectory(
            at: sessionStateURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var records: [AIUsageSessionRecord] = []
        for dir in subdirs {
            let eventsURL = dir.appendingPathComponent("events.jsonl")
            guard FileManager.default.fileExists(atPath: eventsURL.path) else { continue }
            if let record = parseCliSession(eventsURL: eventsURL, since: since) {
                records.append(record)
            }
        }
        return records
    }

    private func parseCliSession(eventsURL: URL, since: Date) -> AIUsageSessionRecord? {
        guard let content = try? String(contentsOf: eventsURL, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: "\n")

        // We need the session.start line for sessionId, and the session.shutdown for metrics.
        // Scan lines for shutdown — it's always the last substantive event.
        var sessionId: String? = nil
        var shutdownData: ShutdownData? = nil
        var turnCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }

            // Quick type-check before full decode to avoid unnecessary work
            guard trimmed.contains("\"type\"") else { continue }

            if trimmed.contains("\"session.start\"") {
                if let parsed = try? decoder.decode(TranscriptSessionStart.self, from: data) {
                    sessionId = parsed.data.sessionId
                }
            } else if trimmed.contains("\"session.shutdown\"") {
                if let parsed = try? decoder.decode(ShutdownEventWrapper.self, from: data) {
                    shutdownData = parsed.data
                }
            } else if trimmed.contains("\"assistant.turn_end\"") {
                turnCount += 1
            }
        }

        guard let sd = shutdownData else { return nil }

        // Session start time from shutdown data (Unix ms)
        let startTime: Date
        if let ms = sd.sessionStartTime {
            startTime = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            // Fall back to file modification date
            let attrs = try? FileManager.default.attributesOfItem(atPath: eventsURL.path)
            startTime = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
        }

        guard startTime >= since else { return nil }

        let credits = sd.totalPremiumRequests ?? 0
        let breakdown = buildModelBreakdown(from: sd.modelMetrics ?? [:])
        let sid = sessionId ?? eventsURL.deletingLastPathComponent().lastPathComponent

        return AIUsageSessionRecord(
            sessionId: sid,
            startTime: startTime,
            provider: .copilot,
            source: .copilotCLI,
            credits: credits,
            turnCount: turnCount,
            modelBreakdown: breakdown,
            estimatedCost: Double(credits) * 0.01
        )
    }

    private func buildModelBreakdown(from raw: [String: RawModelMetrics]) -> [String: AIModelUsage] {
        var result: [String: AIModelUsage] = [:]
        for (model, metrics) in raw {
            let creditCost = metrics.requests?.cost ?? 0
            result[model] = AIModelUsage(
                requestCount: metrics.requests?.count ?? 0,
                creditCost: creditCost,
                inputTokens: metrics.usage?.inputTokens ?? 0,
                outputTokens: metrics.usage?.outputTokens ?? 0,
                cacheReadTokens: metrics.usage?.cacheReadTokens ?? 0,
                estimatedCost: Double(creditCost) * 0.01
            )
        }
        return result
    }

    // MARK: - VS Code chat transcripts

    private func readVSCodeSessions(since: Date) async -> [AIUsageSessionRecord] {
        let wsStorageURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Code/User/workspaceStorage")

        guard let workspaceDirs = try? FileManager.default.contentsOfDirectory(
            at: wsStorageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var records: [AIUsageSessionRecord] = []
        for wsDir in workspaceDirs {
            let transcriptsURL = wsDir
                .appendingPathComponent("GitHub.copilot-chat/transcripts")
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: transcriptsURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                if let record = parseVSCodeTranscript(file, since: since) {
                    records.append(record)
                }
            }
        }
        return records
    }

    private func parseVSCodeTranscript(_ fileURL: URL, since: Date) -> AIUsageSessionRecord? {
        // Use modification date as a fast pre-filter before reading the file
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modDate = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
        guard modDate >= since else { return nil }

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: "\n")

        var sessionId: String? = fileURL.deletingPathExtension().lastPathComponent
        var startTime: Date? = nil
        var turnCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.contains("\"session.start\""), let data = trimmed.data(using: .utf8) {
                if let parsed = try? decoder.decode(TranscriptSessionStart.self, from: data) {
                    if let sid = parsed.data.sessionId { sessionId = sid }
                    if let ts = parsed.timestamp ?? parsed.data.startTime {
                        startTime = ISO8601DateFormatter().date(from: ts)
                    }
                }
            } else if trimmed.contains("\"assistant.turn_end\"") {
                turnCount += 1
            }
        }

        let resolvedStart = startTime ?? modDate
        guard resolvedStart >= since else { return nil }

        return AIUsageSessionRecord(
            sessionId: sessionId ?? fileURL.lastPathComponent,
            startTime: resolvedStart,
            provider: .copilot,
            source: .copilotVSCode,
            // Each assistant turn = 1 premium request in VS Code Copilot Chat.
            // No exact billing data in transcript files; turn count is the best local proxy.
            credits: turnCount,
            turnCount: turnCount,
            modelBreakdown: [:],
            estimatedCost: Double(turnCount) * 0.01
        )
    }

    // MARK: - JetBrains / Android Studio (~/.copilot/jb/*/partition-N.jsonl)
    // The JB plugin stores sessions in partition files with no session.shutdown event —
    // no credit data is available. We can extract session start time and turn count only.

    private func readJetBrainsSessions(since: Date) async -> [AIUsageSessionRecord] {
        let jbURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copilot/jb")

        guard let sessionDirs = try? FileManager.default.contentsOfDirectory(
            at: jbURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var records: [AIUsageSessionRecord] = []
        for dir in sessionDirs {
            if let record = parseJBSession(dir: dir, since: since) {
                records.append(record)
            }
        }
        return records
    }

    private func parseJBSession(dir: URL, since: Date) -> AIUsageSessionRecord? {
        // Fast pre-filter: use the directory modification date before reading files
        let attrs = try? FileManager.default.attributesOfItem(atPath: dir.path)
        let dirModDate = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
        guard dirModDate >= since else { return nil }

        // Enumerate all partition files sorted by name (partition-1, partition-2, …)
        guard let partitions = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return nil }

        let sortedPartitions = partitions
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("partition-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !sortedPartitions.isEmpty else { return nil }

        var startTime: Date? = nil
        var turnCount = 0

        for partition in sortedPartitions {
            guard let content = try? String(contentsOf: partition, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }

                if startTime == nil && trimmed.contains("\"partition.created\"") {
                    if let parsed = try? decoder.decode(JBPartitionCreated.self, from: data) {
                        // createdAt is Unix ms
                        startTime = Date(timeIntervalSince1970: parsed.data.createdAt / 1000.0)
                    }
                } else if trimmed.contains("\"assistant.turn_end\"") {
                    turnCount += 1
                }
            }
        }

        let resolvedStart = startTime ?? dirModDate
        guard resolvedStart >= since else { return nil }

        return AIUsageSessionRecord(
            sessionId: dir.lastPathComponent,
            startTime: resolvedStart,
            provider: .copilot,
            source: .copilotJetBrains,
            credits: 0,   // JB plugin does not write credit data locally
            turnCount: turnCount,
            modelBreakdown: [:],
            estimatedCost: 0
        )
    }
}
