import AppKit
import AVFoundation
import AVKit
import Foundation
import SwiftUI

private enum VideoLayout: String, CaseIterable, Identifiable {
    case fit = "Fit"
    case fill = "Fill"
    case stretch = "Stretch"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fit: "rectangle.center.inset.filled"
        case .fill: "arrow.up.left.and.arrow.down.right"
        case .stretch: "arrow.left.and.right.square"
        }
    }

    var gravity: AVLayerVideoGravity {
        switch self {
        case .fit: .resizeAspect
        case .fill: .resizeAspectFill
        case .stretch: .resize
        }
    }
}

struct PlayerScreen: View {
    let videoOnly: Bool

    @EnvironmentObject private var library: MediaLibrary
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var fullscreen: VideoOnlyFullscreenController
    @EnvironmentObject private var controlsVisibility: PlaybackControlsVisibility
    @EnvironmentObject private var subtitles: SubtitleController
    @State private var videoLayout: VideoLayout = .fit

    var body: some View {
        ZStack {
            CinemaTheme.playerGradient.ignoresSafeArea()
            if videoOnly {
                playerStage
                    .ignoresSafeArea()
            } else {
                playerStage
                    .padding(24)
            }
        }
        .navigationTitle(videoOnly ? "" : playback.currentItem?.title ?? "Cinema Player")
        .onAppear {
            controlsVisibility.startMonitoring()
        }
        .onDisappear {
            controlsVisibility.stopMonitoring()
        }
        .onChange(of: playback.currentTime) { _, time in
            subtitles.update(for: time)
        }
        .onChange(of: playback.currentItem?.id) { _, _ in
            subtitles.clear()
        }
        .animation(.easeOut(duration: 0.18), value: controlsVisibility.isVisible)
    }

    private var playerStage: some View {
        ZStack {
            Color.black
            NativePlayerView(player: playback.player, videoGravity: videoLayout.gravity)
            MouseActivityTrackingView {
                controlsVisibility.revealTemporarily()
            }

            if let cue = subtitles.activeCue {
                VStack {
                    Spacer(minLength: 0)
                    SubtitleOverlay(text: cue.text, videoOnly: videoOnly)
                        .padding(.horizontal, videoOnly ? 92 : 52)
                        .padding(.bottom, videoOnly ? 124 : 132)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            if controlsVisibility.isVisible {
                LinearGradient(
                    colors: [.black.opacity(0.26), .clear, .black.opacity(0.84)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    if !videoOnly {
                        videoInformation
                            .padding(.top, 18)
                            .padding(.horizontal, 18)
                    }
                    Spacer(minLength: 0)
                    controlDeck
                        .padding(videoOnly ? 28 : 18)
                }
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: videoOnly ? 0 : 26, style: .continuous))
        .overlay {
            if !videoOnly {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(videoOnly ? 0 : 0.28), radius: 20, y: 10)
    }

    @ViewBuilder
    private var videoInformation: some View {
        if let item = playback.currentItem {
            let presentation = library.presentation(for: item)
            HStack(spacing: 12) {
                VideoThumbnail(image: presentation?.thumbnail)
                    .frame(width: 96, height: 55)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOW PLAYING")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(CinemaTheme.electricBlue)
                    Text(item.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text(presentation?.detailLine ?? "Loading video details…")
                        .font(.caption)
                        .foregroundStyle(CinemaTheme.quietText)
                }
                Spacer(minLength: 0)
                if playback.hasResumePoint(for: item) {
                    Label("Resumed", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.1), in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .padding(11)
            .frame(maxWidth: 620)
            .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
        }
    }

    private var controlDeck: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(TimeFormatter.string(for: playback.currentTime))
                    .frame(width: 62, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { playback.currentTime },
                        set: { playback.seek(to: $0) }
                    ),
                    in: 0...max(playback.duration, 1)
                )
                .tint(CinemaTheme.electricBlue)
                Text("−\(TimeFormatter.string(for: max(playback.duration - playback.currentTime, 0)))")
                    .frame(width: 68, alignment: .trailing)
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 12) {
                ControlIconButton(icon: "backward.end.fill", label: "Previous video") {
                    playback.playPrevious()
                }
                .disabled(!playback.canAdvance)

                ControlIconButton(icon: "gobackward.10", label: "Back 10 seconds") {
                    playback.skip(by: -10)
                }

                ControlIconButton(
                    icon: playback.isPlaying ? "pause.fill" : "play.fill",
                    label: playback.isPlaying ? "Pause" : "Play",
                    prominent: true
                ) {
                    playback.togglePlayback()
                }

                ControlIconButton(icon: "goforward.10", label: "Forward 10 seconds") {
                    playback.skip(by: 10)
                }

                ControlIconButton(icon: "forward.end.fill", label: "Next video") {
                    playback.playNext()
                }
                .disabled(!playback.canAdvance)

                Spacer(minLength: 8)

                ControlIconButton(
                    icon: "shuffle",
                    label: playback.isShuffling ? "Shuffle on" : "Shuffle off",
                    isActive: playback.isShuffling
                ) {
                    playback.toggleShuffle()
                }
                .disabled(!playback.canAdvance)

                ControlIconButton(
                    icon: playback.repeatMode.icon,
                    label: playback.repeatMode.title,
                    isActive: playback.repeatMode != .off
                ) {
                    playback.cycleRepeatMode()
                }

                Menu {
                    ForEach(PlaybackRate.allCases) { rate in
                        Button(rate.title) { playback.setRate(rate) }
                    }
                } label: {
                    Label(playback.rate.title, systemImage: "speedometer")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: 72)
                }
                .menuStyle(.borderlessButton)
                .help("Playback speed")

                Menu {
                    ForEach(VideoLayout.allCases) { layout in
                        Button {
                            videoLayout = layout
                        } label: {
                            Label(layout.rawValue, systemImage: layout.icon)
                        }
                    }
                } label: {
                    Image(systemName: videoLayout.icon)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .help("Video fit")

                subtitleMenu

                if playback.audioTracks.count > 1 {
                    audioMenu
                }

                ControlIconButton(
                    icon: playback.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: playback.volume == 0 ? "Unmute" : "Mute"
                ) {
                    playback.toggleMute()
                }

                Slider(
                    value: Binding(
                        get: { playback.volume },
                        set: { playback.setVolume($0) }
                    ),
                    in: 0...1
                )
                .tint(CinemaTheme.electricBlue)
                .frame(width: 84)
                .accessibilityLabel("Volume")

                ControlIconButton(
                    icon: videoOnly ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    label: videoOnly ? "Exit full screen" : "Full screen"
                ) {
                    fullscreen.toggle()
                }
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
        .frame(maxWidth: 960)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(CinemaTheme.electricBlue.opacity(0.23), lineWidth: 1)
        }
    }

    private var subtitleMenu: some View {
        Menu {
            Button("Choose SRT Subtitle…") {
                subtitles.chooseSubtitle {
                    playback.selectEmbeddedSubtitle(id: nil)
                }
            }

            if subtitles.isLoaded {
                Divider()
                Text("External: \(externalSubtitleTitle)")
                Menu("Timing \(subtitles.syncOffsetTitle)") {
                    Button("Show 0.5s earlier") {
                        subtitles.adjustSync(by: 0.5)
                    }
                    Button("Show 0.5s later") {
                        subtitles.adjustSync(by: -0.5)
                    }
                    Divider()
                    Button("Reset timing") {
                        subtitles.resetSync()
                    }
                }
                Button("Turn off external subtitle") {
                    subtitles.clear()
                }
            }

            if !playback.embeddedSubtitleTracks.isEmpty {
                Divider()
                Menu("Embedded subtitles") {
                    Button("Off") {
                        playback.selectEmbeddedSubtitle(id: nil)
                    }
                    ForEach(playback.embeddedSubtitleTracks) { track in
                        Button {
                            subtitles.clear()
                            playback.selectEmbeddedSubtitle(id: track.id)
                        } label: {
                            Label(
                                track.title,
                                systemImage: playback.selectedEmbeddedSubtitleID == track.id ? "checkmark" : "captions.bubble"
                            )
                        }
                    }
                }
            }
        } label: {
            Image(systemName: subtitleIcon)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .help("Subtitles")
        .accessibilityLabel("Subtitles")
    }

    private var audioMenu: some View {
        Menu {
            ForEach(playback.audioTracks) { track in
                Button {
                    playback.selectAudioTrack(id: track.id)
                } label: {
                    Label(
                        track.title,
                        systemImage: playback.selectedAudioTrackID == track.id ? "checkmark" : "waveform"
                    )
                }
            }
        } label: {
            Image(systemName: "waveform")
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .help("Audio track")
        .accessibilityLabel("Audio track")
    }

    private var subtitleIcon: String {
        subtitles.isLoaded || playback.selectedEmbeddedSubtitleID != nil
            ? "captions.bubble.fill"
            : "captions.bubble"
    }

    private var externalSubtitleTitle: String {
        subtitles.loadedSubtitleName ?? "Subtitle"
    }
}

private struct SubtitleOverlay: View {
    let text: String
    let videoOnly: Bool

    var body: some View {
        Text(text)
            .font(.system(size: videoOnly ? 25 : 19, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .accessibilityLabel("Subtitle: \(text)")
    }
}

private struct ControlIconButton: View {
    let icon: String
    let label: String
    var prominent = false
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(prominent ? .title3.weight(.bold) : .body.weight(.semibold))
                .frame(width: prominent ? 44 : 30, height: prominent ? 44 : 30)
                .foregroundStyle(isActive ? CinemaTheme.electricBlue : .white)
                .background {
                    if prominent {
                        Circle().fill(CinemaTheme.accentGradient)
                    }
                }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(label)
        .help(label)
    }
}

struct MouseActivityTrackingView: NSViewRepresentable {
    let onActivity: () -> Void

    func makeNSView(context: Context) -> MouseTrackingNSView {
        MouseTrackingNSView(onActivity: onActivity)
    }

    func updateNSView(_ view: MouseTrackingNSView, context: Context) {
        view.onActivity = onActivity
    }
}

final class MouseTrackingNSView: NSView {
    var onActivity: () -> Void
    private var trackingArea: NSTrackingArea?

    init(onActivity: @escaping () -> Void) {
        self.onActivity = onActivity
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onActivity()
    }

    override func mouseMoved(with event: NSEvent) {
        onActivity()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.videoGravity = videoGravity
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
        view.videoGravity = videoGravity
    }
}
