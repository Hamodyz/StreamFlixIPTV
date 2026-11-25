import Foundation

public enum SubtitleAITranslatorError: LocalizedError, Sendable {
    case missingGeminiKey
    case emptySubtitleFile
    case invalidResponse
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .missingGeminiKey:
            return "Gemini API Key is not set. Add it in Account → Subtitles."
        case .emptySubtitleFile:
            return "The downloaded subtitle file was empty or could not be parsed."
        case .invalidResponse:
            return "Gemini returned an unexpected response format."
        case .apiError(let message):
            return "AI Translation error: \(message)"
        }
    }
}

public struct SubtitleAITranslator: Sendable {
    private static let model = "gemini-3.8-flash"

    public init() {}

    public struct SRTCue: Sendable {
        public let index: String
        public let timing: String
        public let text: String
    }

    public static func parseSRT(_ content: String) -> [SRTCue] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SRTCue] = []
        cues.reserveCapacity(blocks.count)

        for block in blocks {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0) }
            guard lines.count >= 2 else { continue }

            // Handle optional BOM or missing index line
            if lines[0].contains("-->") {
                let timing = lines[0].trimmingCharacters(in: .whitespaces)
                let text = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    cues.append(SRTCue(index: String(cues.count + 1), timing: timing, text: text))
                }
            } else if lines.count >= 3, lines[1].contains("-->") {
                let idx = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let timing = lines[1].trimmingCharacters(in: .whitespaces)
                let text = lines.dropFirst(2).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    cues.append(SRTCue(index: idx, timing: timing, text: text))
                }
            }
        }
        return cues
    }

    public static func buildSRT(from cues: [SRTCue]) -> String {
        cues.enumerated().map { offset, cue in
            "\(offset + 1)\n\(cue.timing)\n\(cue.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    public func translateSRTFile(
        sourceURL: URL,
        fileId: Int,
        targetLanguage: SubtitleLanguage,
        geminiAPIKey: String,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let key = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SubtitleAITranslatorError.missingGeminiKey }

        let cacheURL = try cachedTranslatedURL(fileId: fileId, language: targetLanguage)
        if FileManager.default.fileExists(atPath: cacheURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > 0 {
            if let onProgress { await onProgress(1.0) }
            return cacheURL
        }

        let rawData = try Data(contentsOf: sourceURL)
        let rawString = String(data: rawData, encoding: .utf8)
            ?? String(data: rawData, encoding: .windowsCP1252)
            ?? String(decoding: rawData, as: UTF8.self)

        let cues = Self.parseSRT(rawString)
        guard !cues.isEmpty else { throw SubtitleAITranslatorError.emptySubtitleFile }

        let batchSize = 45
        var translatedCues = cues
        let totalBatches = Int(ceil(Double(cues.count) / Double(batchSize)))
        let maxConcurrent = 3
        var completedBatches = 0
        var nextBatch = 0

        try await withThrowingTaskGroup(of: (Int, [String]).self) { group in
            func enqueue(_ batchIdx: Int) {
                let start = batchIdx * batchSize
                let end = min(start + batchSize, cues.count)
                let sourceTexts = cues[start..<end].map(\.text)
                group.addTask {
                    let translated = try await self.translateBatch(
                        lines: sourceTexts,
                        targetLanguage: targetLanguage,
                        apiKey: key
                    )
                    return (batchIdx, translated)
                }
            }

            while nextBatch < min(maxConcurrent, totalBatches) {
                enqueue(nextBatch)
                nextBatch += 1
            }

            while let (batchIdx, translatedTexts) = try await group.next() {
                try Task.checkCancellation()
                let start = batchIdx * batchSize
                let end = min(start + batchSize, cues.count)
                for i in 0..<(end - start) {
                    let original = cues[start + i]
                    let candidate = i < translatedTexts.count ? translatedTexts[i] : ""
                    let finalText = candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? original.text : candidate
                    translatedCues[start + i] = SRTCue(
                        index: original.index,
                        timing: original.timing,
                        text: finalText
                    )
                }
                completedBatches += 1
                if let onProgress {
                    await onProgress(Double(completedBatches) / Double(totalBatches))
                }
                if nextBatch < totalBatches {
                    enqueue(nextBatch)
                    nextBatch += 1
                }
            }
        }

        let outputSRT = Self.buildSRT(from: translatedCues)
        try outputSRT.write(to: cacheURL, atomically: true, encoding: .utf8)
        return cacheURL
    }

    private func translateBatch(
        lines: [String],
        targetLanguage: SubtitleLanguage,
        apiKey: String
    ) async throws -> [String] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.model):generateContent") else {
            throw SubtitleAITranslatorError.invalidResponse
        }

        let inputJSONData = try JSONEncoder().encode(lines)
        let inputJSONString = String(data: inputJSONData, encoding: .utf8) ?? "[]"

        let languageInstruction: String
        switch targetLanguage {
        case .arabic:
            languageInstruction = "natural, fluent Arabic suitable for movie/anime subtitles (clear Modern Standard Arabic with natural dialogue flow, keeping names transliterated cleanly)"
        case .spanish:
            languageInstruction = "natural, fluent Spanish suitable for movie/anime subtitles"
        case .english:
            languageInstruction = "natural, fluent English suitable for movie/anime subtitles"
        }

        let prompt = """
        Translate the following array of \(lines.count) subtitle lines into \(languageInstruction).
        Rules:
        - Return ONLY a valid JSON array of strings with EXACTLY \(lines.count) elements in the exact same order.
        - Preserve line breaks (\\n) and HTML tags like <i>...</i> if present.
        - Do not merge, split, skip, or add any elements.

        Input JSON array:
        \(inputJSONString)
        """

        let body = GeminiGenerateRequest(
            contents: [.init(parts: [.init(text: prompt)])],
            generationConfig: .init(temperature: 0.2, responseMimeType: "application/json")
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let errMsg = (try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data))?.error.message
                ?? "HTTP \(http.statusCode)"
            throw SubtitleAITranslatorError.apiError(errMsg)
        }

        let decoded = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)
        guard let rawText = decoded.candidates?.first?.content?.parts?.first?.text else {
            throw SubtitleAITranslatorError.invalidResponse
        }

        // Strip potential markdown fences just in case
        let cleanedJSON = rawText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanedJSON.data(using: .utf8),
              let translatedArray = try? JSONDecoder().decode([String].self, from: jsonData) else {
            throw SubtitleAITranslatorError.invalidResponse
        }
        return translatedArray
    }

    private func cachedTranslatedURL(fileId: Int, language: SubtitleLanguage) throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("OpenSubtitles", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("ai_\(fileId)_\(language.rawValue).srt")
    }
}

// MARK: - Gemini REST DTOs

private struct GeminiGenerateRequest: Encodable {
    let contents: [Content]
    let generationConfig: GenerationConfig

    struct Content: Encodable {
        let parts: [Part]
    }

    struct Part: Encodable {
        let text: String
    }

    struct GenerationConfig: Encodable {
        let temperature: Double
        let responseMimeType: String
    }
}

private struct GeminiGenerateResponse: Decodable {
    let candidates: [Candidate]?

    struct Candidate: Decodable {
        let content: Content?
    }

    struct Content: Decodable {
        let parts: [Part]?
    }

    struct Part: Decodable {
        let text: String?
    }
}

private struct GeminiErrorEnvelope: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
    }
}
