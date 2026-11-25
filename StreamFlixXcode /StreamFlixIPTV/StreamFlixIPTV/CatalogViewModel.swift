import Foundation
import SwiftUI
import Combine
import StreamFlixCore

@MainActor
public final class CatalogViewModel: ObservableObject {
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var authInfo: XtreamAuthResponse?

    @Published public var liveCategories: [MediaCategory] = []
    @Published public var liveChannels: [LiveChannel] = []

    @Published public var vodCategories: [MediaCategory] = []
    @Published public var movies: [VODMovie] = []

    @Published public var seriesCategories: [MediaCategory] = []
    @Published public var seriesList: [SeriesItem] = []

    @Published public var searchQuery: String = ""
    @Published public var activePlayerItem: PlayableItem?
    @Published public var activeLiveChannelList: [LiveChannel] = []
    @Published public var currentLiveChannel: LiveChannel?

    // Favorites ("My List") persisted in UserDefaults
    @Published public var favoriteSeriesIds: Set<Int> = []
    @Published public var favoriteMovieIds: Set<Int> = []
    @Published public var favoriteChannelIds: Set<Int> = []

    private(set) var apiClient: XtreamAPIClient?
    private var lastCredentials: XtreamCredentials?
    public var onFavoritesChanged: (() -> Void)?

    private let favSeriesKey = "StreamFlixIPTV.FavSeries.v1"
    private let favMoviesKey = "StreamFlixIPTV.FavMovies.v1"
    private let favChannelsKey = "StreamFlixIPTV.FavChannels.v1"

    public init() {
        loadFavorites()
    }

    public func reload() async {
        guard let creds = lastCredentials else { return }
        seriesInfoCache.removeAll()
        await loadAll(credentials: creds)
    }

    public func loadAll(credentials: XtreamCredentials) async {
        lastCredentials = credentials
        isLoading = true
        errorMessage = nil
        let client = XtreamAPIClient(credentials: credentials)
        self.apiClient = client

        do {
            let auth = try await client.authenticate()
            self.authInfo = auth
        } catch {
            self.errorMessage = error.localizedDescription
            isLoading = false
            return
        }

        async let lcTask: [MediaCategory]? = try? await client.fetchLiveCategories()
        async let lTask: [LiveChannel]? = try? await client.fetchLiveStreams()
        async let vcTask: [MediaCategory]? = try? await client.fetchVODCategories()
        async let vTask: [VODMovie]? = try? await client.fetchVODStreams()
        async let scTask: [MediaCategory]? = try? await client.fetchSeriesCategories()
        async let sTask: [SeriesItem]? = try? await client.fetchSeries()

        let (lc, l, vc, v, sc, s) = await (lcTask, lTask, vcTask, vTask, scTask, sTask)
        self.liveCategories = lc ?? []
        self.liveChannels = l ?? []
        self.vodCategories = vc ?? []
        self.movies = v ?? []
        self.seriesCategories = sc ?? []
        self.seriesList = s ?? []

        // Pre-index categories, normalized search titles, and Trending once (avoids lag on UI renders & typing)
        self.channelsByCategory = Dictionary(grouping: self.liveChannels, by: { $0.categoryId ?? "" })
        self.moviesByCategory = Dictionary(grouping: self.movies, by: { $0.categoryId ?? "" })
        self.seriesByCategory = Dictionary(grouping: self.seriesList, by: { $0.categoryId ?? "" })
        self.normalizedChannels = self.liveChannels.map { ($0, Self.normalizeText($0.name)) }
        self.normalizedMovies = self.movies.map { ($0, Self.normalizeText($0.name)) }
        self.normalizedSeries = self.seriesList.map { ($0, Self.normalizeText($0.name)) }

        self.trendingMovies = self.movies
            .filter { !($0.streamIcon ?? "").isEmpty }
            .sorted { lhs, rhs in
                let lScore = (Double(lhs.rating ?? "0") ?? 0) * 1000 + (Double(lhs.added ?? "0") ?? 0) / 1_000_000_000
                let rScore = (Double(rhs.rating ?? "0") ?? 0) * 1000 + (Double(rhs.added ?? "0") ?? 0) / 1_000_000_000
                return lScore > rScore
            }
            .prefix(20)
            .map { $0 }

        self.trendingSeries = self.seriesList
            .filter { !($0.cover ?? "").isEmpty }
            .sorted { lhs, rhs in
                (Double(lhs.rating ?? "0") ?? 0) > (Double(rhs.rating ?? "0") ?? 0)
            }
            .prefix(20)
            .map { $0 }

        if liveChannels.isEmpty && movies.isEmpty && seriesList.isEmpty {
            errorMessage = "Connected to server, but no channels, movies, or series were returned."
        }
        isLoading = false
    }

    // MARK: - Favorites ("My List")

    public var favoriteSeriesItems: [SeriesItem] {
        seriesList.filter { favoriteSeriesIds.contains($0.seriesId) }
    }

    public var favoriteMovies: [VODMovie] {
        movies.filter { favoriteMovieIds.contains($0.streamId) }
    }

    public var favoriteChannels: [LiveChannel] {
        liveChannels.filter { favoriteChannelIds.contains($0.streamId) }
    }

    public func isFavorite(seriesId: Int) -> Bool { favoriteSeriesIds.contains(seriesId) }
    public func isFavorite(movieId: Int) -> Bool { favoriteMovieIds.contains(movieId) }
    public func isFavorite(channelId: Int) -> Bool { favoriteChannelIds.contains(channelId) }

    public func toggleFavoriteSeries(_ id: Int) {
        if favoriteSeriesIds.contains(id) { favoriteSeriesIds.remove(id) } else { favoriteSeriesIds.insert(id) }
        saveFavorites()
    }

    public func toggleFavoriteMovie(_ id: Int) {
        if favoriteMovieIds.contains(id) { favoriteMovieIds.remove(id) } else { favoriteMovieIds.insert(id) }
        saveFavorites()
    }

    public func toggleFavoriteChannel(_ id: Int) {
        if favoriteChannelIds.contains(id) { favoriteChannelIds.remove(id) } else { favoriteChannelIds.insert(id) }
        saveFavorites()
    }

    private func loadFavorites() {
        if let arr = UserDefaults.standard.array(forKey: favSeriesKey) as? [Int] { favoriteSeriesIds = Set(arr) }
        if let arr = UserDefaults.standard.array(forKey: favMoviesKey) as? [Int] { favoriteMovieIds = Set(arr) }
        if let arr = UserDefaults.standard.array(forKey: favChannelsKey) as? [Int] { favoriteChannelIds = Set(arr) }
    }

    public func applyMergedFavorites(series: Set<Int>, movies: Set<Int>, channels: Set<Int>) {
        favoriteSeriesIds = series
        favoriteMovieIds = movies
        favoriteChannelIds = channels
        UserDefaults.standard.set(Array(favoriteSeriesIds), forKey: favSeriesKey)
        UserDefaults.standard.set(Array(favoriteMovieIds), forKey: favMoviesKey)
        UserDefaults.standard.set(Array(favoriteChannelIds), forKey: favChannelsKey)
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteSeriesIds), forKey: favSeriesKey)
        UserDefaults.standard.set(Array(favoriteMovieIds), forKey: favMoviesKey)
        UserDefaults.standard.set(Array(favoriteChannelIds), forKey: favChannelsKey)
        onFavoritesChanged?()
    }

    // MARK: - Featured & Cached Trending

    @Published public private(set) var trendingMovies: [VODMovie] = []
    @Published public private(set) var trendingSeries: [SeriesItem] = []
    @Published public private(set) var forYouMovies: [VODMovie] = []
    @Published public private(set) var forYouSeries: [SeriesItem] = []
    @Published public private(set) var forYouTitle: String = "Recommended for You ✨"
    @Published public private(set) var isRefreshingAI = false
    @Published public var aiStatusMessage: String?

    private var channelsByCategory: [String: [LiveChannel]] = [:]
    private var moviesByCategory: [String: [VODMovie]] = [:]
    private var seriesByCategory: [String: [SeriesItem]] = [:]
    private var normalizedChannels: [(LiveChannel, String)] = []
    private var normalizedMovies: [(VODMovie, String)] = []
    private var normalizedSeries: [(SeriesItem, String)] = []

    public var featuredMovie: VODMovie? {
        trendingMovies.first ?? movies.first(where: { ($0.streamIcon ?? "").isEmpty == false }) ?? movies.first
    }

    public func movies(for categoryId: String) -> [VODMovie] {
        moviesByCategory[categoryId] ?? []
    }

    public func series(for categoryId: String) -> [SeriesItem] {
        seriesByCategory[categoryId] ?? []
    }

    public func channels(for categoryId: String) -> [LiveChannel] {
        channelsByCategory[categoryId] ?? []
    }

    // MARK: - AI Dynamic Trending & Personalized Recommendations

    public func refreshAICuration(watchedTitles: [String], forceRefresh: Bool = false) async {
        guard !movies.isEmpty || !seriesList.isEmpty else { return }
        let settings = OpenSubtitlesSettings.shared
        let favTitles = favoriteSeriesItems.map(\.name) + favoriteMovies.map(\.name)
        aiStatusMessage = nil

        guard settings.isGeminiConfigured else {
            // Fallback without Gemini key: rotate a fresh mix of recent + top-rated items
            let recentMovies = movies.filter { !($0.streamIcon ?? "").isEmpty }
                .sorted { (Double($0.added ?? "0") ?? 0) > (Double($1.added ?? "0") ?? 0) }
                .prefix(80)
                .shuffled()
            if !recentMovies.isEmpty {
                self.trendingMovies = Array(recentMovies.prefix(20))
            }
            let topSeriesPool = seriesList.filter { !($0.cover ?? "").isEmpty }
                .sorted { (Double($0.rating ?? "0") ?? 0) > (Double($1.rating ?? "0") ?? 0) }
                .prefix(80)
                .shuffled()
            if !topSeriesPool.isEmpty {
                self.trendingSeries = Array(topSeriesPool.prefix(20))
            }
            if forceRefresh {
                aiStatusMessage = "Trending rotated! Add your free Gemini API Key in Account → Subtitles & AI Translation for personalized AI Picks."
            }
            return
        }

        isRefreshingAI = true
        defer { isRefreshingAI = false }

        do {
            let ai = try await AIRecommendationsService().fetchRecommendations(
                geminiAPIKey: settings.trimmedGeminiAPIKey,
                watchedTitles: watchedTitles,
                favoriteTitles: favTitles,
                forceRefresh: forceRefresh
            )

            let matchedTrendingMovies = matchMovies(titles: ai.trendingMovies, limit: 20)
            if !matchedTrendingMovies.isEmpty {
                self.trendingMovies = topUpMovies(matchedTrendingMovies, from: self.trendingMovies, limit: 20)
            }

            let matchedTrendingSeries = matchSeries(titles: ai.trendingSeries, limit: 20)
            if !matchedTrendingSeries.isEmpty {
                self.trendingSeries = topUpSeries(matchedTrendingSeries, from: self.trendingSeries, limit: 20)
            }

            self.forYouMovies = matchMovies(titles: ai.forYouMovies, limit: 20)
            self.forYouSeries = matchSeries(titles: ai.forYouSeries, limit: 20)
            if let reason = ai.forYouReason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.forYouTitle = "\(reason) ✨"
            }
            if forceRefresh {
                aiStatusMessage = "✨ AI updated: \(matchedTrendingMovies.count) trending movies, \(matchedTrendingSeries.count) series, \(forYouMovies.count + forYouSeries.count) picks for you."
            }
        } catch {
            aiStatusMessage = "AI Picks error: \(error.localizedDescription)"
        }
    }

    private static func looseMatchKey(_ text: String) -> String {
        let normalized = normalizeText(text)
        let cleaned = normalized.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(cleaned)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func matchMovies(titles: [String], limit: Int) -> [VODMovie] {
        var seen = Set<Int>()
        var matched: [VODMovie] = []
        for rawTitle in titles {
            let q = Self.normalizeText(rawTitle)
            let looseQ = Self.looseMatchKey(rawTitle)
            guard q.count >= 2 else { continue }
            if let hit = normalizedMovies.first(where: { $0.1 == q || Self.looseMatchKey($0.1) == looseQ })?.0
                ?? normalizedMovies.first(where: { ($0.1.contains(q) || Self.looseMatchKey($0.1).contains(looseQ)) && !($0.0.streamIcon ?? "").isEmpty })?.0 {
                if seen.insert(hit.streamId).inserted {
                    matched.append(hit)
                    if matched.count >= limit { break }
                }
            }
        }
        return matched
    }

    private func matchSeries(titles: [String], limit: Int) -> [SeriesItem] {
        var seen = Set<Int>()
        var matched: [SeriesItem] = []
        for rawTitle in titles {
            let q = Self.normalizeText(rawTitle)
            let looseQ = Self.looseMatchKey(rawTitle)
            guard q.count >= 2 else { continue }
            if let hit = normalizedSeries.first(where: { $0.1 == q || Self.looseMatchKey($0.1) == looseQ })?.0
                ?? normalizedSeries.first(where: { ($0.1.contains(q) || Self.looseMatchKey($0.1).contains(looseQ)) && !($0.0.cover ?? "").isEmpty })?.0 {
                if seen.insert(hit.seriesId).inserted {
                    matched.append(hit)
                    if matched.count >= limit { break }
                }
            }
        }
        return matched
    }

    private func topUpMovies(_ primary: [VODMovie], from fallback: [VODMovie], limit: Int) -> [VODMovie] {
        var result = primary
        var seen = Set(primary.map(\.streamId))
        for item in fallback where seen.insert(item.streamId).inserted {
            result.append(item)
            if result.count >= limit { break }
        }
        return result
    }

    private func topUpSeries(_ primary: [SeriesItem], from fallback: [SeriesItem], limit: Int) -> [SeriesItem] {
        var result = primary
        var seen = Set(primary.map(\.seriesId))
        for item in fallback where seen.insert(item.seriesId).inserted {
            result.append(item)
            if result.count >= limit { break }
        }
        return result
    }

    // MARK: - Instant Universal Search (Arabic + English Normalized)

    public static func normalizeText(_ text: String) -> String {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        result.reserveCapacity(lower.count)
        for scalar in lower.unicodeScalars {
            if (0x064B...0x065F).contains(scalar.value) || scalar.value == 0x0640 || scalar.value == 0x0670 {
                continue
            }
            switch scalar.value {
            case 0x0622, 0x0623, 0x0625, 0x0671: // آ أ إ ٱ -> ا
                result.append("\u{0627}")
            case 0x0649: // ى -> ي
                result.append("\u{064A}")
            case 0x0629: // ة -> ه
                result.append("\u{0647}")
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    public func normalize(_ text: String) -> String {
        Self.normalizeText(text)
    }

    public func matches(_ title: String, query: String) -> Bool {
        let q = Self.normalizeText(query)
        guard !q.isEmpty else { return true }
        return Self.normalizeText(title).contains(q)
    }

    public var filteredChannels: [LiveChannel] {
        let q = Self.normalizeText(searchQuery)
        guard !q.isEmpty else { return liveChannels }
        return normalizedChannels.compactMap { $0.1.contains(q) ? $0.0 : nil }
    }

    public var filteredMovies: [VODMovie] {
        let q = Self.normalizeText(searchQuery)
        guard !q.isEmpty else { return movies }
        return normalizedMovies.compactMap { $0.1.contains(q) ? $0.0 : nil }
    }

    public var filteredSeries: [SeriesItem] {
        let q = Self.normalizeText(searchQuery)
        guard !q.isEmpty else { return seriesList }
        return normalizedSeries.compactMap { $0.1.contains(q) ? $0.0 : nil }
    }

    // MARK: - Playback

    public func playMovie(_ movie: VODMovie) {
        currentLiveChannel = nil
        activePlayerItem = apiClient?.buildPlayableMovie(movie)
    }

    public func playChannel(_ channel: LiveChannel, in list: [LiveChannel]? = nil, preferHLS: Bool = true) {
        if let list, !list.isEmpty {
            activeLiveChannelList = list
        } else if activeLiveChannelList.isEmpty {
            activeLiveChannelList = liveChannels
        }
        currentLiveChannel = channel
        activePlayerItem = apiClient?.buildPlayableLive(channel, preferHLS: preferHLS)
    }

    private var seriesInfoCache: [Int: SeriesInfoResponse] = [:]

    public func fetchEpisodesBySeason(seriesId: Int) async -> [Int: [EpisodeItem]] {
        let info: SeriesInfoResponse
        if let cached = seriesInfoCache[seriesId] {
            info = cached
        } else {
            guard let apiClient,
                  let fetched = try? await apiClient.fetchSeriesInfo(seriesId: seriesId) else { return [:] }
            seriesInfoCache[seriesId] = fetched
            info = fetched
        }
        var allSeasons: [Int: [EpisodeItem]] = [:]
        for (k, eps) in (info.episodes ?? [:]) {
            if let sNum = Int(k) {
                allSeasons[sNum] = eps.sorted { $0.episodeNum < $1.episodeNum }
            }
        }
        return allSeasons
    }

    public func playEpisode(
        seriesId: Int,
        fallbackTitle: String,
        fallbackArtwork: String?,
        seasonNumber: Int,
        episodeIndex: Int,
        allSeasons: [Int: [EpisodeItem]]
    ) {
        guard let apiClient else { return }
        if let series = seriesList.first(where: { $0.seriesId == seriesId }),
           let playable = apiClient.buildPlayableEpisode(
               series: series,
               seasonNumber: seasonNumber,
               episodeIndex: episodeIndex,
               seasonEpisodes: allSeasons[seasonNumber] ?? [],
               allSeasons: allSeasons
           ) {
            currentLiveChannel = nil
            activePlayerItem = playable
            return
        }
        let seasonEps = allSeasons[seasonNumber] ?? []
        guard seasonEps.indices.contains(episodeIndex) else { return }
        let ep = seasonEps[episodeIndex]
        guard let url = apiClient.episodeStreamURL(episodeId: ep.id, containerExtension: ep.containerExtension) else { return }
        currentLiveChannel = nil
        activePlayerItem = PlayableItem(
            id: "episode-\(ep.id)",
            title: "\(fallbackTitle) • S\(seasonNumber):E\(ep.displayEpisodeNumber)",
            subtitle: nil,
            artworkURL: ep.info?.movieImage ?? fallbackArtwork,
            streamURL: url,
            kind: .episode,
            seriesId: seriesId,
            seasonNumber: seasonNumber,
            episodeNumber: ep.displayEpisodeNumber,
            nextEpisode: nil
        )
    }

    public func resolveNextEpisode(for item: PlayableItem) async -> PlayableItem.NextEpisodeRef? {
        if let existing = item.nextEpisode { return existing }
        guard item.kind == .episode,
              let seriesId = item.seriesId,
              let seasonNum = item.seasonNumber,
              let epNum = item.episodeNumber,
              let apiClient else {
            return nil
        }

        let allSeasons = await fetchEpisodesBySeason(seriesId: seriesId)
        guard !allSeasons.isEmpty else { return nil }
        let seriesName = seriesList.first(where: { $0.seriesId == seriesId })?.name
            ?? item.title.components(separatedBy: " • ").first
            ?? "Episode"
        let seriesCover = seriesList.first(where: { $0.seriesId == seriesId })?.cover ?? item.artworkURL

        let currentSeasonEps = allSeasons[seasonNum] ?? []
        let rawEpId = item.id.replacingOccurrences(of: "episode-", with: "")
        if let idx = currentSeasonEps.firstIndex(where: { $0.id == rawEpId || $0.displayEpisodeNumber == epNum || $0.episodeNum == epNum }),
           idx + 1 < currentSeasonEps.count {
            let nextEp = currentSeasonEps[idx + 1]
            if let url = apiClient.episodeStreamURL(episodeId: nextEp.id, containerExtension: nextEp.containerExtension) {
                return PlayableItem.NextEpisodeRef(
                    episodeId: nextEp.id,
                    title: "\(seriesName) • S\(seasonNum):E\(nextEp.displayEpisodeNumber)",
                    seasonNumber: seasonNum,
                    episodeNumber: nextEp.displayEpisodeNumber,
                    streamURL: url,
                    artworkURL: nextEp.info?.movieImage ?? seriesCover
                )
            }
        }

        let sortedSeasons = allSeasons.keys.sorted()
        if let sIdx = sortedSeasons.firstIndex(of: seasonNum),
           sIdx + 1 < sortedSeasons.count {
            let nextSeason = sortedSeasons[sIdx + 1]
            if let firstEp = allSeasons[nextSeason]?.first,
               let url = apiClient.episodeStreamURL(episodeId: firstEp.id, containerExtension: firstEp.containerExtension) {
                return PlayableItem.NextEpisodeRef(
                    episodeId: firstEp.id,
                    title: "\(seriesName) • S\(nextSeason):E\(firstEp.displayEpisodeNumber)",
                    seasonNumber: nextSeason,
                    episodeNumber: firstEp.displayEpisodeNumber,
                    streamURL: url,
                    artworkURL: firstEp.info?.movieImage ?? seriesCover
                )
            }
        }
        return nil
    }

    public func switchLiveChannel(offset: Int) {
        let list = activeLiveChannelList.isEmpty ? liveChannels : activeLiveChannelList
        guard !list.isEmpty else { return }
        guard let current = currentLiveChannel,
              let idx = list.firstIndex(where: { $0.streamId == current.streamId }) else {
            if let first = list.first {
                playChannel(first, in: list)
            }
            return
        }
        let nextIdx = (idx + offset + list.count) % list.count
        playChannel(list[nextIdx], in: list)
    }
}
