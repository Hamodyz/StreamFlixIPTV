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

    init() {
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
                        credentialsStore: credentialsStore
                    )
                    .task(id: activeCreds.host + activeCreds.username) {
                        await catalogVM.loadAll(credentials: activeCreds)
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
                }
            }
        }
    }
}
