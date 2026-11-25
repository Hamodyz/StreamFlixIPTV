import Foundation

public struct AIRecommendationTitles: Codable, Sendable {
    public let trendingMovies: [String]
    public let trendingSeries: [String]
    public let forYouMovies: [String]
    public let forYouSeries: [String]
    public let forYouReason: String?
    public let fetchedAt: Date

    public init(
        trendingMovies: [String],
        trendingSeries: [String],
        forYouMovies: [String],
        forYouSeries: [String],
        forYouReason: String?,
        fetchedAt: Date = Date()
    ) {
        self.trendingMovies = trendingMovies
        self.trendingSeries = trendingSeries
        self.forYouMovies = forYouMovies
        self.forYouSeries = forYouSeries
        self.forYouReason = forYouReason
        self.fetchedAt = fetchedAt
    }
}

public struct AIRecommendationsService: Sendable {
    private static let model = "gemini-2.5-flash"
    private static let cacheKey = "StreamFlixIPTV.AICuratorCache.v1"
    private static let cacheTTL: TimeInterval = 12 * 3600 // 12 hours

    public init() {}

    public func loadCachedIfFresh() -> AIRecommendationTitles? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let decoded = try? JSONDecoder().decode(AIRecommendationTitles.self, from: data) else {
            return nil
        }
        if Date().timeIntervalSince(decoded.fetchedAt) < Self.cacheTTL {
            return decoded
        }
        return nil
    }

    public func clearCache() {
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
    }

    public func fetchRecommendations(
        geminiAPIKey: String,
        watchedTitles: [String],
        favoriteTitles: [String],
        forceRefresh: Bool = false
    ) async throws -> AIRecommendationTitles {
        if !forceRefresh, let cached = loadCachedIfFresh() {
            return cached
        }

        let key = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw SubtitleAITranslatorError.missingGeminiKey
        }

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.model):generateContent") else {
            throw SubtitleAITranslatorError.invalidResponse
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: Date())

        let watchedSummary = watchedTitles.prefix(10).joined(separator: ", ")
        let favSummary = favoriteTitles.prefix(10).joined(separator: ", ")

        let prompt = """
        Today is \(todayString). You are a movie and TV curator for an IPTV streaming app.
        User's recently watched titles: \(watchedSummary.isEmpty ? "None yet" : watchedSummary)
        User's favorite titles (My List): \(favSummary.isEmpty ? "None yet" : favSummary)

        Return ONLY a valid JSON object with these exact keys:
        {
          "trendingMovies": [25 popular, trending, and top-rated movies right now (mix of 2024-2026 hits and all-time crowd-pleasers)],
          "trendingSeries": [25 popular, trending, and top-rated TV series and anime right now],
          "forYouMovies": [20 movies specifically similar in genre/vibe to the user's watched & favorite titles (or top diverse hits if none)],
          "forYouSeries": [20 series/anime specifically similar in genre/vibe to the user's watched & favorite titles (or top diverse hits if none)],
          "forYouReason": "A short 3-6 word label like 'Because you watch Anime & Action' or 'Top Picks for You'"
        }

        Rules:
        - Use clean, standard English titles (no years, no extra tags like 4K or HD) so they can be matched against a media catalog.
        - Output ONLY raw JSON.
        """

        let body = GeminiCuratorRequest(
            contents: [.init(parts: [.init(text: prompt)])],
            generationConfig: .init(temperature: 0.7, responseMimeType: "application/json")
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode(GeminiCuratorErrorEnvelope.self, from: data))?.error.message ?? "HTTP \(http.statusCode)"
            throw SubtitleAITranslatorError.apiError(msg)
        }

        let decoded = try JSONDecoder().decode(GeminiCuratorResponse.self, from: data)
        guard let rawText = decoded.candidates?.first?.content?.parts?.first?.text else {
            throw SubtitleAITranslatorError.invalidResponse
        }

        let cleanedJSON = rawText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            throw SubtitleAITranslatorError.invalidResponse
        }

        let parsed = try JSONDecoder().decode(AIRecommendationPayload.self, from: jsonData)
        let result = AIRecommendationTitles(
            trendingMovies: parsed.trendingMovies ?? [],
            trendingSeries: parsed.trendingSeries ?? [],
            forYouMovies: parsed.forYouMovies ?? [],
            forYouSeries: parsed.forYouSeries ?? [],
            forYouReason: parsed.forYouReason,
            fetchedAt: Date()
        )

        if let cacheData = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(cacheData, forKey: Self.cacheKey)
        }
        return result
    }
}

private struct GeminiCuratorRequest: Encodable {
    let contents: [Content]
    let generationConfig: GenerationConfig

    struct Content: Encodable { let parts: [Part] }
    struct Part: Encodable { let text: String }
    struct GenerationConfig: Encodable {
        let temperature: Double
        let responseMimeType: String
    }
}

private struct GeminiCuratorResponse: Decodable {
    let candidates: [Candidate]?
    struct Candidate: Decodable { let content: Content? }
    struct Content: Decodable { let parts: [Part]? }
    struct Part: Decodable { let text: String? }
}

private struct AIRecommendationPayload: Decodable {
    let trendingMovies: [String]?
    let trendingSeries: [String]?
    let forYouMovies: [String]?
    let forYouSeries: [String]?
    let forYouReason: String?
}

private struct GeminiCuratorErrorEnvelope: Decodable {
    let error: ErrorDetail
    struct ErrorDetail: Decodable {
        let message: String
    }
}
