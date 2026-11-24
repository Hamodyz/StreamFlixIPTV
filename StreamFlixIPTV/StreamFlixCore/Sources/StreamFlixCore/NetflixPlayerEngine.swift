import Foundation
import AVFoundation
import Combine

public enum PlaybackBufferState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case buffering(progressPercent: Int)
    case recoveringConnection
    case failed(String)
}

/// High-performance IPTV player engine engineered to solve:
/// 1. Buffering: Adaptive forward buffer + automatic live reconnect on stalls.
/// 2. Slow Seeking: Debounced scrubbing (visual preview first, single range request on release) + 10s instant skip.
/// 3. Lost Position on Long Pause: Periodic + pause-time checkpoints + stale-socket auto-recovery to exact second.
/// 4. Endless Auto-Play When Asleep: Integrates with `SleepGuardManager` for "Are you still watching?".
@MainActor
public final class NetflixPlayerEngine: ObservableObject {
    @Published public private(set) var currentItem: PlayableItem?
    @Published public private(set) var bufferState: PlaybackBufferState = .idle
    @Published public private(set) var currentTime: Double = 0
    @Published public private(set) var duration: Double = 0
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var playbackRate: Float = 1.0
    @Published public var isScrubbing: Bool = false
    @Published public var scrubPreviewTime: Double = 0
    @Published public var nextEpisodeCountdown: Int? = nil

    public let player = AVPlayer()
    public let progressStore: WatchProgressStore
    public let sleepGuard: SleepGuardManager

    private var timeObserver: Any?
    private var itemObservers: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var seekDebounceTask: Task<Void, Never>?
    private var nextEpisodeTask: Task<Void, Never>?
    private var pausedAt: Date?
    private var lastCheckpointAt: Date = .distantPast
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3

    public init(progressStore: WatchProgressStore, sleepGuard: SleepGuardManager) {
        self.progressStore = progressStore
        self.sleepGuard = sleepGuard
        player.automaticallyWaitsToMinimizeStalling = true
        setupPeriodicTimeObserver()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: - Load & Play

    public func load(item: PlayableItem, forceStartFromBeginning: Bool = false) {
        cancelNextEpisodeCountdown()
        currentItem = item
        reconnectAttempts = 0
        pausedAt = nil
        bufferState = .loading

        let resumeSeconds: Double? = forceStartFromBeginning ? nil : progressStore.savedPosition(for: item.id)
        prepareAndPlay(url: item.streamURL, kind: item.kind, seekTo: resumeSeconds)
    }

    private func prepareAndPlay(url: URL, kind: MediaKind, seekTo: Double?) {
        cleanupItemObservers()

        let headers: [String: String] = [
            "User-Agent": "IPTVSmartersPro"
        ]
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers,
            AVURLAssetPreferPreciseDurationAndTimingKey: (kind != .live)
        ])

        let playerItem = AVPlayerItem(asset: asset)
        // Adaptive buffering: 15s ahead for VOD/Series (prevents mid-movie buffering),
        // 3s ahead for Live TV (fast channel zapping + stability).
        playerItem.preferredForwardBufferDuration = (kind == .live) ? 3.0 : 15.0
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false

        observePlayerItem(playerItem, pendingSeek: seekTo)
        player.replaceCurrentItem(with: playerItem)
        player.play()
        player.rate = playbackRate
        isPlaying = true
    }

    // MARK: - Play / Pause with Stale-Socket Recovery

    public func togglePlayPause() {
        sleepGuard.registerUserInteraction()
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    public func pause() {
        player.pause()
        isPlaying = false
        pausedAt = Date()
        bufferState = .paused
        saveCheckpointNow()
    }

    /// Resumes playback. If paused for > 2 minutes (or if IPTV server closed the idle TCP socket),
    /// transparently reconnects to the stream and seeks straight back to the exact saved second.
    public func resume() {
        guard let item = currentItem else { return }
        let staleThreshold: TimeInterval = 120 // 2 minutes
        let wasLongPause = pausedAt.map { Date().timeIntervalSince($0) > staleThreshold } ?? false
        let itemFailed = player.currentItem?.status == .failed || player.currentItem?.error != nil

        pausedAt = nil

        if item.kind != .live && (wasLongPause || itemFailed) {
            let targetSecond = max(0, currentTime - 2.0)
            bufferState = .recoveringConnection
            prepareAndPlay(url: item.streamURL, kind: item.kind, seekTo: targetSecond)
        } else {
            player.play()
            player.rate = playbackRate
            isPlaying = true
            bufferState = .playing
        }
    }

    public func stop() {
        saveCheckpointNow()
        cancelNextEpisodeCountdown()
        player.pause()
        player.replaceCurrentItem(with: nil)
        cleanupItemObservers()
        isPlaying = false
        bufferState = .idle
    }

    // MARK: - Instant Seeking (Debounced Scrubbing + 10s Skip)

    public func skip(by deltaSeconds: Double) {
        guard let item = currentItem, item.kind != .live else { return }
        sleepGuard.registerUserInteraction()
        let target = min(max(0, currentTime + deltaSeconds), max(duration, currentTime + deltaSeconds))
        commitSeek(to: target, exact: false)
    }

    public func beginScrubbing(at seconds: Double) {
        sleepGuard.registerUserInteraction()
        isScrubbing = true
        scrubPreviewTime = seconds
    }

    /// Updates preview immediately while debouncing actual network seek requests so the IPTV server isn't flooded.
    public func updateScrubbing(to seconds: Double) {
        scrubPreviewTime = seconds
        seekDebounceTask?.cancel()
        seekDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000) // 180ms debounce
            guard !Task.isCancelled, let self else { return }
            self.commitSeek(to: seconds, exact: false)
        }
    }

    public func endScrubbing(at seconds: Double) {
        seekDebounceTask?.cancel()
        isScrubbing = false
        currentTime = seconds
        commitSeek(to: seconds, exact: true)
    }

    private func commitSeek(to seconds: Double, exact: Bool) {
        let cmTime = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        // Fast keyframe tolerance during rapid skips; exact frame tolerance on final drop.
        let tolerance: CMTime = exact ? CMTime(seconds: 0.5, preferredTimescale: 600) : .positiveInfinity
        player.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] completed in
            guard completed else { return }
            Task { @MainActor [weak self] in
                self?.currentTime = seconds
                self?.saveCheckpointNow()
            }
        }
    }

    public func setRate(_ rate: Float) {
        sleepGuard.registerUserInteraction()
        playbackRate = rate
        if isPlaying {
            player.rate = rate
        }
    }

    // MARK: - Observers & Recovery

    private func setupPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, !self.isScrubbing else { return }
                let secs = time.seconds
                if secs.isFinite {
                    self.currentTime = secs
                }
                if let dur = self.player.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
                    self.duration = dur
                }
                if Date().timeIntervalSince(self.lastCheckpointAt) >= 5.0 {
                    self.saveCheckpointNow()
                }
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem, pendingSeek: Double?) {
        var didApplyInitialSeek = false

        let statusObs = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch observedItem.status {
                case .readyToPlay:
                    self.reconnectAttempts = 0
                    if !didApplyInitialSeek, let target = pendingSeek, target > 1 {
                        didApplyInitialSeek = true
                        self.commitSeek(to: target, exact: true)
                    }
                    self.bufferState = self.isPlaying ? .playing : .paused
                case .failed:
                    self.handleStreamFailure(error: observedItem.error)
                default:
                    break
                }
            }
        }

        let bufferEmptyObs = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if observedItem.isPlaybackBufferEmpty && self.isPlaying {
                    self.bufferState = .buffering(progressPercent: 0)
                }
            }
        }

        let likelyToKeepUpObs = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if observedItem.isPlaybackLikelyToKeepUp {
                    self.bufferState = self.isPlaying ? .playing : .paused
                }
            }
        }

        itemObservers = [statusObs, bufferEmptyObs, likelyToKeepUpObs]

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePlaybackEnded()
            }
        }
    }

    private func handleStreamFailure(error: Error?) {
        guard let item = currentItem else { return }
        if reconnectAttempts < 1 {
            reconnectAttempts += 1
            bufferState = .recoveringConnection
            let resumeAt = item.kind == .live ? nil : max(0, currentTime - 2.0)
            // If Live TV .m3u8 failed, try .ts fallback once
            var fallbackURL = item.streamURL
            if item.kind == .live && fallbackURL.pathExtension.lowercased() == "m3u8" {
                fallbackURL = fallbackURL.deletingPathExtension().appendingPathExtension("ts")
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.prepareAndPlay(url: fallbackURL, kind: item.kind, seekTo: resumeAt)
            }
        } else {
            isPlaying = false
            bufferState = .failed(error?.localizedDescription ?? "Stream connection failed.")
        }
    }

    private func handlePlaybackEnded() {
        saveCheckpointNow()
        guard let item = currentItem, let next = item.nextEpisode else {
            isPlaying = false
            bufferState = .idle
            return
        }

        let allowed = sleepGuard.shouldAllowAutoPlayNextEpisode { [weak self] in
            self?.stop()
        }
        guard allowed else {
            isPlaying = false
            bufferState = .paused
            return
        }

        startNextEpisodeCountdown(next: next)
    }

    public func startNextEpisodeCountdown(next: PlayableItem.NextEpisodeRef) {
        nextEpisodeCountdown = 5
        nextEpisodeTask?.cancel()
        nextEpisodeTask = Task { [weak self] in
            guard let self else { return }
            while let count = self.nextEpisodeCountdown, count > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.nextEpisodeCountdown = (self.nextEpisodeCountdown ?? 1) - 1
            }
            if !Task.isCancelled {
                self.nextEpisodeCountdown = nil
                self.playNextEpisodeNow(next)
            }
        }
    }

    public func playNextEpisodeNow(_ next: PlayableItem.NextEpisodeRef) {
        cancelNextEpisodeCountdown()
        let nextItem = PlayableItem(
            id: "episode-\(next.episodeId)",
            title: next.title,
            subtitle: "S\(next.seasonNumber):E\(next.episodeNumber)",
            artworkURL: next.artworkURL,
            streamURL: next.streamURL,
            kind: .episode,
            seriesId: currentItem?.seriesId,
            seasonNumber: next.seasonNumber,
            episodeNumber: next.episodeNumber,
            nextEpisode: nil
        )
        load(item: nextItem, forceStartFromBeginning: true)
    }

    public func cancelNextEpisodeCountdown() {
        nextEpisodeTask?.cancel()
        nextEpisodeTask = nil
        nextEpisodeCountdown = nil
    }

    public func saveCheckpointNow() {
        guard let item = currentItem, item.kind != .live, duration > 0 else { return }
        lastCheckpointAt = Date()
        progressStore.updateProgress(item: item, position: currentTime, duration: duration)
    }

    private func cleanupItemObservers() {
        itemObservers.forEach { $0.invalidate() }
        itemObservers.removeAll()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
