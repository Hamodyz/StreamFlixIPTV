import SwiftUI
import StreamFlixCore

struct NetflixHomeView: View {
    @ObservedObject var catalogVM: CatalogViewModel
    @ObservedObject var progressStore: WatchProgressStore

    @State private var selectedSeries: SeriesItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if catalogVM.isLoading && catalogVM.movies.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(Color(red: 0.898, green: 0.035, blue: 0.078))
                            .scaleEffect(1.3)
                        Text("Loading your library...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            if let hero = catalogVM.featuredMovie {
                                HeroBannerView(movie: hero) {
                                    catalogVM.playMovie(hero)
                                }
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
}

private struct HeroBannerView: View {
    let movie: VODMovie
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: URL(string: movie.streamIcon ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.gray.opacity(0.25)
                }
            }
            .frame(height: 400)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.65), .black],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 12) {
                Text(movie.name)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Button(action: onPlay) {
                    Label("Play", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
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

                                Text(record.item.title)
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
