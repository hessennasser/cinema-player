import AppKit
import Foundation

@MainActor
final class MediaLibrary: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    @Published private var presentations: [MediaItem.ID: VideoPresentation] = [:]
    @Published private(set) var favoriteIDs: Set<MediaItem.ID> = []
    @Published var errorMessage: String?

    private let persistenceKey = "cinema-player.library.v1"
    private let favoritesPersistenceKey = "cinema-player.favorites.v1"

    init() {
        load()
        loadFavorites()
    }

    func chooseVideos() {
        let panel = NSOpenPanel()
        panel.title = "Choose videos to add"
        panel.message = "Cinema Player reads only the files you choose."
        panel.prompt = "Add Videos"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = MediaFileSupport.openPanelTypes

        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to add"
        panel.message = "Cinema Player scans the folder you choose for videos."
        panel.prompt = "Add Folder"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        guard panel.runModal() == .OK else { return }

        let videoURLs = panel.urls.flatMap(MediaFileSupport.videoFiles(in:))
        guard !videoURLs.isEmpty else {
            errorMessage = "Cinema Player found no supported videos in that folder."
            return
        }
        add(urls: videoURLs)
    }

    func add(urls: [URL]) {
        let newItems = urls.compactMap(makeItem)
        let knownLocations = Set(items.map(\.url.standardizedFileURL))
        let uniqueItems = newItems.filter { !knownLocations.contains($0.url.standardizedFileURL) }

        guard !uniqueItems.isEmpty else { return }
        items.append(contentsOf: uniqueItems)
        items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        save()
        uniqueItems.forEach(loadPresentation)
    }

    func remove(_ item: MediaItem) {
        items.removeAll { $0.id == item.id }
        favoriteIDs.remove(item.id)
        save()
        saveFavorites()
    }

    func revealInFinder(_ item: MediaItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func moveToTrash(_ item: MediaItem) {
        let didAccess = item.url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { item.url.stopAccessingSecurityScopedResource() }
        }

        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            remove(item)
        } catch {
            errorMessage = "Cinema Player could not move \(item.url.lastPathComponent) to the Trash."
        }
    }

    func clear() {
        items.removeAll()
        presentations.removeAll()
        save()
    }

    func presentation(for item: MediaItem) -> VideoPresentation? {
        presentations[item.id]
    }

    func isFavorite(_ item: MediaItem) -> Bool {
        favoriteIDs.contains(item.id)
    }

    func toggleFavorite(_ item: MediaItem) {
        if favoriteIDs.contains(item.id) {
            favoriteIDs.remove(item.id)
        } else {
            favoriteIDs.insert(item.id)
        }
        saveFavorites()
    }

    private func makeItem(from url: URL) -> MediaItem? {
        guard MediaFileSupport.isSupported(url) else {
            errorMessage = "\(url.lastPathComponent) is not a supported video file."
            return nil
        }

        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return MediaItem(
                title: url.deletingPathExtension().lastPathComponent,
                url: url,
                bookmarkData: bookmarkData
            )
        } catch {
            errorMessage = "Cinema Player could not save access to \(url.lastPathComponent)."
            return nil
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else { return }

        do {
            let savedItems = try JSONDecoder().decode([PersistedMediaItem].self, from: data)
            items = savedItems.compactMap { $0.makeMediaItem() }
            items.forEach(loadPresentation)
        } catch {
            errorMessage = "Your saved library could not be restored."
        }
    }

    private func save() {
        do {
            let savedItems = items.map(PersistedMediaItem.init)
            let data = try JSONEncoder().encode(savedItems)
            UserDefaults.standard.set(data, forKey: persistenceKey)
        } catch {
            errorMessage = "Cinema Player could not save your library."
        }
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: favoritesPersistenceKey),
              let savedFavoriteIDs = try? JSONDecoder().decode(Set<MediaItem.ID>.self, from: data) else {
            return
        }
        favoriteIDs = savedFavoriteIDs.intersection(Set(items.map(\.id)))
    }

    private func saveFavorites() {
        guard let data = try? JSONEncoder().encode(favoriteIDs) else { return }
        UserDefaults.standard.set(data, forKey: favoritesPersistenceKey)
    }

    private func loadPresentation(for item: MediaItem) {
        Task {
            let presentation = await VideoPresentationLoader.load(for: item.url)
            guard items.contains(where: { $0.id == item.id }) else { return }
            presentations[item.id] = presentation
        }
    }
}
