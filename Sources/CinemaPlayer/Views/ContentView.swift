import SwiftUI
import UniformTypeIdentifiers

private enum LibraryScope: String, CaseIterable, Identifiable {
    case all = "All titles"
    case favorites = "Favorites"
    case recent = "Recently added"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: "rectangle.stack.fill"
        case .favorites: "heart.fill"
        case .recent: "clock.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var library: MediaLibrary
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var fullscreen: VideoOnlyFullscreenController
    @EnvironmentObject private var subtitles: SubtitleController
    @State private var selection: MediaItem.ID?
    @State private var searchText = ""
    @State private var scope: LibraryScope = .all
    @State private var isDropTargeted = false

    private var visibleItems: [MediaItem] {
        let scopedItems: [MediaItem]
        switch scope {
        case .all:
            scopedItems = library.items
        case .favorites:
            scopedItems = library.items.filter(library.isFavorite)
        case .recent:
            scopedItems = library.items.sorted { $0.addedAt > $1.addedAt }
        }

        guard !searchText.isEmpty else { return scopedItems }
        return scopedItems.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if fullscreen.isActive, playback.currentItem != nil {
                PlayerScreen(videoOnly: true)
            } else {
                libraryBrowser
            }
        }
        .tint(CinemaTheme.electricBlue)
        .onChange(of: selection) { _, selectedID in
            guard let selectedID,
                  let selectedItem = library.items.first(where: { $0.id == selectedID }) else {
                return
            }
            playback.play(selectedItem)
        }
        .alert("Cinema Player", isPresented: Binding(
            get: { library.errorMessage != nil || playback.errorMessage != nil || subtitles.errorMessage != nil },
            set: {
                if !$0 {
                    library.errorMessage = nil
                    playback.errorMessage = nil
                    subtitles.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                library.errorMessage = nil
                playback.errorMessage = nil
                subtitles.errorMessage = nil
            }
        } message: {
            Text(library.errorMessage ?? playback.errorMessage ?? subtitles.errorMessage ?? "Unknown error")
        }
    }

    private var libraryBrowser: some View {
        NavigationSplitView {
            librarySidebar
        } detail: {
            playerArea
        }
        .navigationSplitViewStyle(.balanced)
        .background(CinemaTheme.night)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(CinemaTheme.electricBlue, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                CinemaMark(size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cinema Player")
                        .font(.headline.weight(.bold))
                    Text("YOUR LOCAL CINEMA")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(CinemaTheme.quietText)
                }
            }

            Button(action: library.chooseVideos) {
                Label("Add videos", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(CinemaTheme.electricBlue)

            VStack(spacing: 5) {
                ForEach(LibraryScope.allCases) { option in
                    Button {
                        scope = option
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: option.icon)
                                .frame(width: 18)
                            Text(option.rawValue)
                            Spacer()
                            if option == .all {
                                Text("\(library.items.count)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(CinemaTheme.quietText)
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(scope == option ? .white : CinemaTheme.quietText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(scope == option ? CinemaTheme.electricBlue.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().overlay(.white.opacity(0.1))

            HStack {
                Text("Your library")
                    .font(.headline)
                Spacer()
                if !visibleItems.isEmpty {
                    Text("\(visibleItems.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CinemaTheme.quietText)
                }
            }

            TextField("Search titles", text: $searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .trailing) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(CinemaTheme.quietText)
                        .padding(.trailing, 10)
                }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if visibleItems.isEmpty {
                        emptyLibraryMessage
                    } else {
                        ForEach(visibleItems) { item in
                            LibraryRow(
                                item: item,
                                presentation: library.presentation(for: item),
                                isActive: playback.currentItem?.id == item.id,
                                isFavorite: library.isFavorite(item),
                                resumeTime: playback.resumeTime(for: item),
                                play: {
                                    if selection == item.id {
                                        playback.play(item)
                                    } else {
                                        selection = item.id
                                    }
                                },
                                toggleFavorite: { library.toggleFavorite(item) },
                                remove: {
                                    if selection == item.id { selection = nil }
                                    library.remove(item)
                                }
                            )
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(16)
        .frame(minWidth: 260, idealWidth: 292, maxWidth: 340)
        .background(CinemaTheme.night)
        .foregroundStyle(.white)
        .navigationTitle("Cinema Player")
    }

    private var emptyLibraryMessage: some View {
        VStack(spacing: 9) {
            Image(systemName: scope == .favorites ? "heart.slash" : "film.stack")
                .font(.title2)
                .foregroundStyle(CinemaTheme.quietText)
            Text(scope == .favorites ? "No favorites yet" : "Your library is ready")
                .font(.subheadline.weight(.semibold))
            Text(scope == .favorites ? "Use the heart on any title to keep it close." : "Add a video from your Mac to start watching.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(CinemaTheme.quietText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .cinemaSurface(cornerRadius: 16)
    }

    @ViewBuilder
    private var playerArea: some View {
        if playback.currentItem != nil {
            PlayerScreen(videoOnly: false)
        } else {
            EmptyPlayerView(addVideos: library.chooseVideos)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            for provider in fileProviders {
                guard let url = await loadFileURL(from: provider) else { continue }
                urls.append(contentsOf: supportedVideos(at: url))
            }
            if !urls.isEmpty {
                library.add(urls: urls)
            }
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private func supportedVideos(at url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return []
        }

        guard isDirectory.boolValue else {
            return MediaFileSupport.isSupported(url) ? [url] : []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter(MediaFileSupport.isSupported)
    }
}

private struct LibraryRow: View {
    let item: MediaItem
    let presentation: VideoPresentation?
    let isActive: Bool
    let isFavorite: Bool
    let resumeTime: Double
    let play: () -> Void
    let toggleFavorite: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: play) {
                HStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        VideoThumbnail(image: presentation?.thumbnail)
                            .frame(width: 86, height: 52)
                        if isActive {
                            Image(systemName: "waveform")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(CinemaTheme.signalRed, in: Circle())
                                .padding(4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .foregroundStyle(.white)
                        Text(presentation?.detailLine ?? "Reading video details…")
                            .font(.caption2)
                            .foregroundStyle(CinemaTheme.quietText)
                            .lineLimit(1)
                        if resumeTime >= 15 {
                            Label("Resume at \(TimeFormatter.string(for: resumeTime))", systemImage: "play.fill")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(CinemaTheme.electricBlue)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.caption)
                    .foregroundStyle(isFavorite ? CinemaTheme.signalRed : CinemaTheme.quietText)
                    .frame(width: 25, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(8)
        .background(isActive ? CinemaTheme.electricBlue.opacity(0.2) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(isActive ? CinemaTheme.electricBlue.opacity(0.72) : .white.opacity(0.05), lineWidth: 1)
        }
        .contextMenu {
            Button("Play", action: play)
            Button(isFavorite ? "Remove from favorites" : "Add to favorites", action: toggleFavorite)
            Divider()
            Button("Remove from library", role: .destructive, action: remove)
        }
    }
}

struct VideoThumbnail: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "film")
                    .font(.title3)
                    .foregroundStyle(CinemaTheme.electricBlue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CinemaTheme.electricBlue.opacity(0.12))
            }
        }
        .frame(width: 82, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct EmptyPlayerView: View {
    let addVideos: () -> Void

    var body: some View {
        ZStack {
            CinemaTheme.playerGradient.ignoresSafeArea()
            Circle()
                .fill(CinemaTheme.electricBlue.opacity(0.14))
                .frame(width: 480, height: 480)
                .blur(radius: 75)
                .offset(x: 130, y: -100)

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(CinemaTheme.surface)
                        .frame(width: 114, height: 84)
                    CinemaMark(size: 54)
                }

                VStack(spacing: 9) {
                    Text("Your cinema is ready")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                    Text("Import movies from your Mac. They stay private, on your device.")
                        .font(.body)
                        .foregroundStyle(CinemaTheme.quietText)
                }

                Button(action: addVideos) {
                    Label("Choose videos", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(CinemaTheme.electricBlue)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(50)
            .cinemaSurface(cornerRadius: 28)
        }
    }
}
