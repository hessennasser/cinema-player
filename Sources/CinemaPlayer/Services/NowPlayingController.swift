import Combine
import MediaPlayer

/// Bridges playback state to the system Now Playing widget, Control Center,
/// and the keyboard media keys via MediaPlayer's remote command center.
@MainActor
final class NowPlayingController: ObservableObject {
    private weak var playback: PlaybackController?
    private var cancellables: Set<AnyCancellable> = []
    private var didConfigureCommands = false

    func attach(to playback: PlaybackController) {
        self.playback = playback
        configureCommandsIfNeeded()

        let triggers: [AnyPublisher<Void, Never>] = [
            playback.$currentItem.map { _ in () }.eraseToAnyPublisher(),
            playback.$currentTime.map { _ in () }.eraseToAnyPublisher(),
            playback.$duration.map { _ in () }.eraseToAnyPublisher(),
            playback.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            playback.$rate.map { _ in () }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(triggers)
            .sink { [weak self] in
                Task { @MainActor in self?.updateNowPlayingInfo() }
            }
            .store(in: &cancellables)
    }

    private func configureCommandsIfNeeded() {
        guard !didConfigureCommands else { return }
        didConfigureCommands = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let playback = self?.playback, !playback.isPlaying else { return }
                playback.togglePlayback()
            }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let playback = self?.playback, playback.isPlaying else { return }
                playback.togglePlayback()
            }
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playback?.togglePlayback() }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playback?.playNext() }
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playback?.playPrevious() }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playback?.skip(by: 10) }
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playback?.skip(by: -10) }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            Task { @MainActor in self?.playback?.seek(to: position) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        let infoCenter = MPNowPlayingInfoCenter.default()

        guard let playback, let item = playback.currentItem else {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
            return
        }

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = item.title
        info[MPMediaItemPropertyPlaybackDuration] = playback.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playback.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = playback.isPlaying ? playback.rate.rawValue : 0.0

        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = playback.isPlaying ? .playing : .paused
    }
}
