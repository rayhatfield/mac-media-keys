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

    init() {
        setupRemoteCommands()
        setupNowPlaying()
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        register(center.togglePlayPauseCommand, as: .play)
        register(center.playCommand, as: .play)
        register(center.pauseCommand, as: .play)

        register(center.nextTrackCommand, as: .next)
        register(center.previousTrackCommand, as: .previous)

        // Some keyboards and macOS routes expose forward/backward as seek/skip
        // commands instead of next/previous. Normalize them to track navigation
        // so they still reach the selected player.
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        register(center.seekForwardCommand, as: .fast)
        register(center.seekBackwardCommand, as: .rewind)
        register(center.skipForwardCommand, as: .fast)
        register(center.skipBackwardCommand, as: .rewind)
    }

    private func setupNowPlaying() {
        let infoCenter = MPNowPlayingInfoCenter.default()
        infoCenter.playbackState = .playing
        infoCenter.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "MacMediaKeys",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
            MPMediaItemPropertyPlaybackDuration: 0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
    }

    private func handleCommand(_ key: MediaKey) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nowPlayingInterceptor(self, receivedKey: key)
        }
    }

    private func register(_ command: MPRemoteCommand, as key: MediaKey) {
        command.isEnabled = true
        command.addTarget { [weak self] _ in
            self?.handleCommand(key)
            return .success
        }
    }
}
