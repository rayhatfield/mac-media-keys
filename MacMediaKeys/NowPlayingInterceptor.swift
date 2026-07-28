import Cocoa
import MediaPlayer

protocol NowPlayingInterceptorDelegate: AnyObject {
    func nowPlayingInterceptor(_ interceptor: NowPlayingInterceptor, receivedKey key: MediaKey)
}

/// Registers with MPRemoteCommandCenter so that macOS routes media key
/// commands to this app instead of whichever app `rcd`/`mediaremoted`
/// considers the current "Now Playing" target.
///
/// On macOS 26+, `rcd` routes media keys via the Now Playing system rather
/// than CGEvents. This interceptor claims the Now Playing session so that
/// when no other media app is actively playing, our app receives the
/// commands.
class NowPlayingInterceptor {
    weak var delegate: NowPlayingInterceptorDelegate?

    private var refreshTimer: Timer?
    private let claimStartTime = Date()

    // Timer health diagnostics. If macOS throttles us (App Nap, timer
    // coalescing), the claim goes stale and rcd starts routing media keys
    // straight to the real playing app again — so a late timer is a direct
    // predictor of the double-toggle bug returning.
    private var lastRefreshTime = Date()
    private var lastHeartbeatTime = Date()

    // How often to re-assert our Now Playing claim. Real media apps (e.g.
    // Qobuz) continuously update their own now-playing info while playing,
    // which makes macOS consider them "more current" than a claim we only
    // set once at launch — so rcd keeps routing hardware media keys directly
    // to them instead of us. Refreshing on this cadence keeps our claim from
    // going stale relative to theirs.
    private static let refreshInterval: TimeInterval = 1.0

    // Log a fire only if it is this much later than scheduled, plus a sparse
    // heartbeat. `copyDebugInfo` ships only the last 200 log lines, so a
    // frequent heartbeat would shrink the captured history to a few hours —
    // far too short for a bug that takes days to reappear. Anomalies (a late
    // fire) are logged immediately regardless of the heartbeat cadence, so the
    // heartbeat only needs to be a periodic liveness marker.
    private static let lateRefreshThreshold: TimeInterval = 2.0
    private static let heartbeatInterval: TimeInterval = 300.0

    init() {
        setupRemoteCommands()
        reassertNowPlaying()

        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refreshTick()
        }
        // `.common` modes so menu tracking and modal loops don't pause the
        // refresh (the default mode would stop firing while a menu is open).
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func refreshTick() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefreshTime)
        lastRefreshTime = now

        if elapsed > Self.lateRefreshThreshold {
            let late = String(format: "%.1f", elapsed)
            let expected = String(format: "%.1f", Self.refreshInterval)
            debugLog("NowPlaying refresh LATE: \(late)s since previous fire (expected \(expected)s) — likely throttled")
        } else if now.timeIntervalSince(lastHeartbeatTime) >= Self.heartbeatInterval {
            lastHeartbeatTime = now
            debugLog("NowPlaying refresh heartbeat — claim healthy")
        }

        reassertNowPlaying()
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        // togglePlayPauseCommand corresponds to the hardware play/pause media
        // key. The standalone play/pause commands are also sent by the system
        // for non-keypress reasons (audio route changes, AVRCP sync, etc.), so
        // we log them but the delegate decides whether to forward based on
        // whether a real keypress was seen recently.
        register(center.togglePlayPauseCommand, as: .play, sourceCommand: "togglePlayPause")
        register(center.playCommand, as: .play, sourceCommand: "play")
        register(center.pauseCommand, as: .play, sourceCommand: "pause")

        register(center.nextTrackCommand, as: .next, sourceCommand: "nextTrack")
        register(center.previousTrackCommand, as: .previous, sourceCommand: "previousTrack")

        // Some keyboards and macOS routes expose forward/backward as seek/skip
        // commands instead of next/previous. Normalize them to track navigation
        // so they still reach the selected player.
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        register(center.seekForwardCommand, as: .fast, sourceCommand: "seekForward")
        register(center.seekBackwardCommand, as: .rewind, sourceCommand: "seekBackward")
        register(center.skipForwardCommand, as: .fast, sourceCommand: "skipForward")
        register(center.skipBackwardCommand, as: .rewind, sourceCommand: "skipBackward")
    }

    /// Re-asserts our Now Playing claim. Called on a timer, and on demand
    /// right when the user switches the selected app, so our claim is
    /// freshest exactly when it matters most for winning the routing race.
    func reassertNowPlaying() {
        let infoCenter = MPNowPlayingInfoCenter.default()

        // Write the metadata first, then the playback state. It's the
        // playback-state assignment that drives the system's "who is playing"
        // transitions, so setting it last means it lands against already-fresh
        // metadata rather than the previous tick's.
        infoCenter.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "MacMediaKeys",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Date().timeIntervalSince(claimStartTime),
            MPMediaItemPropertyPlaybackDuration: 0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
        infoCenter.playbackState = .playing
    }

    private func handleCommand(_ key: MediaKey, sourceCommand: String) {
        debugLog("MPRemoteCommandCenter received \(sourceCommand) → mapped key=\(key)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nowPlayingInterceptor(self, receivedKey: key)
        }
    }

    private func register(_ command: MPRemoteCommand, as key: MediaKey, sourceCommand: String) {
        command.isEnabled = true
        command.addTarget { [weak self] _ in
            self?.handleCommand(key, sourceCommand: sourceCommand)
            return .success
        }
    }
}
