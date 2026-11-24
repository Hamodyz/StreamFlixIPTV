import SwiftUI
import StreamFlixCore

struct SeriesDetailView: View {
    let series: SeriesItem
    @ObservedObject var catalogVM: CatalogViewModel

    @State private var seasons: [Int: [EpisodeItem]] = [:]
    @State private var selectedSeason: Int = 1
    @State private var isLoading = true
    @State private var metadata: SeriesInfoResponse.SeriesMetadata?

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

                    VStack(alignment: .leading, spacing: 8) {
                        Text(series.name)
                            .font(.title.bold())
                            .foregroundStyle(.white)

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
                                    HStack(spacing: 12) {
                                        Image(systemName: "play.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.white)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Episode \(episode.episodeNum): \(episode.title)")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            if let epPlot = episode.info?.plot, !epPlot.isEmpty {
                                                Text(epPlot)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
            self.selectedSeason = mapped.keys.sorted().first ?? 1
        } catch {
            // Keep empty state gracefully
        }
        isLoading = false
    }
}
