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

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleCommand(.play)
            return .success
        }

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.handleCommand(.play)
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.handleCommand(.play)
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.handleCommand(.next)
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.handleCommand(.previous)
            return .success
        }
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
}
