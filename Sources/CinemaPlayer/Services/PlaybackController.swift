import AVFoundation
import Combine
import Foundation

enum PlaybackRate: Double, CaseIterable, Identifiable {
    case half = 0.5
    case normal = 1.0
    case oneAndQuarter = 1.25
    case oneAndHalf = 1.5
    case double = 2.0

    var id: Double { rawValue }

    var title: String {
        rawValue == 1 ? "Normal" : "\(rawValue.formatted())×"
    }
}

enum RepeatMode: String, CaseIterable, Identifiable {
    case off
    case one
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Repeat off"
        case .one: "Repeat one"
        case .all: "Repeat all"
        }
    }

    var icon: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }
}

@MainActor
final class PlaybackController: ObservableObject {
    let player = AVPlayer()

    @Published private(set) var currentItem: MediaItem?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var rate: PlaybackRate = .normal
    @Published private(set) var volume: Double = 1
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var isShuffling = false
    @Published private(set) var embeddedSubtitleTracks: [EmbeddedSubtitleTrack] = []
    @Published private(set) var selectedEmbeddedSubtitleID: String?
    @Published private(set) var audioTracks: [EmbeddedAudioTrack] = []
    @Published private(set) var selectedAudioTrackID: String?
    @Published var errorMessage: String?

    private let resumeStoreKey = "cinema-player.resume-positions.v1"
    private var timeObserver: Any?
    private var activeScopedURL: URL?
    private var statusObserver: NSKeyValueObservation?
    private var resumePositions: [UUID: Double] = [:]
    private var pendingStartTime: Double = 0
    private var playlist: [MediaItem] = []
    private var endObserver: AnyCancellable?
    private var lastPersistedSecond = -1
    private var legibleGroup: AVMediaSelectionGroup?
    private var legibleOptionsByID: [String: AVMediaSelectionOption] = [:]
    private var audibleGroup: AVMediaSelectionGroup?
    private var audibleOptionsByID: [String: AVMediaSelectionOption] = [:]

    init() {
        loadResumePositions()
        player.appliesMediaSelectionCriteriaAutomatically = false
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.updateProgress(with: time)
            }
        }
    }

    func play(_ item: MediaItem) {
        saveProgress(for: currentItem)
        stopAccessingCurrentFile()
        currentItem = item
        currentTime = 0
        duration = 0
        errorMessage = nil
        pendingStartTime = resumeTime(for: item)
        lastPersistedSecond = -1
        embeddedSubtitleTracks = []
        selectedEmbeddedSubtitleID = nil
        legibleGroup = nil
        legibleOptionsByID = [:]
        audioTracks = []
        selectedAudioTrackID = nil
        audibleGroup = nil
        audibleOptionsByID = [:]

        if item.url.startAccessingSecurityScopedResource() {
            activeScopedURL = item.url
        }

        let playerItem = AVPlayerItem(url: item.url)
        observeStatus(of: playerItem)
        observeEnd(of: playerItem)
        player.replaceCurrentItem(with: playerItem)
        isPlaying = false
    }

    func setPlaylist(_ items: [MediaItem]) {
        playlist = items
    }

    var canAdvance: Bool {
        playlist.count > 1
    }

    func toggleShuffle() {
        isShuffling.toggle()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func playNext() {
        advance(by: 1, auto: false)
    }

    func playPrevious() {
        advance(by: -1, auto: false)
    }

    private func advance(by direction: Int, auto: Bool) {
        guard !playlist.isEmpty else { return }

        guard let current = currentItem,
              let index = playlist.firstIndex(where: { $0.id == current.id }) else {
            if !auto, let first = playlist.first { play(first) }
            return
        }

        if isShuffling, playlist.count > 1 {
            var nextIndex = index
            while nextIndex == index {
                nextIndex = Int.random(in: 0..<playlist.count)
            }
            play(playlist[nextIndex])
            return
        }

        let target = index + direction
        if playlist.indices.contains(target) {
            play(playlist[target])
        } else if repeatMode == .all || !auto {
            let wrapped = (target % playlist.count + playlist.count) % playlist.count
            play(playlist[wrapped])
        }
    }

    private func observeEnd(of item: AVPlayerItem) {
        endObserver = NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handlePlaybackEnd()
                }
            }
    }

    private func handlePlaybackEnd() {
        if repeatMode == .one {
            seek(to: 0)
            player.playImmediately(atRate: Float(rate.rawValue))
            isPlaying = true
            return
        }
        advance(by: 1, auto: true)
    }

    func resumeTime(for item: MediaItem) -> Double {
        resumePositions[item.id] ?? 0
    }

    func hasResumePoint(for item: MediaItem) -> Bool {
        resumeTime(for: item) >= 15
    }

    func clearResumePoint(for item: MediaItem) {
        resumePositions[item.id] = nil
        saveResumePositions()
    }

    func togglePlayback() {
        guard player.currentItem != nil else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.playImmediately(atRate: Float(rate.rawValue))
            isPlaying = true
        }
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func seek(to seconds: Double) {
        let clampedTime = min(max(seconds, 0), duration)
        player.seek(to: CMTime(seconds: clampedTime, preferredTimescale: 600))
    }

    func setRate(_ newRate: PlaybackRate) {
        rate = newRate
        guard isPlaying else { return }
        player.rate = Float(newRate.rawValue)
    }

    func setVolume(_ newVolume: Double) {
        volume = min(max(newVolume, 0), 1)
        player.volume = Float(volume)
    }

    func changeVolume(by amount: Double) {
        setVolume(volume + amount)
    }

    func toggleMute() {
        setVolume(volume > 0 ? 0 : 1)
    }

    func selectEmbeddedSubtitle(id: String?) {
        guard let currentPlayerItem = player.currentItem,
              let legibleGroup else { return }

        guard let id else {
            currentPlayerItem.select(nil, in: legibleGroup)
            selectedEmbeddedSubtitleID = nil
            return
        }

        guard let option = legibleOptionsByID[id] else { return }
        currentPlayerItem.select(option, in: legibleGroup)
        selectedEmbeddedSubtitleID = id
    }

    func selectAudioTrack(id: String) {
        guard let currentPlayerItem = player.currentItem,
              let audibleGroup,
              let option = audibleOptionsByID[id] else { return }

        currentPlayerItem.select(option, in: audibleGroup)
        selectedAudioTrackID = id
    }

    private func updateProgress(with time: CMTime) {
        currentTime = max(time.seconds.isFinite ? time.seconds : 0, 0)

        guard let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite else { return }
        duration = max(itemDuration, 0)
        isPlaying = player.rate > 0
        saveProgress(for: currentItem)
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            Task { @MainActor in
                switch observedItem.status {
                case .readyToPlay:
                    self?.loadEmbeddedSubtitleTracks(from: observedItem.asset)
                    self?.loadAudioTracks(from: observedItem.asset)
                    self?.startPlaybackWhenReady()
                case .failed:
                    let reason = observedItem.error?.localizedDescription ?? "The video codec is not supported by macOS."
                    self?.errorMessage = "This video could not be played: \(reason)"
                    self?.isPlaying = false
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func stopAccessingCurrentFile() {
        activeScopedURL?.stopAccessingSecurityScopedResource()
        activeScopedURL = nil
    }

    private func startPlaybackWhenReady() {
        let startTime = pendingStartTime
        pendingStartTime = 0

        guard startTime > 0 else {
            player.playImmediately(atRate: Float(rate.rawValue))
            isPlaying = true
            return
        }

        player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.player.playImmediately(atRate: Float(self.rate.rawValue))
                self.isPlaying = true
            }
        }
    }

    private func loadEmbeddedSubtitleTracks(from asset: AVAsset) {
        Task { [weak self] in
            guard let group = try? await asset.loadMediaSelectionGroup(for: .legible),
                  let self,
                  self.player.currentItem?.asset === asset else {
                return
            }

            self.legibleGroup = group
            let tracks = group.options.enumerated().map { index, option in
                let id = "embedded-\(index)-\(option.displayName)"
                self.legibleOptionsByID[id] = option
                return EmbeddedSubtitleTrack(id: id, title: option.displayName)
            }
            self.embeddedSubtitleTracks = tracks
        }
    }

    private func loadAudioTracks(from asset: AVAsset) {
        Task { [weak self] in
            guard let group = try? await asset.loadMediaSelectionGroup(for: .audible),
                  let self,
                  self.player.currentItem?.asset === asset else {
                return
            }

            self.audibleGroup = group
            var optionsByID: [String: AVMediaSelectionOption] = [:]
            let tracks = group.options.enumerated().map { index, option in
                let id = "audio-\(index)-\(option.displayName)"
                optionsByID[id] = option
                return EmbeddedAudioTrack(id: id, title: option.displayName)
            }
            self.audibleOptionsByID = optionsByID
            self.audioTracks = tracks

            let currentOption = self.player.currentItem?
                .currentMediaSelection.selectedMediaOption(in: group)
            if let currentOption,
               let match = tracks.first(where: { optionsByID[$0.id] == currentOption }) {
                self.selectedAudioTrackID = match.id
            } else {
                self.selectedAudioTrackID = tracks.first?.id
            }
        }
    }

    private func saveProgress(for item: MediaItem?) {
        guard let item, duration > 0 else { return }

        let currentSecond = Int(currentTime.rounded(.down))
        guard currentSecond != lastPersistedSecond else { return }
        lastPersistedSecond = currentSecond

        let hasFinished = currentTime >= duration - 20
        if currentTime >= 15, !hasFinished {
            resumePositions[item.id] = currentTime
        } else if hasFinished {
            resumePositions[item.id] = nil
        }
        saveResumePositions()
    }

    private func loadResumePositions() {
        guard let data = UserDefaults.standard.data(forKey: resumeStoreKey),
              let positions = try? JSONDecoder().decode([UUID: Double].self, from: data) else {
            return
        }
        resumePositions = positions
    }

    private func saveResumePositions() {
        guard let data = try? JSONEncoder().encode(resumePositions) else { return }
        UserDefaults.standard.set(data, forKey: resumeStoreKey)
    }
}
