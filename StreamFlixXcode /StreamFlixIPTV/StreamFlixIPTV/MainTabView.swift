import SwiftUI
import StreamFlixCore

struct MainTabView: View {
    let credentials: XtreamCredentials
    @ObservedObject var catalogVM: CatalogViewModel
    @ObservedObject var playerEngine: NetflixPlayerEngine
    @ObservedObject var progressStore: WatchProgressStore
    @ObservedObject var sleepGuard: SleepGuardManager
    @ObservedObject var credentialsStore: CredentialsStore
    @ObservedObject var syncManager: CloudSyncManager

    var body: some View {
        ZStack {
            TabView {
                NetflixHomeView(
                    catalogVM: catalogVM,
                    progressStore: progressStore
                )
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

                MoviesLibraryView(catalogVM: catalogVM)
                    .tabItem {
                        Label("Movies", systemImage: "film.fill")
                    }

                SeriesLibraryView(catalogVM: catalogVM)
                    .tabItem {
                        Label("Series", systemImage: "sparkles.tv.fill")
                    }

                LiveTVView(catalogVM: catalogVM)
                    .tabItem {
                        Label("Live TV", systemImage: "tv.fill")
                    }

                ProfileSettingsView(
                    credentials: credentials,
                    catalogVM: catalogVM,
                    progressStore: progressStore,
                    sleepGuard: sleepGuard,
                    credentialsStore: credentialsStore,
                    syncManager: syncManager
                )
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
            }

            #if os(macOS)
            if let item = catalogVM.activePlayerItem {
                NetflixPlayerView(
                    item: item,
                    catalogVM: catalogVM,
                    engine: playerEngine,
                    sleepGuard: sleepGuard,
                    onDismiss: {
                        catalogVM.activePlayerItem = nil
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .transition(.opacity)
                .zIndex(100)
            }
            #endif
        }
        #if os(iOS) || os(tvOS)
        .fullScreenCover(item: $catalogVM.activePlayerItem, onDismiss: {
            playerEngine.stop()
        }) { item in
            NetflixPlayerView(
                item: item,
                catalogVM: catalogVM,
                engine: playerEngine,
                sleepGuard: sleepGuard,
                onDismiss: {
                    catalogVM.activePlayerItem = nil
                }
            )
        }
        #endif
    }
}
