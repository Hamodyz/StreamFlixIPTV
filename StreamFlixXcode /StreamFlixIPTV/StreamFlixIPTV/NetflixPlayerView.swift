import SwiftUI
import Combine
import VLCKitSPM
import StreamFlixCore

// MARK: - Direct VLCKit Player Controller (iOS + iPadOS + macOS + tvOS)

@MainActor
final class VLCPlayerController: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    @Published var isPlaying = false
    @Published var isBuffering = true
    @Published var currentTime: Double = 0
    @Published var totalTime: Double = 0
    @Published var playbackRate: Float = 1.0
    @Published var errorMessage: String?
    @Published var highQualityMode: Bool = true
    @Published var lowLatencyBuffer: Bool = true

    @Published var audioTracks: [(index: Int32, name: String)] = []
    @Published var currentAudioIndex: Int32 = -1
    @Published var subtitleTracks: [(index: Int32, name: String)] = []
    @Published var currentSubtitleIndex: Int32 = -1

    let mediaPlayer = VLCMediaPlayer()

    private var currentItem: PlayableItem?
    private var progressStore: WatchProgressStore?
    private var pendingInitialSeek: Double?
    private var lastSavedAt: Date = .distantPast
    private var didTriggerEndForItemId: String?
    var onEpisodeFinished: (() -> Void)?

    override init() {
        super.init()
        mediaPlayer.delegate = self
    }

    func load(item: PlayableItem, progressStore: WatchProgressStore, overrideURL: URL? = nil) {
        self.currentItem = item
        self.progressStore = progressStore
        self.errorMessage = nil
        self.isBuffering = true
        self.currentTime = 0
        self.totalTime = 0
        self.playbackRate = 1.0
        self.didTriggerEndForItemId = nil
        self.audioTracks = []
        self.subtitleTracks = []

        if item.kind != .live, let saved = progressStore.savedPosition(for: item.id), saved > 2 {
            self.pendingInitialSeek = saved
        } else {
            self.pendingInitialSeek = nil
        }

        let targetURL = overrideURL ?? item.streamURL
        let media = VLCMedia(url: targetURL)
        let cachingMs: Int
        if lowLatencyBuffer {
            cachingMs = (item.kind == .live) ? 500 : 800
        } else {
            cachingMs = (item.kind == .live) ? 1500 : 2500
        }

        var options: [String: Any] = [
            "network-caching": cachingMs,
            "http-user-agent": "VLC/3.0.18",
            "http-reconnect": true,
            "clock-jitter": 0,
            "videotoolbox": true
        ]
        if highQualityMode {
            options["avcodec-hw"] = "any"
        }
        media.addOptions(options)

        mediaPlayer.media = media
        mediaPlayer.play()
    }

    func togglePlayPause() -> Bool {
        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
            isPlaying = false
            saveCheckpointNow()
            return true
        } else {
            mediaPlayer.play()
            isPlaying = true
            return false
        }
    }

    func pause() {
        mediaPlayer.pause()
        isPlaying = false
        saveCheckpointNow()
    }

    func play() {
        mediaPlayer.play()
        isPlaying = true
    }

    func seek(to seconds: Double) {
        let clamped = max(0, totalTime > 0 ? min(seconds, totalTime) : seconds)
        mediaPlayer.time = VLCTime(int: Int32(clamped * 1000))
        currentTime = clamped
        if !mediaPlayer.isPlaying {
            mediaPlayer.play()
            isPlaying = true
        }
        saveCheckpointNow()
    }

    func skip(by delta: Double) {
        seek(to: currentTime + delta)
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        mediaPlayer.rate = rate
    }

    func selectAudioTrack(_ index: Int32) {
        mediaPlayer.currentAudioTrackIndex = index
        currentAudioIndex = index
    }

    func selectSubtitleTrack(_ index: Int32) {
        mediaPlayer.currentVideoSubTitleIndex = index
        currentSubtitleIndex = index
    }

    func stop() {
        saveCheckpointNow()
        mediaPlayer.stop()
        mediaPlayer.media = nil
        isPlaying = false
    }

    func saveCheckpointNow() {
        guard pendingInitialSeek == nil else { return }
        guard let item = currentItem, item.kind != .live, totalTime > 0, currentTime > 2 else { return }
        lastSavedAt = Date()
        progressStore?.updateProgress(item: item, position: currentTime, duration: totalTime)
    }

    private func refreshTracks() {
        if let names = mediaPlayer.audioTrackNames as? [String],
           let indexes = mediaPlayer.audioTrackIndexes as? [NSNumber] {
            audioTracks = zip(indexes, names).map { ($0.int32Value, $1) }
            currentAudioIndex = mediaPlayer.currentAudioTrackIndex
        }
        if let subNames = mediaPlayer.videoSubTitlesNames as? [String],
           let subIndexes = mediaPlayer.videoSubTitlesIndexes as? [NSNumber] {
            subtitleTracks = zip(subIndexes, subNames).map { ($0.int32Value, $1) }
            currentSubtitleIndex = mediaPlayer.currentVideoSubTitleIndex
        }
    }

    // MARK: - VLCMediaPlayerDelegate

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch self.mediaPlayer.state {
            case .opening:
                self.isBuffering = true
            case .buffering:
                if !self.mediaPlayer.isPlaying {
                    self.isBuffering = true
                } else {
                    self.isBuffering = false
                }
            case .playing:
                self.isBuffering = false
                self.isPlaying = true
                self.refreshTracks()
                let tot = Double(self.mediaPlayer.media?.length.intValue ?? 0) / 1000.0
                if tot > 0 { self.totalTime = tot }
                if let target = self.pendingInitialSeek, target > 2, tot > 0, self.mediaPlayer.isSeekable {
                    self.pendingInitialSeek = nil
                    self.lastSavedAt = Date()
                    self.seek(to: target)
                }
            case .paused:
                self.isPlaying = false
                self.isBuffering = false
                self.saveCheckpointNow()
            case .ended:
                self.isPlaying = false
                self.isBuffering = false
                if let item = self.currentItem, item.kind == .episode, self.didTriggerEndForItemId != item.id {
                    self.didTriggerEndForItemId = item.id
                    self.onEpisodeFinished?()
                }
            case .error:
                self.isBuffering = false
                self.isPlaying = false
                self.errorMessage = "Could not play this stream. Check your connection or try another server."
            default:
                break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let cur = Double(self.mediaPlayer.time.intValue) / 1000.0
            let tot = Double(self.mediaPlayer.media?.length.intValue ?? 0) / 1000.0
            if cur.isFinite && cur >= 0 { self.currentTime = cur }
            if tot.isFinite && tot > 0 { self.totalTime = tot }
            if self.mediaPlayer.isPlaying {
                self.isBuffering = false
                self.isPlaying = true
            }
            if let target = self.pendingInitialSeek, target > 2, tot > 0, self.mediaPlayer.isSeekable {
                self.pendingInitialSeek = nil
                self.lastSavedAt = Date()
                self.seek(to: target)
                return
            }
            if Date().timeIntervalSince(self.lastSavedAt) >= 5.0 {
                self.saveCheckpointNow()
            }
        }
    }
}

// MARK: - Netflix-Style Player View (Powered by VLCKit)

struct NetflixPlayerView: View {
    let item: PlayableItem
    @ObservedObject var catalogVM: CatalogViewModel
    @ObservedObject var engine: NetflixPlayerEngine
    @ObservedObject var sleepGuard: SleepGuardManager
    let onDismiss: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var vlc = VLCPlayerController()
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var scrubPreviewTime: Double = 0
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var nextEpisodeCountdown: Int?
    @State private var nextEpisodeTask: Task<Void, Never>?
    @State private var useRawTSForLive = false
    @State private var resolvedNextEpisode: PlayableItem.NextEpisodeRef?

    // Live TV Zapping Drawer & OSD Banner
    @State private var showChannelDrawer = false
    @State private var showChannelBanner = false
    @State private var bannerTask: Task<Void, Never>?
    @State private var showEpisodeDrawer = false
    @State private var episodeSeasons: [Int: [EpisodeItem]] = [:]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VLCVideoSurface(
                mediaPlayer: vlc.mediaPlayer,
                onSingleTap: {
                    sleepGuard.registerUserInteraction()
                    if showChannelDrawer {
                        withAnimation(.easeInOut(duration: 0.2)) { showChannelDrawer = false }
                    } else if showEpisodeDrawer {
                        withAnimation(.easeInOut(duration: 0.2)) { showEpisodeDrawer = false }
                    } else if item.kind != .live {
                        let pausedNow = vlc.togglePlayPause()
                        if pausedNow {
                            hideTask?.cancel()
                            withAnimation(.easeInOut(duration: 0.2)) { showControls = true }
                        } else {
                            revealControlsTemporarily()
                        }
                    } else {
                        revealControlsTemporarily()
                    }
                },
                onDoubleTapDelta: { deltaSeconds in
                    guard item.kind != .live else { return }
                    performSkip(deltaSeconds)
                },
                onHorizontalSwipeDelta: { deltaSeconds in
                    guard item.kind != .live else { return }
                    performSkip(deltaSeconds)
                }
            )
            .ignoresSafeArea()

            // Center Paused Indicator
            if !vlc.isPlaying && !vlc.isBuffering && vlc.errorMessage == nil && item.kind != .live && !sleepGuard.isShowingAreYouStillWatching {
                VStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .padding(24)
                        .background(.black.opacity(0.65), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5))
                    Text("PAUSED")
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            // Buffering Spinner
            if vlc.isBuffering && vlc.errorMessage == nil {
                ProgressView()
                    .tint(Color(red: 0.898, green: 0.035, blue: 0.078))
                    .scaleEffect(1.4)
                    .allowsHitTesting(false)
            }

            // Skip / Speed Toast
            if let toastText {
                Text(toastText)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.78), in: Capsule())
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Error Card
            if let err = vlc.errorMessage {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Button("Retry") {
                            vlc.load(item: item, progressStore: engine.progressStore)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Close") {
                            vlc.stop()
                            onDismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(24)
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
            }

            // Auto-Hiding Top & Bottom Netflix Controls
            if showControls && !sleepGuard.isShowingAreYouStillWatching && vlc.errorMessage == nil {
                VStack {
                    topBar
                    Spacer()
                    if item.kind == .episode && nextEpisodeCountdown == nil {
                        HStack(spacing: 10) {
                            if vlc.totalTime > 120 && vlc.currentTime < 180 {
                                Button {
                                    sleepGuard.registerUserInteraction()
                                    vlc.skip(by: 85)
                                    showToast("⏭️ Skipped Intro (+85s)")
                                } label: {
                                    Label("Skip Intro", systemImage: "forward.frame.fill")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.6), lineWidth: 1.2))
                                        .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                            if item.seriesId != nil {
                                Button {
                                    openEpisodeDrawer()
                                } label: {
                                    Label("Episodes", systemImage: "list.bullet")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            if let next = (resolvedNextEpisode ?? item.nextEpisode) {
                                Button { playNextEpisodeNow(next) } label: {
                                    Label("Next Episode", systemImage: "forward.end.fill")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(.white, in: RoundedRectangle(cornerRadius: 8))
                                        .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                    }
                    if item.kind != .live && vlc.totalTime > 0 {
                        bottomSeekBar
                    }
                }
                .transition(.opacity)
            }

            // Floating Skip Intro Button (visible in first 3 mins even when controls auto-hide)
            if !showControls && item.kind == .episode && nextEpisodeCountdown == nil && !sleepGuard.isShowingAreYouStillWatching && vlc.errorMessage == nil && vlc.totalTime > 120 && vlc.currentTime >= 2 && vlc.currentTime < 180 {
                VStack {
                    Spacer()
                    HStack {
                        Button {
                            sleepGuard.registerUserInteraction()
                            vlc.skip(by: 85)
                            showToast("⏭️ Skipped Intro (+85s)")
                        } label: {
                            Label("Skip Intro", systemImage: "forward.frame.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.6), lineWidth: 1.2))
                                .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 24)
                        .padding(.bottom, 28)
                        Spacer()
                    }
                }
                .transition(.opacity)
            }

            // Next Episode Countdown Card
            if let countdown = nextEpisodeCountdown, let next = (resolvedNextEpisode ?? item.nextEpisode) {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Next Episode in \(countdown)s")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(cleanEpisodeDisplayTitle(next.title))
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            HStack(spacing: 10) {
                                Button("Play Now") { playNextEpisodeNow(next) }
                                    .buttonStyle(.borderedProminent)
                                Button("Cancel") { cancelNextEpisodeCountdown() }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: 320)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(24)
                    }
                }
            }

            // Live TV Satellite Channel Banner
            if item.kind == .live && showChannelBanner {
                VStack {
                    Spacer()
                    HStack(spacing: 14) {
                        Circle().fill(Color.red).frame(width: 10, height: 10)
                        AsyncImage(url: URL(string: item.artworkURL ?? "")) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "tv").foregroundStyle(.white)
                            }
                        }
                        .frame(width: 44, height: 32)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("LIVE TV • Use ↑ / ↓ or CH+ / CH- to flip channels")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 70)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Slide-Out TV Channel Zapping Drawer
            if item.kind == .live && showChannelDrawer {
                HStack(spacing: 0) {
                    LiveChannelDrawer(
                        channels: catalogVM.activeLiveChannelList.isEmpty ? catalogVM.liveChannels : catalogVM.activeLiveChannelList,
                        currentChannelId: catalogVM.currentLiveChannel?.streamId,
                        onSelect: { channel in
                            catalogVM.playChannel(channel)
                            triggerChannelBanner()
                        },
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) { showChannelDrawer = false }
                        }
                    )
                    Spacer()
                }
                .transition(.move(edge: .leading))
                .zIndex(50)
            }

            // Slide-Out Series Episodes Drawer
            if item.kind == .episode && showEpisodeDrawer {
                HStack(spacing: 0) {
                    SeriesEpisodeDrawer(
                        seasons: episodeSeasons,
                        initialSeason: item.seasonNumber ?? (episodeSeasons.keys.sorted().first ?? 1),
                        currentEpisodeId: item.id.replacingOccurrences(of: "episode-", with: ""),
                        onSelect: { seasonNum, epIdx in
                            withAnimation(.easeInOut(duration: 0.2)) { showEpisodeDrawer = false }
                            if let sid = item.seriesId {
                                let baseTitle = item.title.components(separatedBy: " • ").first ?? item.title
                                catalogVM.playEpisode(
                                    seriesId: sid,
                                    fallbackTitle: baseTitle,
                                    fallbackArtwork: item.artworkURL,
                                    seasonNumber: seasonNum,
                                    episodeIndex: epIdx,
                                    allSeasons: episodeSeasons
                                )
                            }
                        },
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) { showEpisodeDrawer = false }
                        }
                    )
                    Spacer()
                }
                .transition(.move(edge: .leading))
                .zIndex(50)
            }

            // Netflix "Are You Still Watching?" Sleep Guard Modal
            if sleepGuard.isShowingAreYouStillWatching {
                AreYouStillWatchingOverlay(
                    secondsRemaining: sleepGuard.countdownSecondsRemaining,
                    onContinue: {
                        sleepGuard.dismissPromptAndContinue()
                        if let next = item.nextEpisode {
                            playNextEpisodeNow(next)
                        } else {
                            vlc.play()
                        }
                    },
                    onExit: {
                        sleepGuard.stopAndExit()
                        vlc.stop()
                        onDismiss()
                    }
                )
                .zIndex(60)
            }
        }
        #if os(macOS)
        .onContinuousHover { phase in
            if case .active = phase {
                revealControlsTemporarily()
            }
        }
        #endif
        .focusable(true)
        .onKeyPress(.leftArrow) {
            guard item.kind != .live else { return .ignored }
            performSkip(-10)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard item.kind != .live else { return .ignored }
            performSkip(10)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard item.kind == .live else { return .ignored }
            zapChannel(offset: 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard item.kind == .live else { return .ignored }
            zapChannel(offset: -1)
            return .handled
        }
        .onAppear {
            vlc.onEpisodeFinished = { handleEpisodeFinished() }
            vlc.load(item: item, progressStore: engine.progressStore)
            refreshResolvedNextEpisode()
            revealControlsTemporarily()
            if item.kind == .live { triggerChannelBanner() }
        }
        .onChange(of: item.id) { _, _ in
            cancelNextEpisodeCountdown()
            useRawTSForLive = false
            vlc.load(item: item, progressStore: engine.progressStore)
            refreshResolvedNextEpisode()
            revealControlsTemporarily()
            if item.kind == .live { triggerChannelBanner() }
        }
        .onChange(of: vlc.isPlaying) { _, playing in
            if playing {
                revealControlsTemporarily()
            }
        }
        .onDisappear {
            hideTask?.cancel()
            cancelNextEpisodeCountdown()
            vlc.stop()
        }
    }

    // MARK: - Top & Bottom Bars

    private var isCompactWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var closeButton: some View {
        Button {
            cancelNextEpisodeCountdown()
            vlc.stop()
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.6), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var titlePill: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.kind == .episode ? cleanEpisodeDisplayTitle(item.title) : item.title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
            if item.kind != .episode, let sub = item.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var navigationActionButtons: some View {
        if item.kind == .live {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { showChannelDrawer.toggle() }
            } label: {
                Label("Channels", systemImage: "list.bullet.rectangle")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.65), in: Capsule())
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Button { zapChannel(offset: -1) } label: {
                    Label("CH -", systemImage: "chevron.down")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.65), in: Capsule())
                }
                .buttonStyle(.plain)

                Button { zapChannel(offset: 1) } label: {
                    Label("CH +", systemImage: "chevron.up")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.65), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 6) {
                Button { performSkip(-10) } label: {
                    Label("-10s", systemImage: "gobackward.10")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.65), in: Capsule())
                }
                .buttonStyle(.plain)

                Button { performSkip(10) } label: {
                    Label("+10s", systemImage: "goforward.10")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.65), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                closeButton
                if !isCompactWidth {
                    navigationActionButtons
                }
                titlePill
                Spacer()

            // Quality / Buffer / Audio / Subtitle Tracks Menu
            Menu {
                if item.kind == .live {
                    Section("Stream Quality") {
                        Button(useRawTSForLive ? "Auto HLS (.m3u8)" : "✓ Auto HLS (.m3u8)") {
                            useRawTSForLive = false
                            let hlsURL = item.streamURL.deletingPathExtension().appendingPathExtension("m3u8")
                            vlc.load(item: item, progressStore: engine.progressStore, overrideURL: hlsURL)
                            showToast("HLS Stream")
                        }
                        Button(useRawTSForLive ? "✓ Original Raw (.ts)" : "Original Raw (.ts)") {
                            useRawTSForLive = true
                            let tsURL = item.streamURL.deletingPathExtension().appendingPathExtension("ts")
                            vlc.load(item: item, progressStore: engine.progressStore, overrideURL: tsURL)
                            showToast("Original Raw Quality")
                        }
                    }
                }

                Section("Buffer & Speed") {
                    Button(vlc.lowLatencyBuffer ? "✓ Fast Start (Low Buffer)" : "Fast Start (Low Buffer)") {
                        vlc.lowLatencyBuffer = true
                        vlc.load(item: item, progressStore: engine.progressStore)
                        showToast("Fast Start Enabled")
                    }
                    Button(!vlc.lowLatencyBuffer ? "✓ Smooth Anti-Buffer" : "Smooth Anti-Buffer") {
                        vlc.lowLatencyBuffer = false
                        vlc.load(item: item, progressStore: engine.progressStore)
                        showToast("Smooth Buffer Enabled")
                    }
                }

                if !vlc.audioTracks.isEmpty {
                    Section("Audio Track") {
                        ForEach(vlc.audioTracks, id: \.index) { track in
                            Button(track.index == vlc.currentAudioIndex ? "✓ \(track.name)" : track.name) {
                                vlc.selectAudioTrack(track.index)
                                showToast(track.name)
                            }
                        }
                    }
                }

                if !vlc.subtitleTracks.isEmpty {
                    Section("Subtitles") {
                        ForEach(vlc.subtitleTracks, id: \.index) { sub in
                            Button(sub.index == vlc.currentSubtitleIndex ? "✓ \(sub.name)" : sub.name) {
                                vlc.selectSubtitleTrack(sub.index)
                                showToast(sub.name)
                            }
                        }
                    }
                }
            } label: {
                Label("HD", systemImage: "slider.horizontal.3")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.65), in: Capsule())
            }

            if item.kind != .live {
                Menu {
                    ForEach([Float(1.0), 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button("\(String(format: "%.2g", rate))x") {
                            vlc.setRate(rate)
                            showToast("\(String(format: "%.2g", rate))x Speed")
                        }
                    }
                } label: {
                    Text("\(String(format: "%.2g", vlc.playbackRate))x")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.65), in: Capsule())
                }
            }

            if let sleepRem = sleepGuard.sleepTimerRemainingSeconds {
                Text("Sleep: \(formatTime(Double(sleepRem)))")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.65), in: Capsule())
                    .foregroundStyle(.white)
            }

            Menu {
                Button("15 Minutes") { sleepGuard.startSleepTimer(minutes: 15) { vlc.stop(); onDismiss() } }
                Button("30 Minutes") { sleepGuard.startSleepTimer(minutes: 30) { vlc.stop(); onDismiss() } }
                Button("45 Minutes") { sleepGuard.startSleepTimer(minutes: 45) { vlc.stop(); onDismiss() } }
                Button("60 Minutes") { sleepGuard.startSleepTimer(minutes: 60) { vlc.stop(); onDismiss() } }
                if sleepGuard.sleepTimerRemainingSeconds != nil {
                    Divider()
                    Button("Cancel Sleep Timer", role: .destructive) { sleepGuard.cancelSleepTimer() }
                }
            } label: {
                Image(systemName: "moon.zzz.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.6), in: Circle())
            }

            #if os(macOS)
            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            #endif
            }

            if isCompactWidth {
                HStack(spacing: 8) {
                    navigationActionButtons
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var bottomSeekBar: some View {
        HStack(spacing: 12) {
            Text(formatTime(isScrubbing ? scrubPreviewTime : vlc.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 58, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubPreviewTime : vlc.currentTime },
                    set: { newVal in
                        if !isScrubbing { isScrubbing = true }
                        scrubPreviewTime = newVal
                        revealControlsTemporarily()
                    }
                ),
                in: 0...max(vlc.totalTime, 1),
                onEditingChanged: { editing in
                    if !editing {
                        isScrubbing = false
                        vlc.seek(to: scrubPreviewTime)
                        revealControlsTemporarily()
                    }
                }
            )
            .tint(Color(red: 0.898, green: 0.035, blue: 0.078))

            Text(formatTime(vlc.totalTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 58, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Helpers

    private func revealControlsTemporarily() {
        if !showControls {
            withAnimation(.easeInOut(duration: 0.2)) { showControls = true }
        }
        hideTask?.cancel()
        guard vlc.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled && vlc.isPlaying && !isScrubbing {
                withAnimation(.easeInOut(duration: 0.25)) { showControls = false }
            }
        }
    }

    private func performSkip(_ delta: Double) {
        sleepGuard.registerUserInteraction()
        revealControlsTemporarily()
        vlc.skip(by: delta)
        showToast(delta > 0 ? "⏩ +\(Int(delta))s" : "⏪ \(Int(delta))s")
    }

    private func showToast(_ text: String) {
        withAnimation(.easeInOut(duration: 0.15)) { toastText = text }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) { toastText = nil }
            }
        }
    }

    private func openEpisodeDrawer() {
        withAnimation(.easeInOut(duration: 0.22)) { showEpisodeDrawer.toggle() }
        if episodeSeasons.isEmpty, let sid = item.seriesId {
            Task {
                episodeSeasons = await catalogVM.fetchEpisodesBySeason(seriesId: sid)
            }
        }
    }

    private func refreshResolvedNextEpisode() {
        resolvedNextEpisode = item.nextEpisode
        if item.kind == .episode && item.nextEpisode == nil {
            Task {
                let found = await catalogVM.resolveNextEpisode(for: item)
                if !Task.isCancelled {
                    resolvedNextEpisode = found
                }
            }
        }
    }

    private func handleEpisodeFinished() {
        vlc.saveCheckpointNow()
        guard let next = (resolvedNextEpisode ?? item.nextEpisode) else { return }
        let allowed = sleepGuard.shouldAllowAutoPlayNextEpisode {
            vlc.stop()
            onDismiss()
        }
        guard allowed else { return }
        nextEpisodeCountdown = 5
        nextEpisodeTask?.cancel()
        nextEpisodeTask = Task {
            while let count = nextEpisodeCountdown, count > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                nextEpisodeCountdown = (nextEpisodeCountdown ?? 1) - 1
            }
            if !Task.isCancelled {
                nextEpisodeCountdown = nil
                playNextEpisodeNow(next)
            }
        }
    }

    private func cleanEpisodeDisplayTitle(_ rawTitle: String) -> String {
        rawTitle.components(separatedBy: " — ").first ?? rawTitle
    }

    private func playNextEpisodeNow(_ next: PlayableItem.NextEpisodeRef) {
        cancelNextEpisodeCountdown()
        let nextItem = PlayableItem(
            id: "episode-\(next.episodeId)",
            title: cleanEpisodeDisplayTitle(next.title),
            subtitle: nil,
            artworkURL: next.artworkURL,
            streamURL: next.streamURL,
            kind: .episode,
            seriesId: item.seriesId,
            seasonNumber: next.seasonNumber,
            episodeNumber: next.episodeNumber,
            nextEpisode: nil
        )
        catalogVM.activePlayerItem = nextItem
    }

    private func cancelNextEpisodeCountdown() {
        nextEpisodeTask?.cancel()
        nextEpisodeTask = nil
        nextEpisodeCountdown = nil
    }

    private func zapChannel(offset: Int) {
        sleepGuard.registerUserInteraction()
        catalogVM.switchLiveChannel(offset: offset)
        triggerChannelBanner()
    }

    private func triggerChannelBanner() {
        withAnimation(.easeInOut(duration: 0.2)) { showChannelBanner = true }
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.25)) { showChannelBanner = false }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        return hrs > 0 ? String(format: "%d:%02d:%02d", hrs, mins, secs) : String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Cross-Platform VLC Drawable View (Single Tap + Double Tap Left/Right + Horizontal Swipe)

#if os(iOS) || os(tvOS)
struct VLCVideoSurface: UIViewRepresentable {
    let mediaPlayer: VLCMediaPlayer
    let onSingleTap: () -> Void
    let onDoubleTapDelta: (Double) -> Void
    let onHorizontalSwipeDelta: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSingleTap: onSingleTap,
            onDoubleTapDelta: onDoubleTapDelta,
            onHorizontalSwipeDelta: onHorizontalSwipeDelta
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        mediaPlayer.drawable = view
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject {
        let onSingleTap: () -> Void
        let onDoubleTapDelta: (Double) -> Void
        let onHorizontalSwipeDelta: (Double) -> Void

        init(
            onSingleTap: @escaping () -> Void,
            onDoubleTapDelta: @escaping (Double) -> Void,
            onHorizontalSwipeDelta: @escaping (Double) -> Void
        ) {
            self.onSingleTap = onSingleTap
            self.onDoubleTapDelta = onDoubleTapDelta
            self.onHorizontalSwipeDelta = onHorizontalSwipeDelta
        }

        func attach(to view: UIView) {
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleTap)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.numberOfTapsRequired = 1
            tap.require(toFail: doubleTap)
            view.addGestureRecognizer(tap)

            #if os(iOS)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            tap.require(toFail: pan)
            view.addGestureRecognizer(pan)
            #endif
        }

        @objc private func handleTap() {
            Task { @MainActor in onSingleTap() }
        }

        @objc private func handleDoubleTap(_ sender: UITapGestureRecognizer) {
            guard let view = sender.view else { return }
            let loc = sender.location(in: view)
            let delta: Double = (loc.x < view.bounds.width * 0.45) ? -10 : 10
            Task { @MainActor in onDoubleTapDelta(delta) }
        }

        #if os(iOS)
        @objc private func handlePan(_ sender: UIPanGestureRecognizer) {
            guard sender.state == .ended, let view = sender.view else { return }
            let delta = Double(sender.translation(in: view).x) * 0.25
            if abs(delta) >= 2 {
                Task { @MainActor in onHorizontalSwipeDelta(delta) }
            }
        }
        #endif
    }
}
#elseif os(macOS)
struct VLCVideoSurface: NSViewRepresentable {
    let mediaPlayer: VLCMediaPlayer
    let onSingleTap: () -> Void
    let onDoubleTapDelta: (Double) -> Void
    let onHorizontalSwipeDelta: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        mediaPlayer.drawable = view
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator: NSObject {
        let onSingleTap: () -> Void
        init(onSingleTap: @escaping () -> Void) { self.onSingleTap = onSingleTap }

        func attach(to view: NSView) {
            let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
            view.addGestureRecognizer(click)
        }

        @objc private func handleClick() {
            Task { @MainActor in onSingleTap() }
        }
    }
}
#endif

// MARK: - Slide-Out Satellite-Style Channel Drawer & Sleep Guard Overlay

private struct LiveChannelDrawer: View {
    let channels: [LiveChannel]
    let currentChannelId: Int?
    let onSelect: (LiveChannel) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Live Channels").font(.headline).foregroundStyle(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.black.opacity(0.95))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(channels.enumerated()), id: \.element.id) { index, ch in
                            let isCurrent = (ch.streamId == currentChannelId)
                            Button { onSelect(ch) } label: {
                                HStack(spacing: 10) {
                                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                                    AsyncImage(url: URL(string: ch.streamIcon ?? "")) { phase in
                                        if let img = phase.image { img.resizable().aspectRatio(contentMode: .fit) }
                                        else { Image(systemName: "tv").foregroundStyle(.secondary) }
                                    }
                                    .frame(width: 34, height: 24)
                                    Text(ch.name).font(.subheadline.weight(isCurrent ? .bold : .regular)).foregroundStyle(.white).lineLimit(1)
                                    Spacer()
                                    if isCurrent { Circle().fill(Color.red).frame(width: 8, height: 8) }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(isCurrent ? Color(red: 0.898, green: 0.035, blue: 0.078).opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .id(ch.streamId)
                        }
                    }
                    .padding(10)
                }
                .onAppear { if let currentChannelId { proxy.scrollTo(currentChannelId, anchor: .center) } }
            }
        }
        .frame(width: 310)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.85))
    }
}

private struct SeriesEpisodeDrawer: View {
    let seasons: [Int: [EpisodeItem]]
    let initialSeason: Int
    let currentEpisodeId: String
    let onSelect: (Int, Int) -> Void
    let onClose: () -> Void

    @State private var selectedSeason: Int = 1

    var sortedSeasons: [Int] { seasons.keys.sorted() }
    var episodes: [EpisodeItem] { seasons[selectedSeason] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Episodes").font(.headline).foregroundStyle(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.black.opacity(0.95))

            if sortedSeasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sortedSeasons, id: \.self) { sNum in
                            Button {
                                selectedSeason = sNum
                            } label: {
                                Text("S\(sNum)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedSeason == sNum ? Color(red: 0.898, green: 0.035, blue: 0.078) : Color.white.opacity(0.15), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(Color.black.opacity(0.85))
            }

            if episodes.isEmpty {
                VStack { ProgressView().tint(.white) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(episodes.enumerated()), id: \.element.id) { index, ep in
                                let isCurrent = (ep.id == currentEpisodeId)
                                Button { onSelect(selectedSeason, index) } label: {
                                    HStack(spacing: 10) {
                                        Text("E\(ep.displayEpisodeNumber)")
                                            .font(.caption.monospacedDigit().bold())
                                            .foregroundStyle(isCurrent ? .white : Color(red: 0.898, green: 0.035, blue: 0.078))
                                            .frame(width: 42, alignment: .leading)
                                        Text(ep.title)
                                            .font(.subheadline.weight(isCurrent ? .bold : .regular))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                        Spacer()
                                        if isCurrent { Circle().fill(Color.red).frame(width: 8, height: 8) }
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(isCurrent ? Color(red: 0.898, green: 0.035, blue: 0.078).opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .id(ep.id)
                            }
                        }
                        .padding(10)
                    }
                    .onAppear {
                        selectedSeason = initialSeason
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo(currentEpisodeId, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 330)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.88))
        .onAppear { selectedSeason = initialSeason }
    }
}

private struct AreYouStillWatchingOverlay: View {
    let secondsRemaining: Int
    let onContinue: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "moon.stars.fill").font(.system(size: 46)).foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                Text("Are you still watching?").font(.title2.bold()).foregroundStyle(.white)
                Text("Playback paused so you don't lose your place. Stopping automatically in \(secondsRemaining)s.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
                HStack(spacing: 14) {
                    Button(action: onContinue) {
                        Text("Continue Watching").fontWeight(.bold).padding(.horizontal, 22).padding(.vertical, 12)
                            .background(.white).foregroundStyle(.black).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Button(action: onExit) {
                        Text("I'm Done").fontWeight(.semibold).padding(.horizontal, 22).padding(.vertical, 12)
                            .background(Color.white.opacity(0.15)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(28)
        }
    }
}
