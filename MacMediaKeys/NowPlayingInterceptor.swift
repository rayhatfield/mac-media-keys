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

    // How often to re-assert our Now Playing claim. Real media apps (e.g.
    // Qobuz) continuously update their own now-playing info while playing,
    // which makes macOS consider them "more current" than a claim we only
    // set once at launch — so rcd keeps routing hardware media keys directly
    // to them instead of us. Refreshing on this cadence keeps our claim from
    // going stale relative to theirs.
    private static let refreshInterval: TimeInterval = 1.0

    init() {
        setupRemoteCommands()
        reassertNowPlaying()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.reassertNowPlaying()
        }
    }

    deinit {
        refreshTimer?.invalidate()
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
        infoCenter.playbackState = .playing
        infoCenter.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "MacMediaKeys",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Date().timeIntervalSince(claimStartTime),
            MPMediaItemPropertyPlaybackDuration: 0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
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
