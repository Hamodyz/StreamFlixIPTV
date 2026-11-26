import Foundation

public struct AIRecommendationTitles: Codable, Sendable {
    public let trendingMovies: [String]
    public let trendingSeries: [String]
    public let trendingAnime: [String]
    public let forYouMovies: [String]
    public let forYouSeries: [String]
    public let forYouReason: String?
    public let fetchedAt: Date

    public init(
        trendingMovies: [String],
        trendingSeries: [String],
        trendingAnime: [String] = [],
        forYouMovies: [String],
        forYouSeries: [String],
        forYouReason: String?,
        fetchedAt: Date = Date()
    ) {
        self.trendingMovies = trendingMovies
        self.trendingSeries = trendingSeries
        self.trendingAnime = trendingAnime
        self.forYouMovies = forYouMovies
        self.forYouSeries = forYouSeries
        self.forYouReason = forYouReason
        self.fetchedAt = fetchedAt
    }
}

/// Fast, free, zero-key live curation powered by IMDb/Cinemeta & AniList public catalogs,
/// with optional AniList similarity recommendations based on what you watch.
public struct AIRecommendationsService: Sendable {
    private static let cacheKey = "StreamFlixIPTV.LiveCuratorCache.v2"
    private static let cacheTTL: TimeInterval = 6 * 3600 // 6 hours

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

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let anchorTitle = (watchedTitles.first ?? favoriteTitles.first)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        async let moviesTask = fetchCinemetaTop(type: "movie", session: session)
        async let seriesTask = fetchCinemetaTop(type: "series", session: session)
        async let animeTask = fetchAniListTrending(session: session)
        async let topRatedMoviesTask = fetchCinemetaTop(type: "movie", catalog: "imdbRating", session: session)
        async let similarAnimeTask = fetchAniListSimilar(searchTitle: anchorTitle, session: session)

        let (topMovies, topSeries, topAnime, ratedMovies, similarAnime) = await (
            moviesTask,
            seriesTask,
            animeTask,
            topRatedMoviesTask,
            similarAnimeTask
        )

        var forYouSeries = similarAnime
        let forYouReason = (anchorTitle != nil && !similarAnime.isEmpty)
            ? "Similar to \(anchorTitle!)"
            : "Top IMDb & Popular Picks"

        if forYouSeries.isEmpty {
            forYouSeries = Array(topSeries.shuffled().prefix(15))
        }
        let forYouMovies = Array((ratedMovies.isEmpty ? topMovies : ratedMovies).shuffled().prefix(15))

        let result = AIRecommendationTitles(
            trendingMovies: topMovies,
            trendingSeries: topSeries,
            trendingAnime: topAnime,
            forYouMovies: forYouMovies,
            forYouSeries: forYouSeries,
            forYouReason: forYouReason,
            fetchedAt: Date()
        )

        if !topMovies.isEmpty || !topSeries.isEmpty || !topAnime.isEmpty,
           let cacheData = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(cacheData, forKey: Self.cacheKey)
        }
        return result
    }

    // MARK: - Free IMDb/Cinemeta Public Catalogs (No Key, < 0.5s)

    private func fetchCinemetaTop(type: String, catalog: String = "top", session: URLSession) async -> [String] {
        guard let url = URL(string: "https://v3-cinemeta.strem.io/catalog/\(type)/\(catalog).json") else {
            return []
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode(CinemetaResponse.self, from: data)
            return decoded.metas.compactMap { meta in
                let name = meta.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : name
            }
        } catch {
            return []
        }
    }

    // MARK: - Free AniList Public GraphQL API (No Key, < 0.5s)

    private func fetchAniListTrending(session: URLSession) async -> [String] {
        let query = """
        query {
          Page(page: 1, perPage: 25) {
            media(type: ANIME, sort: TRENDING_DESC, isAdult: false) {
              title { english romaji }
            }
          }
        }
        """
        guard let response = await postAniList(query: query, variables: nil, session: session) else {
            return []
        }
        let media = response.data?.Page?.media ?? []
        return media.compactMap { item in
            let title = item.title?.english ?? item.title?.romaji
            return title?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func fetchAniListSimilar(searchTitle: String?, session: URLSession) async -> [String] {
        guard let raw = searchTitle, !raw.isEmpty else { return [] }
        let cleaned = OpenSubtitlesService.cleanSearchQuery(from: raw, kind: .episode).query
        guard cleaned.count >= 2 else { return [] }

        let query = """
        query ($search: String) {
          Media(search: $search, type: ANIME) {
            recommendations(sort: RATING_DESC, perPage: 20) {
              nodes {
                mediaRecommendation {
                  title { english romaji }
                }
              }
            }
          }
        }
        """
        guard let response = await postAniList(query: query, variables: ["search": cleaned], session: session) else {
            return []
        }
        let nodes = response.data?.Media?.recommendations?.nodes ?? []
        return nodes.compactMap { node in
            let t = node.mediaRecommendation?.title
            return (t?.english ?? t?.romaji)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func postAniList(query: String, variables: [String: String]?, session: URLSession) async -> AniListGraphQLResponse? {
        guard let url = URL(string: "https://graphql.anilist.co") else { return nil }
        var body: [String: Any] = ["query": query]
        if let variables { body["variables"] = variables }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(AniListGraphQLResponse.self, from: data)
        } catch {
            return nil
        }
    }
}

// MARK: - Public Catalog DTOs

private struct CinemetaResponse: Decodable {
    let metas: [Meta]
    struct Meta: Decodable {
        let name: String
    }
}

private struct AniListGraphQLResponse: Decodable {
    let data: DataNode?

    struct DataNode: Decodable {
        let Page: PageNode?
        let Media: MediaNode?
    }

    struct PageNode: Decodable {
        let media: [MediaItem]?
    }

    struct MediaNode: Decodable {
        let recommendations: RecommendationConnection?
    }

    struct RecommendationConnection: Decodable {
        let nodes: [RecommendationNode]?
    }

    struct RecommendationNode: Decodable {
        let mediaRecommendation: MediaItem?
    }

    struct MediaItem: Decodable {
        let title: TitleNode?
    }

    struct TitleNode: Decodable {
        let english: String?
        let romaji: String?
    }
}
