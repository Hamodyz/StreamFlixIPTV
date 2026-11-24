import Foundation
import Combine

/// Prevents binge-playing endlessly when the user falls asleep (Netflix-style "Are You Still Watching?").
@MainActor
public final class SleepGuardManager: ObservableObject {
    @Published public var consecutiveAutoPlayedEpisodes: Int = 0
    @Published public var isShowingAreYouStillWatching: Bool = false
    @Published public var countdownSecondsRemaining: Int = 60
    @Published public var sleepTimerRemainingSeconds: Int? = nil

    /// Default: prompt after 2 consecutive auto-played episodes without user interaction (like Netflix).
    public var maxConsecutiveAutoPlay: Int
    public var promptTimeoutSeconds: Int

    private var lastUserInteractionAt: Date = Date()
    private var countdownTask: Task<Void, Never>?
    private var sleepTimerTask: Task<Void, Never>?

    public init(maxConsecutiveAutoPlay: Int = 2, promptTimeoutSeconds: Int = 60) {
        self.maxConsecutiveAutoPlay = maxConsecutiveAutoPlay
        self.promptTimeoutSeconds = promptTimeoutSeconds
    }

    /// Call whenever the user taps the screen, seeks, changes volume, or selects an episode manually.
    public func registerUserInteraction() {
        lastUserInteractionAt = Date()
        consecutiveAutoPlayedEpisodes = 0
        if isShowingAreYouStillWatching {
            dismissPromptAndContinue()
        }
    }

    /// Evaluates whether the player should auto-play the next episode or pause and ask "Are you still watching?".
    /// Returns `true` if auto-play is allowed, `false` if the Sleep Guard prompt was triggered.
    public func shouldAllowAutoPlayNextEpisode(onTimeoutStop: @escaping @MainActor () -> Void) -> Bool {
        let nextCount = consecutiveAutoPlayedEpisodes + 1
        if nextCount >= maxConsecutiveAutoPlay {
            triggerAreYouStillWatching(onTimeoutStop: onTimeoutStop)
            return false
        } else {
            consecutiveAutoPlayedEpisodes = nextCount
            return true
        }
    }

    public func triggerAreYouStillWatching(onTimeoutStop: @escaping @MainActor () -> Void) {
        isShowingAreYouStillWatching = true
        countdownSecondsRemaining = promptTimeoutSeconds
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            guard let self else { return }
            while self.countdownSecondsRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.countdownSecondsRemaining -= 1
            }
            if !Task.isCancelled && self.isShowingAreYouStillWatching {
                self.isShowingAreYouStillWatching = false
                onTimeoutStop()
            }
        }
    }

    public func dismissPromptAndContinue() {
        countdownTask?.cancel()
        countdownTask = nil
        isShowingAreYouStillWatching = false
        consecutiveAutoPlayedEpisodes = 0
        lastUserInteractionAt = Date()
    }

    public func stopAndExit() {
        countdownTask?.cancel()
        countdownTask = nil
        isShowingAreYouStillWatching = false
    }

    // MARK: - Optional Manual Sleep Timer (15m / 30m / 60m)

    public func startSleepTimer(minutes: Int, onExpire: @escaping @MainActor () -> Void) {
        cancelSleepTimer()
        sleepTimerRemainingSeconds = minutes * 60
        sleepTimerTask = Task { [weak self] in
            guard let self else { return }
            while let remaining = self.sleepTimerRemainingSeconds, remaining > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                if let current = self.sleepTimerRemainingSeconds {
                    self.sleepTimerRemainingSeconds = max(0, current - 1)
                }
            }
            if !Task.isCancelled {
                self.sleepTimerRemainingSeconds = nil
                onExpire()
            }
        }
    }

    public func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerRemainingSeconds = nil
    }
}
