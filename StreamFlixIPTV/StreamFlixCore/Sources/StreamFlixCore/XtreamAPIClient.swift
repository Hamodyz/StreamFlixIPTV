import Foundation

public enum XtreamAPIError: LocalizedError, Sendable {
    case invalidURL
    case authenticationFailed(String)
    case networkError(String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server host URL. Check your Host address."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .decodingError(let reason):
            return "Failed to parse server response: \(reason)"
        }
    }
}

public actor XtreamAPIClient {
    private let session: URLSession
    public let credentials: XtreamCredentials

    public init(credentials: XtreamCredentials, session: URLSession? = nil) {
        self.credentials = credentials
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 60
            config.httpAdditionalHeaders = [
                "User-Agent": "StreamFlixIPTV/1.0 (Apple; SwiftUI)",
                "Accept": "application/json"
            ]
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Authentication

    public func authenticate() async throws -> XtreamAuthResponse {
        guard let url = credentials.playerAPIBaseURL else {
            throw XtreamAPIError.invalidURL
        }
        let response: XtreamAuthResponse = try await fetchJSON(url: url)
        guard response.userInfo.isActive else {
            throw XtreamAPIError.authenticationFailed(response.userInfo.status ?? "Inactive account")
        }
        return response
    }

    // MARK: - Catalog Fetching

    public func fetchLiveCategories() async throws -> [MediaCategory] {
        try await fetchAction("get_live_categories")
    }

    public func fetchLiveStreams(categoryId: String? = nil) async throws -> [LiveChannel] {
        var extra: [URLQueryItem] = []
        if let categoryId { extra.append(URLQueryItem(name: "category_id", value: categoryId)) }
        return try await fetchAction("get_live_streams", extraItems: extra)
    }

    public func fetchVODCategories() async throws -> [MediaCategory] {
        try await fetchAction("get_vod_categories")
    }

    public func fetchVODStreams(categoryId: String? = nil) async throws -> [VODMovie] {
        var extra: [URLQueryItem] = []
        if let categoryId { extra.append(URLQueryItem(name: "category_id", value: categoryId)) }
        return try await fetchAction("get_vod_streams", extraItems: extra)
    }

    public func fetchSeriesCategories() async throws -> [MediaCategory] {
        try await fetchAction("get_series_categories")
    }

    public func fetchSeries(categoryId: String? = nil) async throws -> [SeriesItem] {
        var extra: [URLQueryItem] = []
        if let categoryId { extra.append(URLQueryItem(name: "category_id", value: categoryId)) }
        return try await fetchAction("get_series", extraItems: extra)
    }

    public func fetchSeriesInfo(seriesId: Int) async throws -> SeriesInfoResponse {
        try await fetchAction(
            "get_series_info",
            extraItems: [URLQueryItem(name: "series_id", value: String(seriesId))]
        )
    }

    // MARK: - Stream URL Builders (Optimized for Apple Hardware)

    /// Prefers `.m3u8` (HLS) for Live TV because AVPlayer buffers and recovers much faster on HLS than raw `.ts`.
    public nonisolated func liveStreamURL(streamId: Int, preferHLS: Bool = true) -> URL? {
        let ext = preferHLS ? "m3u8" : "ts"
        return URL(string: "\(credentials.host)/live/\(credentials.username)/\(credentials.password)/\(streamId).\(ext)")
    }

    public nonisolated func movieStreamURL(streamId: Int, containerExtension: String?) -> URL? {
        let ext = (containerExtension?.isEmpty == false ? containerExtension! : "mp4")
        return URL(string: "\(credentials.host)/movie/\(credentials.username)/\(credentials.password)/\(streamId).\(ext)")
    }

    public nonisolated func episodeStreamURL(episodeId: String, containerExtension: String?) -> URL? {
        let ext = (containerExtension?.isEmpty == false ? containerExtension! : "mp4")
        return URL(string: "\(credentials.host)/series/\(credentials.username)/\(credentials.password)/\(episodeId).\(ext)")
    }

    public nonisolated func buildPlayableMovie(_ movie: VODMovie) -> PlayableItem? {
        guard let url = movieStreamURL(streamId: movie.streamId, containerExtension: movie.containerExtension) else {
            return nil
        }
        return PlayableItem(
            id: "movie-\(movie.streamId)",
            title: movie.name,
            subtitle: movie.rating.map { "★ \($0)" },
            artworkURL: movie.streamIcon,
            streamURL: url,
            kind: .movie
        )
    }

    public nonisolated func buildPlayableLive(_ channel: LiveChannel, preferHLS: Bool = true) -> PlayableItem? {
        guard let url = liveStreamURL(streamId: channel.streamId, preferHLS: preferHLS) else {
            return nil
        }
        return PlayableItem(
            id: "live-\(channel.streamId)",
            title: channel.name,
            subtitle: "LIVE",
            artworkURL: channel.streamIcon,
            streamURL: url,
            kind: .live
        )
    }

    /// Builds a PlayableItem for an episode and automatically attaches the next episode reference
    /// so Netflix-style Auto-Play & Sleep Guard know what comes next.
    public nonisolated func buildPlayableEpisode(
        series: SeriesItem,
        seasonNumber: Int,
        episodeIndex: Int,
        seasonEpisodes: [EpisodeItem],
        allSeasons: [Int: [EpisodeItem]]
    ) -> PlayableItem? {
        guard seasonEpisodes.indices.contains(episodeIndex) else { return nil }
        let episode = seasonEpisodes[episodeIndex]
        guard let url = episodeStreamURL(episodeId: episode.id, containerExtension: episode.containerExtension) else {
            return nil
        }

        let nextRef = findNextEpisode(
            series: series,
            seasonNumber: seasonNumber,
            episodeIndex: episodeIndex,
            seasonEpisodes: seasonEpisodes,
            allSeasons: allSeasons
        )

        return PlayableItem(
            id: "episode-\(episode.id)",
            title: "\(series.name) • S\(seasonNumber):E\(episode.displayEpisodeNumber)",
            subtitle: nil,
            artworkURL: episode.info?.movieImage ?? series.cover,
            streamURL: url,
            kind: .episode,
            seriesId: series.seriesId,
            seasonNumber: seasonNumber,
            episodeNumber: episode.displayEpisodeNumber,
            nextEpisode: nextRef
        )
    }

    private nonisolated func findNextEpisode(
        series: SeriesItem,
        seasonNumber: Int,
        episodeIndex: Int,
        seasonEpisodes: [EpisodeItem],
        allSeasons: [Int: [EpisodeItem]]
    ) -> PlayableItem.NextEpisodeRef? {
        if episodeIndex + 1 < seasonEpisodes.count {
            let nextEp = seasonEpisodes[episodeIndex + 1]
            if let nextURL = episodeStreamURL(episodeId: nextEp.id, containerExtension: nextEp.containerExtension) {
                return PlayableItem.NextEpisodeRef(
                    episodeId: nextEp.id,
                    title: "\(series.name) • S\(seasonNumber):E\(nextEp.displayEpisodeNumber)",
                    seasonNumber: seasonNumber,
                    episodeNumber: nextEp.displayEpisodeNumber,
                    streamURL: nextURL,
                    artworkURL: nextEp.info?.movieImage ?? series.cover
                )
            }
        } else {
            let sortedSeasons = allSeasons.keys.sorted()
            if let currentSeasonIdx = sortedSeasons.firstIndex(of: seasonNumber),
               currentSeasonIdx + 1 < sortedSeasons.count {
                let nextSeason = sortedSeasons[currentSeasonIdx + 1]
                if let firstEp = allSeasons[nextSeason]?.first,
                   let nextURL = episodeStreamURL(episodeId: firstEp.id, containerExtension: firstEp.containerExtension) {
                    return PlayableItem.NextEpisodeRef(
                        episodeId: firstEp.id,
                        title: "\(series.name) • S\(nextSeason):E\(firstEp.displayEpisodeNumber)",
                        seasonNumber: nextSeason,
                        episodeNumber: firstEp.displayEpisodeNumber,
                        streamURL: nextURL,
                        artworkURL: firstEp.info?.movieImage ?? series.cover
                    )
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func fetchAction<T: Decodable>(_ action: String, extraItems: [URLQueryItem] = []) async throws -> T {
        guard var components = URLComponents(string: "\(credentials.host)/player_api.php") else {
            throw XtreamAPIError.invalidURL
        }
        var items = [
            URLQueryItem(name: "username", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password),
            URLQueryItem(name: "action", value: action)
        ]
        items.append(contentsOf: extraItems)
        components.queryItems = items
        guard let url = components.url else {
            throw XtreamAPIError.invalidURL
        }
        return try await fetchJSON(url: url)
    }

    private func fetchJSON<T: Decodable>(url: URL) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw XtreamAPIError.networkError(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw XtreamAPIError.networkError("HTTP \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw XtreamAPIError.decodingError(error.localizedDescription)
        }
    }
}
