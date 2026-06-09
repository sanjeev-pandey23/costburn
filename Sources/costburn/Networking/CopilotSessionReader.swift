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

    func readSessions(since: Date) async -> [CopilotSessionRecord] {
        async let cliRecords = readCLISessions(since: since)
        async let vsCodeRecords = readVSCodeSessions(since: since)
        let (cli, vscode) = await (cliRecords, vsCodeRecords)
        return cli + vscode
    }

    // MARK: - CLI sessions (~/.copilot/session-state/*/events.jsonl)

    private func readCLISessions(since: Date) async -> [CopilotSessionRecord] {
        let sessionStateURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".copilot/session-state")

        guard let subdirs = try? FileManager.default.contentsOfDirectory(
            at: sessionStateURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var records: [CopilotSessionRecord] = []
        for dir in subdirs {
            let eventsURL = dir.appendingPathComponent("events.jsonl")
            guard FileManager.default.fileExists(atPath: eventsURL.path) else { continue }
            if let record = parseCliSession(eventsURL: eventsURL, since: since) {
                records.append(record)
            }
        }
        return records
    }

    private func parseCliSession(eventsURL: URL, since: Date) -> CopilotSessionRecord? {
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

        return CopilotSessionRecord(
            sessionId: sid,
            startTime: startTime,
            source: .cli,
            credits: credits,
            turnCount: turnCount,
            modelBreakdown: breakdown
        )
    }

    private func buildModelBreakdown(from raw: [String: RawModelMetrics]) -> [String: CopilotModelUsage] {
        var result: [String: CopilotModelUsage] = [:]
        for (model, metrics) in raw {
            result[model] = CopilotModelUsage(
                requestCount: metrics.requests?.count ?? 0,
                creditCost: metrics.requests?.cost ?? 0,
                inputTokens: metrics.usage?.inputTokens ?? 0,
                outputTokens: metrics.usage?.outputTokens ?? 0,
                cacheReadTokens: metrics.usage?.cacheReadTokens ?? 0
            )
        }
        return result
    }

    // MARK: - VS Code chat transcripts

    private func readVSCodeSessions(since: Date) async -> [CopilotSessionRecord] {
        let wsStorageURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Code/User/workspaceStorage")

        guard let workspaceDirs = try? FileManager.default.contentsOfDirectory(
            at: wsStorageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var records: [CopilotSessionRecord] = []
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

    private func parseVSCodeTranscript(_ fileURL: URL, since: Date) -> CopilotSessionRecord? {
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

        return CopilotSessionRecord(
            sessionId: sessionId ?? fileURL.lastPathComponent,
            startTime: resolvedStart,
            source: .vscode,
            // Each assistant turn = 1 premium request in VS Code Copilot Chat.
            // No exact billing data in transcript files; turn count is the best local proxy.
            credits: turnCount,
            turnCount: turnCount,
            modelBreakdown: [:]
        )
    }
}
