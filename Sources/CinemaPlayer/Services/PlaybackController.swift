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
    @Published private(set) var isBuffering = false
    @Published private(set) var isLive = false
    /// The size actually being decoded, which for an adaptive stream changes as
    /// the player moves between renditions.
    @Published private(set) var presentedResolution: String?
    /// Non-nil while a link that cannot be streamed is being fetched.
    @Published private(set) var downloadProgress: Double?
    /// Set when a link needs fetching, so the library can remember it.
    @Published private(set) var discoveredLocalCopyNeed: MediaItem?
    /// The qualities the current stream offers, best first. Empty for anything
    /// that is not an adaptive stream, which has only the one.
    @Published private(set) var availableRenditions: [StreamRendition] = []
    /// The height the viewer pinned to, or nil while quality is automatic.
    @Published private(set) var preferredMaximumHeight: Int?
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
    private let qualityStoreKey = "cinema-player.preferred-max-height.v1"
    private var timeObserver: Any?
    private var activeScopedURL: URL?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var presentationSizeObserver: NSKeyValueObservation?
    private var downloadTask: Task<Void, Never>?
    private var renditionTask: Task<Void, Never>?
    private var didRetryWithLocalCopy = false
    private var failureObserver: AnyCancellable?
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
        preferredMaximumHeight = UserDefaults.standard.object(forKey: qualityStoreKey) as? Int
        player.appliesMediaSelectionCriteriaAutomatically = false
        observeBuffering()
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
        didRetryWithLocalCopy = false
        start(item, fromLocalCopy: item.needsLocalCopy)
    }

    private func start(_ item: MediaItem, fromLocalCopy: Bool) {
        downloadTask?.cancel()
        downloadTask = nil
        downloadProgress = nil

        guard !fromLocalCopy || !item.isRemote else {
            playFromLocalCopy(item)
            return
        }
        beginPlayback(of: item, at: item.url)
    }

    /// Fetches the whole file, then plays it from disk. The library item keeps
    /// its link; the copy is only how it gets watched.
    private func playFromLocalCopy(_ item: MediaItem) {
        if let cached = StreamCache.shared.cachedCopy(of: item.url) {
            beginPlayback(of: item, at: cached)
            return
        }

        prepare(for: item)
        downloadProgress = 0
        downloadTask = Task { [weak self] in
            do {
                let local = try await StreamCache.shared.localCopy(of: item.url) { fraction in
                    self?.downloadProgress = fraction
                }
                guard let self, !Task.isCancelled, self.currentItem?.id == item.id else { return }
                self.downloadProgress = nil
                self.beginPlayback(of: item, at: local)
            } catch is CancellationError {
                self?.downloadProgress = nil
            } catch {
                guard let self, self.currentItem?.id == item.id else { return }
                self.downloadProgress = nil
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Caps the quality the player may choose. `nil` hands the decision back to
    /// AVFoundation, which is what most viewers want most of the time.
    func setPreferredMaximumHeight(_ height: Int?) {
        preferredMaximumHeight = height
        if let height {
            UserDefaults.standard.set(height, forKey: qualityStoreKey)
        } else {
            UserDefaults.standard.removeObject(forKey: qualityStoreKey)
        }

        guard let item = player.currentItem else { return }
        applyPreferredQuality(to: item)
    }

    var preferredQualityTitle: String {
        guard let preferredMaximumHeight else { return "Auto" }

        return availableRenditions.first { $0.height == preferredMaximumHeight }?.title
            ?? "\(preferredMaximumHeight)p"
    }

    /// A cap, not a fixed choice: the player still drops lower when the network
    /// cannot keep up, which is the behaviour people expect from a quality menu.
    private func applyPreferredQuality(to item: AVPlayerItem) {
        guard let height = preferredMaximumHeight,
              let match = bestRendition(atOrBelow: height) else {
            item.preferredMaximumResolution = .zero
            item.preferredPeakBitRate = 0
            return
        }

        item.preferredMaximumResolution = match.size
        item.preferredPeakBitRate = 0
    }

    private func bestRendition(atOrBelow height: Int) -> StreamRendition? {
        availableRenditions.first { $0.height <= height } ?? availableRenditions.last
    }

    /// Reads the qualities a master playlist offers. Only an adaptive stream
    /// has more than one, so nothing else is asked for.
    private func loadRenditions(for item: MediaItem, playing url: URL) {
        renditionTask?.cancel()
        availableRenditions = []

        guard !url.isFileURL,
              StreamSupport.playlistExtensions.contains(url.pathExtension.lowercased()) else {
            return
        }

        renditionTask = Task { [weak self] in
            guard let manifest = try? await StreamHTTP.manifest(at: url) else { return }
            let renditions = StreamSupport.manifestRenditions(in: manifest)

            guard let self, !Task.isCancelled, self.currentItem?.id == item.id, renditions.count > 1 else { return }
            self.availableRenditions = renditions
            if let playerItem = self.player.currentItem {
                self.applyPreferredQuality(to: playerItem)
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadProgress = nil
    }

    private func beginPlayback(of item: MediaItem, at url: URL) {
        prepare(for: item)

        if url.isFileURL, url.startAccessingSecurityScopedResource() {
            activeScopedURL = url
        }

        let playerItem = AVPlayerItem(url: url)
        applyPreferredQuality(to: playerItem)
        loadRenditions(for: item, playing: url)
        observeStatus(of: playerItem)
        observeEnd(of: playerItem)
        observeFailure(of: playerItem)
        observePresentationSize(of: playerItem)
        player.replaceCurrentItem(with: playerItem)
        isPlaying = false
    }

    private func prepare(for item: MediaItem) {
        saveProgress(for: currentItem)
        stopAccessingCurrentFile()
        currentItem = item
        currentTime = 0
        duration = 0
        isLive = false
        presentedResolution = nil
        availableRenditions = []
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
        guard duration > 0 else { return }

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
        isPlaying = player.rate > 0

        // Live streams report an indefinite duration: there is nothing to
        // scrub through and no position worth remembering.
        let itemDuration = player.currentItem?.duration
        guard let seconds = itemDuration?.seconds, seconds.isFinite else {
            duration = 0
            isLive = player.currentItem?.status == .readyToPlay
            return
        }

        duration = max(seconds, 0)
        isLive = false
        saveProgress(for: currentItem)
    }

    /// Reflects the stall that a remote video hits while it fills its buffer.
    private func observeBuffering() {
        timeControlObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observedPlayer, _ in
            Task { @MainActor in
                self?.isBuffering = observedPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
    }

    private func observePresentationSize(of item: AVPlayerItem) {
        presentationSizeObserver = item.observe(\.presentationSize, options: [.initial, .new]) { [weak self] observedItem, _ in
            let size = observedItem.presentationSize
            Task { @MainActor in
                guard size.width > 0, size.height > 0 else { return }
                self?.presentedResolution = StreamSupport.resolutionLabel(for: size)
            }
        }
    }

    /// A link can go bad mid-playback, which never happens to a local file.
    private func observeFailure(of item: AVPlayerItem) {
        failureObserver = NotificationCenter.default
            .publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                Task { @MainActor in
                    guard let self else { return }
                    self.isPlaying = false
                    self.errorMessage = "Playback stopped: \(error?.localizedDescription ?? "the video stream could not be read.")"
                }
            }
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
                    guard let self else { return }
                    if self.retryWithLocalCopy() { return }
                    let reason = observedItem.error?.localizedDescription ?? self.defaultFailureReason
                    self.errorMessage = "This video could not be played: \(reason)"
                    self.isPlaying = false
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    /// A host that ignores `Range` leaves AVPlayer unable to read a progressive
    /// file, which surfaces as an opaque failure. Fetching the file instead is
    /// the only way to watch it, so that is tried once before reporting.
    private func retryWithLocalCopy() -> Bool {
        guard let item = currentItem, item.isRemote, !item.needsLocalCopy, !didRetryWithLocalCopy else {
            return false
        }
        guard !StreamSupport.playlistExtensions.contains(item.url.pathExtension.lowercased()) else {
            return false
        }

        didRetryWithLocalCopy = true
        discoveredLocalCopyNeed = item
        isPlaying = false
        playFromLocalCopy(item)
        return true
    }

    private var defaultFailureReason: String {
        currentItem?.isRemote == true
            ? "the link is unreachable or its format is not supported by macOS."
            : "the video codec is not supported by macOS."
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
