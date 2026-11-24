import SwiftUI
import AVKit
import StreamFlixCore

struct NetflixPlayerView: View {
    let item: PlayableItem
    @ObservedObject var engine: NetflixPlayerEngine
    @ObservedObject var sleepGuard: SleepGuardManager
    let onDismiss: () -> Void

    @State private var showControls = true
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var skipFeedback: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AVPlayerSurface(player: engine.player)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in
                    // Left/right double-tap skip (handled via GeometryReader below as well)
                    toggleControls()
                }
                .onTapGesture {
                    sleepGuard.registerUserInteraction()
                    toggleControls()
                }

            // Double-tap left/right 10s zones for VOD/Series
            if item.kind != .live {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                engine.skip(by: -10)
                                showSkipToast("-10s")
                            }
                            .onTapGesture {
                                sleepGuard.registerUserInteraction()
                                toggleControls()
                            }
                            .frame(width: geo.size.width * 0.35)

                        Spacer()

                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                engine.skip(by: 10)
                                showSkipToast("+10s")
                            }
                            .onTapGesture {
                                sleepGuard.registerUserInteraction()
                                toggleControls()
                            }
                            .frame(width: geo.size.width * 0.35)
                    }
                }
            }

            if let skipFeedback {
                Text(skipFeedback)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.75), in: Capsule())
            }

            // Buffering / Recovering HUD
            switch engine.bufferState {
            case .loading, .buffering:
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(Color(red: 0.898, green: 0.035, blue: 0.078))
                        .scaleEffect(1.4)
                    Text("Buffering...")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                .padding(18)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            case .recoveringConnection:
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Reconnecting to exact spot...")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                .padding(18)
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            case .failed(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(msg)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        engine.load(item: item)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
            default:
                EmptyView()
            }

            // Controls Overlay
            if showControls && !sleepGuard.isShowingAreYouStillWatching {
                playerControlsOverlay
            }

            // Next Episode Countdown Card
            if let countdown = engine.nextEpisodeCountdown, let next = item.nextEpisode {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Next Episode in \(countdown)s")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(next.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            HStack(spacing: 10) {
                                Button("Play Now") {
                                    engine.playNextEpisodeNow(next)
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Cancel") {
                                    engine.cancelNextEpisodeCountdown()
                                }
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

            // Netflix "Are You Still Watching?" Sleep Guard Modal
            if sleepGuard.isShowingAreYouStillWatching {
                AreYouStillWatchingOverlay(
                    secondsRemaining: sleepGuard.countdownSecondsRemaining,
                    onContinue: {
                        sleepGuard.dismissPromptAndContinue()
                        if let next = item.nextEpisode {
                            engine.playNextEpisodeNow(next)
                        } else {
                            engine.resume()
                        }
                    },
                    onExit: {
                        sleepGuard.stopAndExit()
                        engine.stop()
                        onDismiss()
                    }
                )
            }
        }
        .onAppear {
            engine.load(item: item)
            scheduleControlsHide()
        }
    }

    private var playerControlsOverlay: some View {
        VStack {
            // Top Bar
            HStack {
                Button {
                    engine.stop()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.5), in: Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.currentItem?.title ?? item.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let sub = engine.currentItem?.subtitle ?? item.subtitle {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }

                Spacer()

                if let sleepRem = sleepGuard.sleepTimerRemainingSeconds {
                    Text("Sleep: \(formatTime(Double(sleepRem)))")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                }

                Menu {
                    Button("15 Minutes") { sleepGuard.startSleepTimer(minutes: 15) { engine.stop(); onDismiss() } }
                    Button("30 Minutes") { sleepGuard.startSleepTimer(minutes: 30) { engine.stop(); onDismiss() } }
                    Button("45 Minutes") { sleepGuard.startSleepTimer(minutes: 45) { engine.stop(); onDismiss() } }
                    Button("60 Minutes") { sleepGuard.startSleepTimer(minutes: 60) { engine.stop(); onDismiss() } }
                    if sleepGuard.sleepTimerRemainingSeconds != nil {
                        Divider()
                        Button("Cancel Sleep Timer", role: .destructive) { sleepGuard.cancelSleepTimer() }
                    }
                } label: {
                    Image(systemName: "moon.zzz.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.5), in: Circle())
                }

                if item.kind != .live {
                    Menu {
                        ForEach([Float(1.0), 1.25, 1.5, 2.0], id: \.self) { rate in
                            Button("\(String(format: "%.2g", rate))x") {
                                engine.setRate(rate)
                            }
                        }
                    } label: {
                        Text("\(String(format: "%.2g", engine.playbackRate))x")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            // Center Play/Pause & -10s / +10s
            HStack(spacing: 48) {
                if item.kind != .live {
                    Button {
                        engine.skip(by: -10)
                        scheduleControlsHide()
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 34))
                            .foregroundStyle(.white)
                    }
                }

                Button {
                    engine.togglePlayPause()
                    scheduleControlsHide()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.white)
                        .padding(20)
                        .background(.black.opacity(0.45), in: Circle())
                }

                if item.kind != .live {
                    Button {
                        engine.skip(by: 10)
                        scheduleControlsHide()
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 34))
                            .foregroundStyle(.white)
                    }
                }
            }

            Spacer()

            // Bottom Scrub Bar
            if item.kind != .live && engine.duration > 0 {
                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { engine.isScrubbing ? engine.scrubPreviewTime : engine.currentTime },
                            set: { newVal in
                                if !engine.isScrubbing {
                                    engine.beginScrubbing(at: newVal)
                                } else {
                                    engine.updateScrubbing(to: newVal)
                                }
                            }
                        ),
                        in: 0...max(engine.duration, 1),
                        onEditingChanged: { editing in
                            if !editing {
                                engine.endScrubbing(at: engine.scrubPreviewTime)
                                scheduleControlsHide()
                            }
                        }
                    )
                    .tint(Color(red: 0.898, green: 0.035, blue: 0.078))

                    HStack {
                        Text(formatTime(engine.isScrubbing ? engine.scrubPreviewTime : engine.currentTime))
                        Spacer()
                        Text(formatTime(engine.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            } else {
                HStack {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("LIVE")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Color.black.opacity(0.35))
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            scheduleControlsHide()
        }
    }

    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        controlsHideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled && engine.isPlaying && !engine.isScrubbing {
                withAnimation { showControls = false }
            }
        }
    }

    private func showSkipToast(_ text: String) {
        skipFeedback = text
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            skipFeedback = nil
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
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
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))

                Text("Are you still watching?")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Playback paused so you don't lose your place. Stopping automatically in \(secondsRemaining)s.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                HStack(spacing: 14) {
                    Button(action: onContinue) {
                        Text("Continue Watching")
                            .fontWeight(.bold)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(.white)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Button(action: onExit) {
                        Text("I'm Done")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.15))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(28)
        }
    }
}

// MARK: - Cross-Platform AVPlayerLayer Wrapper

#if os(iOS) || os(tvOS)
struct AVPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerContainerUIView {
        let view = PlayerContainerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }
    func updateUIView(_ uiView: PlayerContainerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerContainerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#elseif os(macOS)
struct AVPlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        return view
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
#endif
