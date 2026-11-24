import SwiftUI
import StreamFlixCore

struct MainTabView: View {
    let credentials: XtreamCredentials
    @ObservedObject var catalogVM: CatalogViewModel
    @ObservedObject var playerEngine: NetflixPlayerEngine
    @ObservedObject var progressStore: WatchProgressStore
    @ObservedObject var sleepGuard: SleepGuardManager
    @ObservedObject var credentialsStore: CredentialsStore

    var body: some View {
        TabView {
            NetflixHomeView(
                catalogVM: catalogVM,
                progressStore: progressStore
            )
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            LiveTVView(catalogVM: catalogVM)
                .tabItem {
                    Label("Live TV", systemImage: "tv.fill")
                }

            SearchView(catalogVM: catalogVM)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            ProfileSettingsView(
                credentials: credentials,
                catalogVM: catalogVM,
                progressStore: progressStore,
                sleepGuard: sleepGuard,
                credentialsStore: credentialsStore
            )
            .tabItem {
                Label("Account", systemImage: "person.crop.circle")
            }
        }
        .fullScreenCover(item: $catalogVM.activePlayerItem, onDismiss: {
            playerEngine.stop()
        }) { item in
            NetflixPlayerView(
                item: item,
                engine: playerEngine,
                sleepGuard: sleepGuard,
                onDismiss: {
                    catalogVM.activePlayerItem = nil
                }
            )
        }
    }
}
