import SwiftUI
import StreamFlixCore

// MARK: - Live TV Tab (iPad/Mac Split Dish Guide + Live Mini-Player | iPhone Compact List)

struct LiveTVView: View {
    @ObservedObject var catalogVM: CatalogViewModel
    @State private var selectedCategoryId: String?
    @State private var searchText: String = ""
    @State private var previewChannel: LiveChannel?
    @StateObject private var previewVLC = VLCPlayerController()
    @StateObject private var previewProgress = WatchProgressStore()

    var selectedCategoryTitle: String {
        if let id = selectedCategoryId,
           let cat = catalogVM.liveCategories.first(where: { $0.categoryId == id }) {
            return cat.categoryName
        }
        return "All Channels (\(catalogVM.liveChannels.count))"
    }

    var displayedChannels: [LiveChannel] {
        let base = selectedCategoryId.map { catalogVM.channels(for: $0) } ?? catalogVM.liveChannels
        return base.filter { catalogVM.matches($0.name, query: searchText) }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()

                    if geo.size.width >= 720 {
                        // iPad / Mac Split Satellite Dish Layout
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                CategoryAndSearchBar(
                                    selectedTitle: selectedCategoryTitle,
                                    allTitle: "All Channels (\(catalogVM.liveChannels.count))",
                                    categories: catalogVM.liveCategories,
                                    searchText: $searchText,
                                    searchPlaceholder: "ابحث في القنوات المباشرة...",
                                    onSelectAll: { selectedCategoryId = nil },
                                    onSelectCategory: { selectedCategoryId = $0.categoryId }
                                )

                                List(Array(displayedChannels.enumerated()), id: \.element.id) { index, channel in
                                    let isSelected = (previewChannel?.streamId == channel.streamId)
                                    HStack(spacing: 12) {
                                        Button {
                                            if isSelected {
                                                openFullscreen(channel)
                                            } else {
                                                startPreview(channel)
                                            }
                                        } label: {
                                            HStack(spacing: 10) {
                                                Text(String(format: "%03d", index + 1))
                                                    .font(.caption.monospacedDigit().bold())
                                                    .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                                                    .frame(width: 34, alignment: .leading)

                                                AsyncImage(url: URL(string: channel.streamIcon ?? "")) { phase in
                                                    if let img = phase.image {
                                                        img.resizable().aspectRatio(contentMode: .fit)
                                                    } else {
                                                        Image(systemName: "tv")
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                .frame(width: 38, height: 28)
                                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                                                Text(channel.name)
                                                    .font(.subheadline.weight(isSelected ? .bold : .medium))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)

                                                Spacer()
                                            }
                                            .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            catalogVM.toggleFavoriteChannel(channel.streamId)
                                        } label: {
                                            Image(systemName: catalogVM.isFavorite(channelId: channel.streamId) ? "heart.fill" : "heart")
                                                .font(.caption)
                                                .foregroundStyle(catalogVM.isFavorite(channelId: channel.streamId) ? Color(red: 0.898, green: 0.035, blue: 0.078) : .secondary)
                                                .padding(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .listRowBackground(isSelected ? Color(red: 0.898, green: 0.035, blue: 0.078).opacity(0.22) : Color.black)
                                }
                                .listStyle(.plain)
                            }
                            .frame(width: min(410, geo.size.width * 0.40))

                            Divider().background(Color.white.opacity(0.12))

                            // Right Pane: Live Mini-Player Preview + Dish Controls
                            VStack(spacing: 18) {
                                if let ch = previewChannel {
                                    ZStack {
                                        Color.black
                                        VLCVideoSurface(
                                            mediaPlayer: previewVLC.mediaPlayer,
                                            onSingleTap: { openFullscreen(ch) },
                                            onDoubleTapDelta: { _ in },
                                            onHorizontalSwipeDelta: { _ in }
                                        )
                                        if previewVLC.isBuffering && previewVLC.errorMessage == nil {
                                            ProgressView()
                                                .tint(Color(red: 0.898, green: 0.035, blue: 0.078))
                                                .scaleEffect(1.3)
                                        }
                                        if let err = previewVLC.errorMessage {
                                            VStack(spacing: 8) {
                                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                                Text(err).font(.caption).foregroundStyle(.white).multilineTextAlignment(.center)
                                                Button("Retry") { startPreview(ch) }.buttonStyle(.borderedProminent)
                                            }
                                            .padding()
                                        }
                                    }
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        Button { openFullscreen(ch) } label: {
                                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.white)
                                                .padding(10)
                                                .background(.black.opacity(0.7), in: Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .padding(12)
                                    }

                                    HStack(spacing: 14) {
                                        Circle().fill(Color.red).frame(width: 10, height: 10)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ch.name)
                                                .font(.title3.bold())
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            Text("LIVE PREVIEW • Tap channel again or Full Screen to expand")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }

                                    HStack(spacing: 12) {
                                        Button {
                                            zapPreview(offset: -1)
                                        } label: {
                                            Label("CH -", systemImage: "chevron.down")
                                                .font(.subheadline.bold())
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 12)
                                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.white)

                                        Button {
                                            openFullscreen(ch)
                                        } label: {
                                            Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                                .font(.subheadline.bold())
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(Color(red: 0.898, green: 0.035, blue: 0.078), in: RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.white)

                                        Button {
                                            zapPreview(offset: 1)
                                        } label: {
                                            Label("CH +", systemImage: "chevron.up")
                                                .font(.subheadline.bold())
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 12)
                                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.white)
                                    }
                                } else {
                                    VStack(spacing: 14) {
                                        Image(systemName: "tv.and.mediabox")
                                            .font(.system(size: 56))
                                            .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                                        Text("Select a Channel")
                                            .font(.title2.bold())
                                            .foregroundStyle(.white)
                                        Text("Tap any channel on the left to watch it live right here, or tap Full Screen anytime.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: 360)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        // iPhone Compact List
                        VStack(alignment: .leading, spacing: 0) {
                            CategoryAndSearchBar(
                                selectedTitle: selectedCategoryTitle,
                                allTitle: "All Channels (\(catalogVM.liveChannels.count))",
                                categories: catalogVM.liveCategories,
                                searchText: $searchText,
                                searchPlaceholder: "ابحث في القنوات المباشرة...",
                                onSelectAll: { selectedCategoryId = nil },
                                onSelectCategory: { selectedCategoryId = $0.categoryId }
                            )

                            List(displayedChannels) { channel in
                                HStack(spacing: 14) {
                                    Button {
                                        catalogVM.playChannel(channel, in: displayedChannels, preferHLS: true)
                                    } label: {
                                        HStack(spacing: 14) {
                                            AsyncImage(url: URL(string: channel.streamIcon ?? "")) { phase in
                                                if let img = phase.image {
                                                    img.resizable().aspectRatio(contentMode: .fit)
                                                } else {
                                                    Image(systemName: "tv").foregroundStyle(.secondary)
                                                }
                                            }
                                            .frame(width: 48, height: 36)
                                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                                            Text(channel.name)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)

                                            Spacer()

                                            Image(systemName: "play.fill")
                                                .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        catalogVM.toggleFavoriteChannel(channel.streamId)
                                    } label: {
                                        Image(systemName: catalogVM.isFavorite(channelId: channel.streamId) ? "heart.fill" : "heart")
                                            .foregroundStyle(catalogVM.isFavorite(channelId: channel.streamId) ? Color(red: 0.898, green: 0.035, blue: 0.078) : .secondary)
                                            .padding(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .listRowBackground(Color.black)
                            }
                            .listStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Live TV")
            .onDisappear {
                previewVLC.stop()
            }
            .onChange(of: catalogVM.activePlayerItem) { _, newItem in
                if newItem != nil {
                    previewVLC.stop()
                }
            }
        }
    }

    private func startPreview(_ channel: LiveChannel) {
        previewChannel = channel
        if let item = catalogVM.apiClient?.buildPlayableLive(channel, preferHLS: true) {
            previewVLC.load(item: item, progressStore: previewProgress)
        }
    }

    private func openFullscreen(_ channel: LiveChannel) {
        previewVLC.stop()
        catalogVM.playChannel(channel, in: displayedChannels, preferHLS: true)
    }

    private func zapPreview(offset: Int) {
        let list = displayedChannels
        guard !list.isEmpty else { return }
        guard let current = previewChannel,
              let idx = list.firstIndex(where: { $0.streamId == current.streamId }) else {
            if let first = list.first { startPreview(first) }
            return
        }
        let nextIdx = (idx + offset + list.count) % list.count
        startPreview(list[nextIdx])
    }
}

// MARK: - Movies Library Tab (Server Order + Left Dropdown + Inline Search + Pagination)

struct MoviesLibraryView: View {
    @ObservedObject var catalogVM: CatalogViewModel
    @State private var selectedCategoryId: String?
    @State private var searchText: String = ""
    @State private var displayLimit: Int = 150

    var selectedCategoryTitle: String {
        if let id = selectedCategoryId,
           let cat = catalogVM.vodCategories.first(where: { $0.categoryId == id }) {
            return cat.categoryName
        }
        return "All Movies (\(catalogVM.movies.count))"
    }

    var displayedMovies: [VODMovie] {
        let base = selectedCategoryId.map { catalogVM.movies(for: $0) } ?? catalogVM.movies
        return base.filter { catalogVM.matches($0.name, query: searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    CategoryAndSearchBar(
                        selectedTitle: selectedCategoryTitle,
                        allTitle: "All Movies (\(catalogVM.movies.count))",
                        categories: catalogVM.vodCategories,
                        searchText: $searchText,
                        searchPlaceholder: "ابحث في الأفلام...",
                        onSelectAll: { selectedCategoryId = nil; displayLimit = 150 },
                        onSelectCategory: { selectedCategoryId = $0.categoryId; displayLimit = 150 }
                    )

                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 18) {
                            ForEach(displayedMovies.prefix(displayLimit)) { movie in
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        catalogVM.playMovie(movie)
                                    } label: {
                                        PosterCard(title: movie.name, imageURL: movie.streamIcon)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        catalogVM.toggleFavoriteMovie(movie.streamId)
                                    } label: {
                                        Image(systemName: catalogVM.isFavorite(movieId: movie.streamId) ? "heart.fill" : "heart")
                                            .font(.caption)
                                            .foregroundStyle(catalogVM.isFavorite(movieId: movie.streamId) ? Color(red: 0.898, green: 0.035, blue: 0.078) : .white)
                                            .padding(6)
                                            .background(.black.opacity(0.65), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                }
                            }
                        }
                        .padding(16)

                        if displayedMovies.count > displayLimit {
                            Button("Load More (\(displayedMovies.count - displayLimit) remaining)") {
                                displayLimit += 150
                            }
                            .buttonStyle(.bordered)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationTitle("Movies")
        }
    }
}

// MARK: - Series Library Tab (Server Order + Left Dropdown + Inline Search + Pagination)

struct SeriesLibraryView: View {
    @ObservedObject var catalogVM: CatalogViewModel
    @State private var selectedCategoryId: String?
    @State private var selectedSeries: SeriesItem?
    @State private var searchText: String = ""
    @State private var displayLimit: Int = 150

    var selectedCategoryTitle: String {
        if let id = selectedCategoryId,
           let cat = catalogVM.seriesCategories.first(where: { $0.categoryId == id }) {
            return cat.categoryName
        }
        return "All Series (\(catalogVM.seriesList.count))"
    }

    var displayedSeries: [SeriesItem] {
        let base = selectedCategoryId.map { catalogVM.series(for: $0) } ?? catalogVM.seriesList
        return base.filter { catalogVM.matches($0.name, query: searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    CategoryAndSearchBar(
                        selectedTitle: selectedCategoryTitle,
                        allTitle: "All Series (\(catalogVM.seriesList.count))",
                        categories: catalogVM.seriesCategories,
                        searchText: $searchText,
                        searchPlaceholder: "ابحث في المسلسلات...",
                        onSelectAll: { selectedCategoryId = nil; displayLimit = 150 },
                        onSelectCategory: { selectedCategoryId = $0.categoryId; displayLimit = 150 }
                    )

                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 18) {
                            ForEach(displayedSeries.prefix(displayLimit)) { item in
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        selectedSeries = item
                                    } label: {
                                        PosterCard(title: item.name, imageURL: item.cover)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        catalogVM.toggleFavoriteSeries(item.seriesId)
                                    } label: {
                                        Image(systemName: catalogVM.isFavorite(seriesId: item.seriesId) ? "heart.fill" : "heart")
                                            .font(.caption)
                                            .foregroundStyle(catalogVM.isFavorite(seriesId: item.seriesId) ? Color(red: 0.898, green: 0.035, blue: 0.078) : .white)
                                            .padding(6)
                                            .background(.black.opacity(0.65), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                }
                            }
                        }
                        .padding(16)

                        if displayedSeries.count > displayLimit {
                            Button("Load More (\(displayedSeries.count - displayLimit) remaining)") {
                                displayLimit += 150
                            }
                            .buttonStyle(.bordered)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationTitle("Series")
            .navigationDestination(item: $selectedSeries) { series in
                SeriesDetailView(series: series, catalogVM: catalogVM)
            }
        }
    }
}

// MARK: - Top-Left Dropdown + Inline Search Bar

private struct CategoryAndSearchBar: View {
    let selectedTitle: String
    let allTitle: String
    let categories: [MediaCategory]
    @Binding var searchText: String
    let searchPlaceholder: String
    let onSelectAll: () -> Void
    let onSelectCategory: (MediaCategory) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Button(allTitle, action: onSelectAll)
                Divider()
                ForEach(categories) { cat in
                    Button(cat.categoryName) {
                        onSelectCategory(cat)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                    Text(selectedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(searchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
