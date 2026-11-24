import SwiftUI
import StreamFlixCore

@main
struct StreamFlixIPTVApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var credentialsStore = CredentialsStore()
    @StateObject private var progressStore = WatchProgressStore()
    @StateObject private var sleepGuard = SleepGuardManager(maxConsecutiveAutoPlay: 2, promptTimeoutSeconds: 60)
    @StateObject private var playerEngine: NetflixPlayerEngine
    @StateObject private var catalogVM = CatalogViewModel()
    @StateObject private var syncManager = CloudSyncManager()

    init() {
        // Boost poster image cache (100 MB RAM / 400 MB Disk) for smooth scrolling
        URLCache.shared = URLCache(
            memoryCapacity: 100 * 1024 * 1024,
            diskCapacity: 400 * 1024 * 1024,
            diskPath: "StreamFlixPosterCache"
        )

        let progress = WatchProgressStore()
        let guardMgr = SleepGuardManager(maxConsecutiveAutoPlay: 2, promptTimeoutSeconds: 60)
        _progressStore = StateObject(wrappedValue: progress)
        _sleepGuard = StateObject(wrappedValue: guardMgr)
        _playerEngine = StateObject(wrappedValue: NetflixPlayerEngine(progressStore: progress, sleepGuard: guardMgr))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let activeCreds = credentialsStore.activeProfile {
                    MainTabView(
                        credentials: activeCreds,
                        catalogVM: catalogVM,
                        playerEngine: playerEngine,
                        progressStore: progressStore,
                        sleepGuard: sleepGuard,
                        credentialsStore: credentialsStore,
                        syncManager: syncManager
                    )
                    .task(id: activeCreds.host + activeCreds.username) {
                        wireSyncCallbacks(for: activeCreds)
                        await catalogVM.loadAll(credentials: activeCreds)
                        await pullFromCloud(for: activeCreds)
                    }
                } else {
                    LoginView(credentialsStore: credentialsStore)
                }
            }
            .preferredColorScheme(.dark)
            .tint(Color(red: 0.898, green: 0.035, blue: 0.078)) // Netflix Red #E50914
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    playerEngine.saveCheckpointNow()
                    if let activeCreds = credentialsStore.activeProfile, syncManager.isConfigured {
                        Task {
                            await syncManager.pushNow(
                                userKey: activeCreds.username,
                                progressStore: progressStore,
                                favorites: (catalogVM.favoriteSeriesIds, catalogVM.favoriteMovieIds, catalogVM.favoriteChannelIds)
                            )
                        }
                    }
                } else if newPhase == .active, let activeCreds = credentialsStore.activeProfile {
                    Task {
                        await pullFromCloud(for: activeCreds)
                    }
                }
            }
        }
    }

    private func wireSyncCallbacks(for creds: XtreamCredentials) {
        progressStore.onDidChange = { [weak syncManager, weak progressStore, weak catalogVM] in
            guard let syncManager, let progressStore, let catalogVM else { return }
            syncManager.schedulePush(
                userKey: creds.username,
                progressStore: progressStore,
                favorites: (catalogVM.favoriteSeriesIds, catalogVM.favoriteMovieIds, catalogVM.favoriteChannelIds)
            )
        }
        catalogVM.onFavoritesChanged = { [weak syncManager, weak progressStore, weak catalogVM] in
            guard let syncManager, let progressStore, let catalogVM else { return }
            syncManager.schedulePush(
                userKey: creds.username,
                progressStore: progressStore,
                favorites: (catalogVM.favoriteSeriesIds, catalogVM.favoriteMovieIds, catalogVM.favoriteChannelIds)
            )
        }
    }

    private func pullFromCloud(for creds: XtreamCredentials) async {
        guard syncManager.isConfigured else { return }
        if let merged = await syncManager.pullAndMerge(
            userKey: creds.username,
            progressStore: progressStore,
            localFavorites: (catalogVM.favoriteSeriesIds, catalogVM.favoriteMovieIds, catalogVM.favoriteChannelIds)
        ) {
            catalogVM.applyMergedFavorites(series: merged.series, movies: merged.movies, channels: merged.channels)
        }
    }
}
