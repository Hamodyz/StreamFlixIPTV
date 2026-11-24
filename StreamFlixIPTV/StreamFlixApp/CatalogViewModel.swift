import Foundation
import SwiftUI
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

    private(set) var apiClient: XtreamAPIClient?

    public init() {}

    public func loadAll(credentials: XtreamCredentials) async {
        isLoading = true
        errorMessage = nil
        let client = XtreamAPIClient(credentials: credentials)
        self.apiClient = client

        do {
            let auth = try await client.authenticate()
            self.authInfo = auth

            async let liveCats = client.fetchLiveCategories()
            async let live = client.fetchLiveStreams()
            async let vodCats = client.fetchVODCategories()
            async let vods = client.fetchVODStreams()
            async let serCats = client.fetchSeriesCategories()
            async let sers = client.fetchSeries()

            let (lc, l, vc, v, sc, s) = try await (liveCats, live, vodCats, vods, serCats, sers)
            self.liveCategories = lc
            self.liveChannels = l
            self.vodCategories = vc
            self.movies = v
            self.seriesCategories = sc
            self.seriesList = s
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public var featuredMovie: VODMovie? {
        movies.first(where: { ($0.streamIcon ?? "").isEmpty == false }) ?? movies.first
    }

    public func movies(for categoryId: String) -> [VODMovie] {
        movies.filter { $0.categoryId == categoryId }
    }

    public func series(for categoryId: String) -> [SeriesItem] {
        seriesList.filter { $0.categoryId == categoryId }
    }

    public func channels(for categoryId: String) -> [LiveChannel] {
        liveChannels.filter { $0.categoryId == categoryId }
    }

    // MARK: - Instant Universal Search (Channels + Movies + Series)

    public var filteredChannels: [LiveChannel] {
        guard !searchQuery.isEmpty else { return liveChannels }
        return liveChannels.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    public var filteredMovies: [VODMovie] {
        guard !searchQuery.isEmpty else { return movies }
        return movies.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    public var filteredSeries: [SeriesItem] {
        guard !searchQuery.isEmpty else { return seriesList }
        return seriesList.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    public func playMovie(_ movie: VODMovie) {
        activePlayerItem = apiClient?.buildPlayableMovie(movie)
    }

    public func playChannel(_ channel: LiveChannel, preferHLS: Bool = true) {
        activePlayerItem = apiClient?.buildPlayableLive(channel, preferHLS: preferHLS)
    }
}
