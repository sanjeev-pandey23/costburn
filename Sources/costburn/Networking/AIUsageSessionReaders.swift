import Foundation

struct ClaudeSessionReader: Sendable {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func readSessions(since: Date) async -> [AIUsageSessionRecord] {
        let projectsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        var samplesByRequest: [String: ClaudeUsageSample] = [:]

        for fileURL in LocalJSONL.files(under: projectsURL, modifiedSince: since) {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            for (lineIndex, line) in content.components(separatedBy: "\n").enumerated() {
                guard let sample = parseUsageSample(
                    line: line,
                    fileURL: fileURL,
                    lineIndex: lineIndex,
                    since: since
                ) else { continue }

                if let existing = samplesByRequest[sample.deduplicationKey] {
                    if sample.shouldReplace(existing) {
                        samplesByRequest[sample.deduplicationKey] = sample
                    }
                } else {
                    samplesByRequest[sample.deduplicationKey] = sample
                }
            }
        }

        return Dictionary(grouping: samplesByRequest.values, by: \.sessionId)
            .map { sessionId, samples in
                AIUsageSessionRecord(
                    sessionId: sessionId,
                    startTime: samples.map(\.timestamp).min() ?? Date(),
                    provider: .claude,
                    source: .claudeCode,
                    credits: 0,
                    turnCount: samples.count,
                    modelBreakdown: UsageBucket.modelBreakdown(from: samples),
                    estimatedCost: samples.reduce(0) { $0 + $1.usage.estimatedCost }
                )
            }
            .sorted { $0.startTime > $1.startTime }
    }

    private func parseUsageSample(
        line: String,
        fileURL: URL,
        lineIndex: Int,
        since: Date
    ) -> ClaudeUsageSample? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.contains("\"usage\""),
              let data = trimmed.data(using: .utf8),
              let decoded = try? decoder.decode(ClaudeTranscriptLine.self, from: data),
              decoded.type == "assistant",
              let usage = decoded.message?.usage else {
            return nil
        }

        let timestamp = DateParsing.isoDate(from: decoded.timestamp) ?? Date.distantPast
        guard timestamp >= since else { return nil }

        let model = decoded.message?.model ?? "Claude"
        let nestedFiveMinute = usage.cacheCreation?.ephemeralFiveMinuteInputTokens ?? 0
        let nestedOneHour = usage.cacheCreation?.ephemeralOneHourInputTokens ?? 0
        let aggregateCacheCreation = usage.cacheCreationInputTokens ?? (nestedFiveMinute + nestedOneHour)
        let unclassifiedCacheCreation = max(aggregateCacheCreation - nestedFiveMinute - nestedOneHour, 0)
        let cacheCreationFiveMinute = nestedFiveMinute + unclassifiedCacheCreation
        let cacheCreationOneHour = nestedOneHour
        let inputTokens = usage.inputTokens ?? 0
        let outputTokens = usage.outputTokens ?? 0
        let cacheReadTokens = usage.cacheReadInputTokens ?? 0
        let cost = AIUsagePricing.estimatedCost(
            provider: .claude,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationFiveMinuteTokens: cacheCreationFiveMinute,
            cacheCreationOneHourTokens: cacheCreationOneHour,
            cacheReadTokens: cacheReadTokens,
            explicitCost: decoded.costUSD
        )

        let requestKey = decoded.requestId
            ?? decoded.message?.id
            ?? decoded.uuid
            ?? "\(fileURL.path)#\(lineIndex)"

        return ClaudeUsageSample(
            deduplicationKey: "\(fileURL.path)#\(requestKey)",
            sessionId: decoded.sessionId ?? fileURL.deletingLastPathComponent().lastPathComponent,
            model: model,
            timestamp: timestamp,
            usage: AIModelUsage(
                requestCount: 1,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: aggregateCacheCreation,
                cacheCreationFiveMinuteTokens: cacheCreationFiveMinute,
                cacheCreationOneHourTokens: cacheCreationOneHour,
                cacheReadTokens: cacheReadTokens,
                estimatedCost: cost
            ),
            totalBillableTokens: inputTokens + outputTokens + aggregateCacheCreation + cacheReadTokens
        )
    }
}

struct CodexSessionReader: Sendable {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func readSessions(since: Date) async -> [AIUsageSessionRecord] {
        let sessionsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")

        return LocalJSONL.files(under: sessionsURL, modifiedSince: since)
            .compactMap { parseSession(fileURL: $0, since: since) }
            .sorted { $0.startTime > $1.startTime }
    }

    private func parseSession(fileURL: URL, since: Date) -> AIUsageSessionRecord? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileModificationDate = (attrs?[.modificationDate] as? Date) ?? Date.distantPast

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }

        var currentModel = "Codex"
        var firstUsageDate: Date?
        var turnCount = 0
        var modelBuckets: [String: UsageBucket] = [:]

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let decoded = try? decoder.decode(CodexLogLine.self, from: data) else {
                continue
            }

            if decoded.type == "turn_context", let model = decoded.payload?.model, !model.isEmpty {
                currentModel = model
                continue
            }

            guard decoded.type == "event_msg",
                  decoded.payload?.type == "token_count",
                  let tokenUsage = decoded.payload?.info?.lastTokenUsage else {
                continue
            }

            let usageDate = DateParsing.isoDate(from: decoded.timestamp) ?? fileModificationDate
            guard usageDate >= since else { continue }

            let cachedInputTokens = tokenUsage.cachedInputTokens ?? 0
            let inputTokens = max((tokenUsage.inputTokens ?? 0) - cachedInputTokens, 0)
            let outputTokens = tokenUsage.outputTokens ?? 0
            let reasoningTokens = tokenUsage.reasoningOutputTokens ?? 0
            let cost = AIUsagePricing.estimatedCost(
                provider: .codex,
                model: currentModel,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cachedInputTokens
            )
            let usage = AIModelUsage(
                requestCount: 1,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cachedInputTokens,
                reasoningTokens: reasoningTokens,
                estimatedCost: cost
            )

            modelBuckets[currentModel, default: UsageBucket()].add(usage)
            firstUsageDate = min(firstUsageDate ?? usageDate, usageDate)
            turnCount += 1
        }

        guard turnCount > 0 else { return nil }

        let modelBreakdown = modelBuckets.mapValues(\.usage)
        return AIUsageSessionRecord(
            sessionId: fileURL.deletingPathExtension().lastPathComponent,
            startTime: firstUsageDate ?? fileModificationDate,
            provider: .codex,
            source: .codexCLI,
            credits: 0,
            turnCount: turnCount,
            modelBreakdown: modelBreakdown,
            estimatedCost: modelBreakdown.values.reduce(0) { $0 + $1.estimatedCost }
        )
    }
}

private struct ClaudeUsageSample {
    let deduplicationKey: String
    let sessionId: String
    let model: String
    let timestamp: Date
    let usage: AIModelUsage
    let totalBillableTokens: Int

    func shouldReplace(_ existing: ClaudeUsageSample) -> Bool {
        if totalBillableTokens != existing.totalBillableTokens {
            return totalBillableTokens > existing.totalBillableTokens
        }
        return timestamp >= existing.timestamp
    }
}

private struct UsageBucket {
    var requestCount = 0
    var creditCost = 0
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationTokens = 0
    var cacheCreationFiveMinuteTokens = 0
    var cacheCreationOneHourTokens = 0
    var cacheReadTokens = 0
    var reasoningTokens = 0
    var estimatedCost: Double = 0

    mutating func add(_ usage: AIModelUsage) {
        requestCount += usage.requestCount
        creditCost += usage.creditCost
        inputTokens += usage.inputTokens
        outputTokens += usage.outputTokens
        cacheCreationTokens += usage.cacheCreationTokens
        cacheCreationFiveMinuteTokens += usage.cacheCreationFiveMinuteTokens
        cacheCreationOneHourTokens += usage.cacheCreationOneHourTokens
        cacheReadTokens += usage.cacheReadTokens
        reasoningTokens += usage.reasoningTokens
        estimatedCost += usage.estimatedCost
    }

    var usage: AIModelUsage {
        AIModelUsage(
            requestCount: requestCount,
            creditCost: creditCost,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheCreationFiveMinuteTokens: cacheCreationFiveMinuteTokens,
            cacheCreationOneHourTokens: cacheCreationOneHourTokens,
            cacheReadTokens: cacheReadTokens,
            reasoningTokens: reasoningTokens,
            estimatedCost: estimatedCost
        )
    }

    static func modelBreakdown(from samples: [ClaudeUsageSample]) -> [String: AIModelUsage] {
        var buckets: [String: UsageBucket] = [:]
        for sample in samples {
            buckets[sample.model, default: UsageBucket()].add(sample.usage)
        }
        return buckets.mapValues(\.usage)
    }
}

private enum LocalJSONL {
    static func files(under root: URL, modifiedSince since: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile != false else { continue }
            if let modified = values?.contentModificationDate, modified < since {
                continue
            }
            files.append(fileURL)
        }
        return files
    }
}

private enum DateParsing {
    static func isoDate(from value: String?) -> Date? {
        guard let value else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

private struct ClaudeTranscriptLine: Decodable {
    let parentUuid: String?
    let message: ClaudeMessage?
    let requestId: String?
    let type: String?
    let uuid: String?
    let timestamp: String?
    let sessionId: String?
    let costUSD: Double?

    enum CodingKeys: String, CodingKey {
        case parentUuid
        case message
        case requestId
        case type
        case uuid
        case timestamp
        case sessionId
        case costUSD
    }
}

private struct ClaudeMessage: Decodable {
    let id: String?
    let model: String?
    let usage: ClaudeUsage?
}

private struct ClaudeUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreation: ClaudeCacheCreation?
}

private struct ClaudeCacheCreation: Decodable {
    let ephemeralFiveMinuteInputTokens: Int?
    let ephemeralOneHourInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case ephemeralFiveMinuteInputTokens = "ephemeral_5m_input_tokens"
        case ephemeralOneHourInputTokens = "ephemeral_1h_input_tokens"
    }
}

private struct CodexLogLine: Decodable {
    let timestamp: String?
    let type: String
    let payload: CodexPayload?
}

private struct CodexPayload: Decodable {
    let type: String?
    let info: CodexTokenInfo?
    let model: String?
}

private struct CodexTokenInfo: Decodable {
    let lastTokenUsage: CodexTokenUsage?
}

private struct CodexTokenUsage: Decodable {
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?
    let reasoningOutputTokens: Int?
    let totalTokens: Int?
}
