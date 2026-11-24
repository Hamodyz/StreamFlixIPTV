import SwiftUI
import StreamFlixCore

struct SearchView: View {
    @ObservedObject var catalogVM: CatalogViewModel
    @State private var selectedSeries: SeriesItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if catalogVM.searchQuery.isEmpty {
                            Text("Search across all Live Channels, Movies, and Series instantly.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                        } else {
                            if !catalogVM.filteredChannels.isEmpty {
                                Text("Live Channels")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)

                                ForEach(catalogVM.filteredChannels.prefix(15)) { ch in
                                    Button {
                                        catalogVM.playChannel(ch)
                                    } label: {
                                        HStack {
                                            Image(systemName: "tv").foregroundStyle(.red)
                                            Text(ch.name).foregroundStyle(.white)
                                            Spacer()
                                            Image(systemName: "play.fill").foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                    }
                                }
                            }

                            if !catalogVM.filteredMovies.isEmpty {
                                Text("Movies")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 14) {
                                    ForEach(catalogVM.filteredMovies.prefix(30)) { movie in
                                        Button {
                                            catalogVM.playMovie(movie)
                                        } label: {
                                            PosterCard(title: movie.name, imageURL: movie.streamIcon)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }

                            if !catalogVM.filteredSeries.isEmpty {
                                Text("Series")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 14) {
                                    ForEach(catalogVM.filteredSeries.prefix(30)) { item in
                                        Button {
                                            selectedSeries = item
                                        } label: {
                                            PosterCard(title: item.name, imageURL: item.cover)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $catalogVM.searchQuery, prompt: "Channels, Movies, Series...")
            .navigationDestination(item: $selectedSeries) { series in
                SeriesDetailView(series: series, catalogVM: catalogVM)
            }
        }
    }
}

struct ProfileSettingsView: View {
    let credentials: XtreamCredentials
    @ObservedObject var catalogVM: CatalogViewModel
    @ObservedObject var progressStore: WatchProgressStore
    @ObservedObject var sleepGuard: SleepGuardManager
    @ObservedObject var credentialsStore: CredentialsStore

    var body: some View {
        NavigationStack {
            List {
                Section("Active Subscription") {
                    LabeledContent("Profile", value: credentials.profileName)
                    LabeledContent("Username", value: credentials.username)
                    LabeledContent("Server", value: credentials.host)
                    if let status = catalogVM.authInfo?.userInfo.status {
                        LabeledContent("Status", value: status)
                    }
                }

                Section("Netflix Sleep Guard") {
                    Stepper(
                        "Ask after \(sleepGuard.maxConsecutiveAutoPlay) episodes",
                        value: $sleepGuard.maxConsecutiveAutoPlay,
                        in: 1...5
                    )
                }

                Section("History") {
                    Button("Clear Continue Watching", role: .destructive) {
                        progressStore.clearAll()
                    }
                }

                Section {
                    Button("Switch Profile / Sign Out", role: .destructive) {
                        credentialsStore.signOut()
                    }
                }
            }
            .navigationTitle("Account")
        }
    }
}
