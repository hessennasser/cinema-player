import Foundation

struct MediaItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let url: URL
    let bookmarkData: Data?
    let addedAt: Date

    /// True when the video lives behind a link rather than on this Mac.
    var isRemote: Bool { !url.isFileURL }

    init(id: UUID = UUID(), title: String, url: URL, bookmarkData: Data?, addedAt: Date = .now) {
        self.id = id
        self.title = title
        self.url = url
        self.bookmarkData = bookmarkData
        self.addedAt = addedAt
    }
}

struct PersistedMediaItem: Codable {
    let id: UUID
    let title: String
    let lastKnownURL: URL
    let bookmarkData: Data?
    let addedAt: Date

    init(item: MediaItem) {
        id = item.id
        title = item.title
        lastKnownURL = item.url
        bookmarkData = item.bookmarkData
        addedAt = item.addedAt
    }

    func makeMediaItem() -> MediaItem? {
        guard let resolvedURL = resolveURL() else { return nil }

        return MediaItem(
            id: id,
            title: title,
            url: resolvedURL,
            bookmarkData: bookmarkData,
            addedAt: addedAt
        )
    }

    private func resolveURL() -> URL? {
        guard lastKnownURL.isFileURL else { return lastKnownURL }
        guard let bookmarkData else { return lastKnownURL }

        var bookmarkIsStale = false
        do {
            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &bookmarkIsStale
            )
        } catch {
            return FileManager.default.fileExists(atPath: lastKnownURL.path) ? lastKnownURL : nil
        }
    }
}
