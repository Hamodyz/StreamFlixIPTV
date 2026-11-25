import SwiftUI
import StreamFlixCore

private func cleanDisplayTitle(for item: PlayableItem) -> String {
    guard item.kind == .episode else { return item.title }
    return item.title.components(separatedBy: " — ").first ?? item.title
}

struct NetflixHomeView: View {
    @ObservedObject var catalogVM: CatalogViewModel
    @ObservedObject var progressStore: WatchProgressStore

    @State private var selectedSeries: SeriesItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if catalogVM.isLoading && catalogVM.movies.isEmpty && catalogVM.seriesList.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(Color(red: 0.898, green: 0.035, blue: 0.078))
                            .scaleEffect(1.3)
                        Text("Loading your library...")
                            .foregroundStyle(.secondary)
                    }
                } else if let error = catalogVM.errorMessage, catalogVM.movies.isEmpty && catalogVM.seriesList.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        Text(error)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") {
                            Task { await catalogVM.reload() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 0) {
                        // Universal Search Bar on Home (Searches Movies, Series & Live TV)
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("ابحث عن أي فيلم أو مسلسل أو قناة (عربي / إنجليزي)...", text: $catalogVM.searchQuery)
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        if !catalogVM.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            homeSearchResultsView
                        } else {
                            homeCatalogScrollView
                        }
                    }
                }
            }
            .navigationTitle("STREAMFLIX")
            #if os(iOS) || os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $selectedSeries) { series in
                SeriesDetailView(series: series, catalogVM: catalogVM)
            }
        }
    }

    private var homeSearchResultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if catalogVM.filteredChannels.isEmpty && catalogVM.filteredMovies.isEmpty && catalogVM.filteredSeries.isEmpty {
                    Text("لا توجد نتائج مطابقة لـ \"\(catalogVM.searchQuery)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                } else {
                    if !catalogVM.filteredSeries.isEmpty {
                        Text("Series (\(catalogVM.filteredSeries.count))")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), spacing: 12)], spacing: 14) {
                            ForEach(catalogVM.filteredSeries.prefix(40)) { item in
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

                    if !catalogVM.filteredMovies.isEmpty {
                        Text("Movies (\(catalogVM.filteredMovies.count))")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), spacing: 12)], spacing: 14) {
                            ForEach(catalogVM.filteredMovies.prefix(40)) { movie in
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

                    if !catalogVM.filteredChannels.isEmpty {
                        Text("Live Channels (\(catalogVM.filteredChannels.count))")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)

                        ForEach(catalogVM.filteredChannels.prefix(25)) { ch in
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
                }
            }
            .padding(.vertical, 12)
        }
    }

    private var homeCatalogScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 22) {
                HomeDashboardHeader(
                    catalogVM: catalogVM,
                    latestResume: progressStore.continueWatchingList.first,
                    onResume: { record in
                        catalogVM.activePlayerItem = record.item
                    },
                    onSurpriseMovie: {
                        if let randomMovie = catalogVM.trendingMovies.randomElement() ?? catalogVM.movies.randomElement() {
                            catalogVM.playMovie(randomMovie)
                        }
                    },
                    onRefreshAI: {
                        let watched = progressStore.records.values
                            .sorted { $0.updatedAt > $1.updatedAt }
                            .prefix(10)
                            .map { $0.item.title.components(separatedBy: " • ").first ?? $0.item.title }
                        Task {
                            await catalogVM.refreshAICuration(watchedTitles: watched, forceRefresh: true)
                        }
                    }
                )

                if let aiMsg = catalogVM.aiStatusMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                        Text(aiMsg)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Button {
                            catalogVM.aiStatusMessage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                }

                if !progressStore.continueWatchingList.isEmpty {
                    ContinueWatchingRow(
                        records: progressStore.continueWatchingList,
                        onResume: { record in
                            catalogVM.activePlayerItem = record.item
                        },
                        onRemove: { record in
                            progressStore.removeProgress(for: record.id)
                        }
                    )
                }

                if !catalogVM.forYouMovies.isEmpty {
                    MovieCarouselRow(
                        title: catalogVM.forYouTitle,
                        movies: catalogVM.forYouMovies,
                        onSelect: { catalogVM.playMovie($0) }
                    )
                }

                if !catalogVM.forYouSeries.isEmpty {
                    SeriesCarouselRow(
                        title: "Series Picks for You ✨",
                        series: catalogVM.forYouSeries,
                        onSelect: { selectedSeries = $0 }
                    )
                }

                // My List / Favorites on Home Screen
                if !catalogVM.favoriteSeriesItems.isEmpty {
                    SeriesCarouselRow(
                        title: "My List — Favorite Series ❤️",
                        series: catalogVM.favoriteSeriesItems,
                        onSelect: { selectedSeries = $0 }
                    )
                }

                if !catalogVM.favoriteMovies.isEmpty {
                    MovieCarouselRow(
                        title: "My List — Favorite Movies ❤️",
                        movies: catalogVM.favoriteMovies,
                        onSelect: { catalogVM.playMovie($0) }
                    )
                }

                if !catalogVM.favoriteChannels.isEmpty {
                    FavoriteChannelsRow(
                        channels: catalogVM.favoriteChannels,
                        onSelect: { ch in
                            catalogVM.playChannel(ch, in: catalogVM.favoriteChannels)
                        }
                    )
                }

                if !catalogVM.trendingMovies.isEmpty {
                    MovieCarouselRow(
                        title: "Trending Movies 🔥",
                        movies: catalogVM.trendingMovies,
                        onSelect: { catalogVM.playMovie($0) }
                    )
                }

                if !catalogVM.trendingSeries.isEmpty {
                    SeriesCarouselRow(
                        title: "Trending Series ⭐",
                        series: catalogVM.trendingSeries,
                        onSelect: { selectedSeries = $0 }
                    )
                }

                ForEach(catalogVM.vodCategories.prefix(6)) { category in
                    let items = catalogVM.movies(for: category.categoryId)
                    if !items.isEmpty {
                        MovieCarouselRow(
                            title: category.categoryName,
                            movies: Array(items.prefix(20)),
                            onSelect: { catalogVM.playMovie($0) }
                        )
                    }
                }

                ForEach(catalogVM.seriesCategories.prefix(4)) { category in
                    let items = catalogVM.series(for: category.categoryId)
                    if !items.isEmpty {
                        SeriesCarouselRow(
                            title: category.categoryName,
                            series: Array(items.prefix(20)),
                            onSelect: { selectedSeries = $0 }
                        )
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .refreshable {
            await catalogVM.reload()
            let watched = progressStore.records.values
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(10)
                .map { $0.item.title.components(separatedBy: " • ").first ?? $0.item.title }
            await catalogVM.refreshAICuration(watchedTitles: watched, forceRefresh: true)
        }
    }
}

private struct FavoriteChannelsRow: View {
    let channels: [LiveChannel]
    let onSelect: (LiveChannel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My List — Favorite Channels ❤️")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(channels) { ch in
                        Button { onSelect(ch) } label: {
                            HStack(spacing: 10) {
                                AsyncImage(url: URL(string: ch.streamIcon ?? "")) { phase in
                                    if let img = phase.image {
                                        img.resizable().aspectRatio(contentMode: .fit)
                                    } else {
                                        Image(systemName: "tv").foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 36, height: 28)

                                Text(ch.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct HomeDashboardHeader: View {
    @ObservedObject var catalogVM: CatalogViewModel
    let latestResume: WatchProgressRecord?
    let onResume: (WatchProgressRecord) -> Void
    let onSurpriseMovie: () -> Void
    let onRefreshAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let resume = latestResume {
                HStack(spacing: 16) {
                    AsyncImage(url: URL(string: resume.item.artworkURL ?? "")) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.white.opacity(0.1)
                        }
                    }
                    .frame(width: 96, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("RESUME WATCHING")
                            .font(.caption2.bold())
                            .tracking(1.5)
                            .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                        Text(cleanDisplayTitle(for: resume.item))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        ProgressView(value: resume.progressFraction)
                            .tint(Color(red: 0.898, green: 0.035, blue: 0.078))
                    }

                    Spacer()

                    Button {
                        onResume(resume)
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.898, green: 0.035, blue: 0.078).opacity(0.22), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    StatPill(icon: "film.fill", label: "Movies", value: "\(catalogVM.movies.count)")
                    StatPill(icon: "tv.fill", label: "Series", value: "\(catalogVM.seriesList.count)")
                    StatPill(icon: "antenna.radiowaves.left.and.right", label: "Live TV", value: "\(catalogVM.liveChannels.count)")
                    StatPill(
                        icon: "heart.fill",
                        label: "My List",
                        value: "\(catalogVM.favoriteMovies.count + catalogVM.favoriteSeriesItems.count + catalogVM.favoriteChannels.count)"
                    )
                    Button(action: onSurpriseMovie) {
                        HStack(spacing: 6) {
                            Image(systemName: "shuffle")
                                .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                            Text("Pick for Me")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button(action: onRefreshAI) {
                        HStack(spacing: 6) {
                            if catalogVM.isRefreshingAI {
                                ProgressView().scaleEffect(0.7).tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                            }
                            Text("AI Picks")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(catalogVM.isRefreshingAI)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}

private struct StatPill: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.08), in: Capsule())
    }
}

private struct ContinueWatchingRow: View {
    let records: [WatchProgressRecord]
    let onResume: (WatchProgressRecord) -> Void
    let onRemove: (WatchProgressRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continue Watching")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(records) { record in
                        Button {
                            onResume(record)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .center) {
                                    AsyncImage(url: URL(string: record.item.artworkURL ?? "")) { phase in
                                        if let img = phase.image {
                                            img.resizable().aspectRatio(contentMode: .fill)
                                        } else {
                                            Color.white.opacity(0.12)
                                        }
                                    }
                                    .frame(width: 150, height: 100)
                                    .clipped()

                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 36))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .shadow(radius: 4)
                                }
                                .overlay(alignment: .bottom) {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Rectangle().fill(Color.white.opacity(0.25))
                                            Rectangle()
                                                .fill(Color(red: 0.898, green: 0.035, blue: 0.078))
                                                .frame(width: geo.size.width * record.progressFraction)
                                        }
                                    }
                                    .frame(height: 4)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Text(cleanDisplayTitle(for: record.item))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                onRemove(record)
                            } label: {
                                Label("Remove from Continue Watching", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct MovieCarouselRow: View {
    let title: String
    let movies: [VODMovie]
    let onSelect: (VODMovie) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(movies) { movie in
                        Button { onSelect(movie) } label: {
                            PosterCard(title: movie.name, imageURL: movie.streamIcon)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct SeriesCarouselRow: View {
    let title: String
    let series: [SeriesItem]
    let onSelect: (SeriesItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(series) { item in
                        Button { onSelect(item) } label: {
                            PosterCard(title: item.name, imageURL: item.cover)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct PosterCard: View {
    let title: String
    let imageURL: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: imageURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZStack {
                        Color.white.opacity(0.1)
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 120, height: 175)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
        }
    }
}
