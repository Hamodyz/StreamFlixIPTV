import SwiftUI
import StreamFlixCore

struct SearchView: View {
    @ObservedObject var catalogVM: CatalogViewModel
    @State private var selectedSeries: SeriesItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Prominent Always-Visible Netflix Search Bar (Arabic & English)
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("ابحث بالعربي أو الإنجليزي (أفلام، مسلسلات، قنوات)...", text: $catalogVM.searchQuery)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                        if !catalogVM.searchQuery.isEmpty {
                            Button {
                                catalogVM.searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if catalogVM.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("اكتب اسم أي فيلم أو مسلسل أو قناة بالعربي أو بالإنجليزي للبحث الفوري.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                            } else if catalogVM.filteredChannels.isEmpty && catalogVM.filteredMovies.isEmpty && catalogVM.filteredSeries.isEmpty {
                                Text("لا توجد نتائج مطابقة لـ \"\(catalogVM.searchQuery)\"")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                            } else {
                                if !catalogVM.filteredChannels.isEmpty {
                                    Text("Live Channels (\(catalogVM.filteredChannels.count))")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 16)

                                    ForEach(catalogVM.filteredChannels.prefix(20)) { ch in
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
                                        .buttonStyle(.plain)
                                    }
                                }

                                if !catalogVM.filteredMovies.isEmpty {
                                    Text("Movies (\(catalogVM.filteredMovies.count))")
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
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }

                                if !catalogVM.filteredSeries.isEmpty {
                                    Text("Series (\(catalogVM.filteredSeries.count))")
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
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Search")
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
    @ObservedObject var syncManager: CloudSyncManager
    @ObservedObject private var openSubtitlesSettings = OpenSubtitlesSettings.shared

    @State private var showDeleteConfirm = false
    @State private var showAddAccountSheet = false
    @State private var revealOpenSubtitlesKey = false
    @State private var revealGeminiKey = false

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
                    if let active = catalogVM.authInfo?.userInfo.activeCons,
                       let maxC = catalogVM.authInfo?.userInfo.maxConnections {
                        LabeledContent("Connections", value: "\(active) / \(maxC)")
                    }
                    Button {
                        Task {
                            await catalogVM.reload()
                        }
                    } label: {
                        HStack {
                            Label("Refresh Library", systemImage: "arrow.clockwise")
                            Spacer()
                            if catalogVM.isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(catalogVM.isLoading)
                }

                Section {
                    TextField("https://your-project-default-rtdb.firebaseio.com", text: $syncManager.databaseURLString)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif

                    Button {
                        Task {
                            if let merged = await syncManager.pullAndMerge(
                                userKey: credentials.username,
                                progressStore: progressStore,
                                localFavorites: (catalogVM.favoriteSeriesIds, catalogVM.favoriteMovieIds, catalogVM.favoriteChannelIds)
                            ) {
                                catalogVM.applyMergedFavorites(series: merged.series, movies: merged.movies, channels: merged.channels)
                                await syncManager.pushNow(
                                    userKey: credentials.username,
                                    progressStore: progressStore,
                                    favorites: merged
                                )
                            }
                        }
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if syncManager.isSyncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!syncManager.isConfigured || syncManager.isSyncing)

                    if let last = syncManager.lastSyncedAt {
                        LabeledContent("Last Synced", value: last.formatted(date: .omitted, time: .shortened))
                    }
                    if let err = syncManager.lastSyncError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Cloud Sync (iPad / iPhone / Mac)")
                } footer: {
                    Text("Paste your free Firebase Realtime Database URL once on each device to sync Continue Watching & My List automatically.")
                }

                Section {
                    HStack(spacing: 10) {
                        if revealOpenSubtitlesKey {
                            TextField("OpenSubtitles API Key", text: $openSubtitlesSettings.apiKey)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        } else {
                            SecureField("OpenSubtitles API Key", text: $openSubtitlesSettings.apiKey)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        }
                        Button {
                            revealOpenSubtitlesKey.toggle()
                        } label: {
                            Image(systemName: revealOpenSubtitlesKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    LabeledContent(
                        "OpenSubtitles Status",
                        value: openSubtitlesSettings.isConfigured ? "Configured ✓" : "Not Set"
                    )

                    Picker("Default Language", selection: $openSubtitlesSettings.preferredLanguage) {
                        ForEach(SubtitleLanguage.allCases) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }

                    HStack(spacing: 10) {
                        if revealGeminiKey {
                            TextField("Gemini API Key (for AI Translation)", text: $openSubtitlesSettings.geminiAPIKey)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        } else {
                            SecureField("Gemini API Key (for AI Translation)", text: $openSubtitlesSettings.geminiAPIKey)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        }
                        Button {
                            revealGeminiKey.toggle()
                        } label: {
                            Image(systemName: revealGeminiKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    LabeledContent(
                        "AI Translation",
                        value: openSubtitlesSettings.isGeminiConfigured ? "Configured ✓" : "Optional"
                    )
                } header: {
                    Text("Subtitles & AI Translation")
                } footer: {
                    Text("Add your OpenSubtitles API Key (opensubtitles.com → API Consumers) and optionally a free Gemini API Key (aistudio.google.com) to translate English subtitles into Arabic or Spanish with AI.")
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

                Section("Accounts (\(credentialsStore.savedProfiles.count))") {
                    ForEach(credentialsStore.savedProfiles, id: \.self) { profile in
                        let isCurrent = (profile.host == credentials.host && profile.username == credentials.username)
                        Button {
                            if !isCurrent {
                                credentialsStore.selectProfile(profile)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.profileName)
                                        .font(.body.weight(isCurrent ? .bold : .regular))
                                        .foregroundStyle(.primary)
                                    Text("\(profile.username) • \(profile.host)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if isCurrent {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                                }
                            }
                        }
                    }

                    Button {
                        showAddAccountSheet = true
                    } label: {
                        Label("Add Another Account", systemImage: "person.badge.plus")
                    }

                    Button {
                        credentialsStore.signOut()
                    } label: {
                        Label("Sign Out (Keep Saved)", systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Current Account", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Account")
            .alert("Delete Account?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    credentialsStore.deleteProfile(credentials)
                }
            } message: {
                Text("This will remove \(credentials.profileName) (\(credentials.username)) from this device.")
            }
            .sheet(isPresented: $showAddAccountSheet) {
                LoginView(credentialsStore: credentialsStore)
            }
        }
    }
}
