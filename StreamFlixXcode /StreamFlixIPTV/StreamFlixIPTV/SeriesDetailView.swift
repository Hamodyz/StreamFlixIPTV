import SwiftUI
import StreamFlixCore

struct SeriesDetailView: View {
    let series: SeriesItem
    @ObservedObject var catalogVM: CatalogViewModel
    @EnvironmentObject private var progressStore: WatchProgressStore

    @State private var seasons: [Int: [EpisodeItem]] = [:]
    @State private var selectedSeason: Int = 1
    @State private var isLoading = true
    @State private var metadata: SeriesInfoResponse.SeriesMetadata?

    private var lastWatchedRecord: WatchProgressRecord? {
        progressStore.latestRecord(forSeriesId: series.seriesId)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AsyncImage(url: URL(string: metadata?.cover ?? series.cover ?? "")) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.white.opacity(0.1)
                        }
                    }
                    .frame(height: 260)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 12) {
                            Text(series.name)
                                .font(.title.bold())
                                .foregroundStyle(.white)

                            Spacer()

                            let isFav = catalogVM.isFavorite(seriesId: series.seriesId)
                            Button {
                                catalogVM.toggleFavoriteSeries(series.seriesId)
                            } label: {
                                Label(isFav ? "In My List" : "My List", systemImage: isFav ? "heart.fill" : "heart")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isFav ? Color(red: 0.898, green: 0.035, blue: 0.078) : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.14), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        if let lastRec = lastWatchedRecord {
                            Button {
                                catalogVM.activePlayerItem = lastRec.item
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    let sNum = lastRec.item.seasonNumber ?? 1
                                    let eNum = lastRec.item.episodeNumber ?? 1
                                    Text(lastRec.isCompleted ? "Last Watched: S\(sNum):E\(eNum)" : "Resume S\(sNum):E\(eNum)")
                                        .fontWeight(.bold)
                                }
                                .font(.subheadline)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }

                        if let plot = metadata?.plot ?? series.plot, !plot.isEmpty {
                            Text(plot)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)

                    if isLoading {
                        ProgressView()
                            .tint(Color(red: 0.898, green: 0.035, blue: 0.078))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if !seasons.isEmpty {
                        Picker("Season", selection: $selectedSeason) {
                            ForEach(seasons.keys.sorted(), id: \.self) { seasonNum in
                                Text("Season \(seasonNum)").tag(seasonNum)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 16)

                        let currentEpisodes = seasons[selectedSeason] ?? []
                        LazyVStack(spacing: 12) {
                            ForEach(Array(currentEpisodes.enumerated()), id: \.element.id) { index, episode in
                                let epProgress = progressStore.progressRecord(forEpisodeId: episode.id)
                                let isLastWatched = lastWatchedRecord?.id == "episode-\(episode.id)"
                                Button {
                                    if let playable = catalogVM.apiClient?.buildPlayableEpisode(
                                        series: series,
                                        seasonNumber: selectedSeason,
                                        episodeIndex: index,
                                        seasonEpisodes: currentEpisodes,
                                        allSeasons: seasons
                                    ) {
                                        catalogVM.activePlayerItem = playable
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "play.circle.fill")
                                                .font(.title2)
                                                .foregroundStyle(isLastWatched ? Color(red: 0.898, green: 0.035, blue: 0.078) : .white)
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text("Episode \(episode.displayEpisodeNumber): \(episode.title)")
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundStyle(.white)
                                                        .lineLimit(1)
                                                    if isLastWatched {
                                                        Text(epProgress?.isCompleted == true ? "Watched" : "Continue")
                                                            .font(.caption2.bold())
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color(red: 0.898, green: 0.035, blue: 0.078).opacity(0.25), in: Capsule())
                                                            .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                                                    }
                                                }
                                                if let epPlot = episode.info?.plot, !epPlot.isEmpty {
                                                    Text(epPlot)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(2)
                                                }
                                            }
                                            Spacer()
                                        }

                                        if let epProgress, !epProgress.isCompleted, epProgress.progressFraction > 0 {
                                            ProgressView(value: epProgress.progressFraction)
                                                .tint(Color(red: 0.898, green: 0.035, blue: 0.078))
                                        }
                                    }
                                    .padding(12)
                                    .background(
                                        isLastWatched ? Color(red: 0.898, green: 0.035, blue: 0.078).opacity(0.12) : Color.white.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(series.name)
        #if os(iOS) || os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadEpisodes()
        }
    }

    private func loadEpisodes() async {
        guard let client = catalogVM.apiClient else {
            isLoading = false
            return
        }
        do {
            let info = try await client.fetchSeriesInfo(seriesId: series.seriesId)
            self.metadata = info.info
            var mapped: [Int: [EpisodeItem]] = [:]
            for (key, eps) in info.episodes ?? [:] {
                let num = Int(key) ?? 1
                mapped[num] = eps.sorted { $0.episodeNum < $1.episodeNum }
            }
            self.seasons = mapped
            if let lastSeason = lastWatchedRecord?.item.seasonNumber, mapped[lastSeason] != nil {
                self.selectedSeason = lastSeason
            } else {
                self.selectedSeason = mapped.keys.sorted().first ?? 1
            }
        } catch {
            // Keep empty state gracefully
        }
        isLoading = false
    }
}
